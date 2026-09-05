import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ui/osd/osd_controller.dart';
import 'clock_format.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// One tiny seek-step state machine (outline · §2 "Seek behavior").
///
/// - Quick tap: `±5 s`.
/// - Rapid continuous fires (clicks or hold repeats): `5 s, 10 s, 15 s,
///   20 s…` — step *n* = *n* × 5 s, no ceiling.
/// - A gap > [gap] since the previous fire resets to 5 s.
/// - Hold repeat cadence (300 ms) is shorter than [gap] (400 ms), so a
///   hold can never reset itself.
///
/// Forward and backward are two independent instances — `>>` then `<<`
/// never continue each other's ramp.
class SeekRamp {
  SeekRamp(this._direction);

  /// +1 forward, −1 backward.
  final int _direction;

  /// Fires closer together than this continue the ramp; a larger gap
  /// resets it. (One constant to tune on device.)
  static const Duration gap = Duration(milliseconds: 400);

  static const Duration _unit = Duration(seconds: 5);

  int _step = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// The next step's delta (and the ramp's bookkeeping update).
  Duration next() {
    final DateTime now = DateTime.now();
    _step = now.difference(_last) > gap ? 1 : _step + 1;
    _last = now;
    return _unit * (_step * _direction);
  }

  /// Resets the sequence (fired on every *other* transport action and
  /// on timeline clicks — time gaps are handled inside [next]).
  void reset() {
    _step = 0;
  }
}

/// The single transport facade (outline · §2 "Behaviors").
///
/// Every action is defined once here — player call + OSD card — and the
/// buttons, the keyboard and the video-canvas tap all call it. The two
/// bars (timeline, volume) keep calling `PlayerService` directly: they
/// have their own live readouts, no deck.
class TransportActions {
  TransportActions._internal();

  /// The one and only transport facade.
  static final TransportActions instance = TransportActions._internal();

  final PlayerService player = PlayerService.instance;
  final OsdController osd = OsdController.instance;
  final QueueService queue = QueueService.instance;

  /// Two independent seek ramps.
  final SeekRamp seekForwardRamp = SeekRamp(1);
  final SeekRamp seekBackwardRamp = SeekRamp(-1);

  /// Resets both ramps (called by the timeline on a committed seek and
  /// by every transport action below).
  void resetSeekRamps() {
    seekForwardRamp.reset();
    seekBackwardRamp.reset();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Play / Pause — and while STOPPED, Play resumes the parked item
  /// from the stop memory (the Resume toast fires from the open path).
  void playOrPause() {
    resetSeekRamps(); // every other transport action resets the ramps
    switch (player.transportState.value) {
      case TransportState.idle:
        return; // nothing loaded — the mark is dimmed
      case TransportState.stopped:
        osd.dismissResumeToast();
        // A resumable memory surfaces through the Resume toast; a
        // memory under the shared threshold (or a stream with no
        // duration) starts the item from the beginning with the plain
        // `>` card, no toast.
        final bool resumes = player.stopMemoryWillResume;
        _run(player.playFromStop().then((_) {
          if (!resumes) {
            osd.show(const OsdTransportCard(mark: OsdMark.play));
          }
        }));
      case TransportState.paused:
        osd.dismissResumeToast();
        osd.show(const OsdTransportCard(mark: OsdMark.play));
        _run(player.play());
      case TransportState.playing:
        osd.dismissResumeToast();
        osd.show(const OsdTransportCard(mark: OsdMark.pause));
        _run(player.pause());
    }
  }

  /// Stop — the third state. No card: the canvas change IS the feedback.
  void stop() {
    resetSeekRamps();
    switch (player.transportState.value) {
      case TransportState.playing:
      case TransportState.paused:
        osd.dismiss();
        _run(player.stop());
      case TransportState.idle:
      case TransportState.stopped:
        return; // no-op (dimmed in the UI)
    }
  }

  /// Previous item — one rule in every state. The card names the item
  /// (or `00:00:00` on a same-item restart). Titles are read from the
  /// queue, not the engine's title stream — the card must be right the
  /// instant the action fires.
  void previous() {
    if (!queue.hasQueue) return;
    resetSeekRamps();
    osd.dismissResumeToast();
    final bool restart = _previousRestartsThisItem();
    final int from = queue.index.value;
    _run(player.previous().then((_) {
      final List<String> paths = queue.paths.value;
      final int to = restart ? from : from - 1;
      final String text = restart
          ? '00:00:00'
          : (to >= 0 && to < paths.length
              ? MediaUtils.displayName(paths[to])
              : '00:00:00');
      osd.show(OsdTransportCard(mark: OsdMark.previous, text: text));
    }));
  }

  /// The Previous rule: position (stop memory while stopped) > 3 s, or
  /// first item → THIS item restarts from `0:00`.
  bool _previousRestartsThisItem() {
    final TransportState state = player.transportState.value;
    final Duration pos =
        (state == TransportState.stopped && player.stopMemory.value != null)
            ? player.stopMemory.value!.position
            : player.position.value;
    return pos > const Duration(seconds: 3) || queue.index.value <= 0;
  }

  /// Next item — dimmed in the UI when there is none.
  void next() {
    if (!queue.hasNext) return;
    resetSeekRamps();
    osd.dismissResumeToast();
    final int to = queue.index.value + 1;
    final List<String> paths = queue.paths.value;
    _run(player.next().then((_) {
      osd.show(OsdTransportCard(
        mark: OsdMark.next,
        text: to < paths.length ? MediaUtils.displayName(paths[to]) : null,
      ));
    }));
  }

  /// One seek-forward step (button press, hold repeat, → key repeat).
  /// The card always shows the step just applied next to the new time:
  /// `>>  +15s  01:12:34`.
  void seekForward() {
    if (!_seekable) return;
    osd.dismissResumeToast();
    _applySeek(seekForwardRamp.next(), OsdMark.seekForward);
  }

  /// One seek-backward step — the perfect mirror.
  void seekBackward() {
    if (!_seekable) return;
    osd.dismissResumeToast();
    _applySeek(seekBackwardRamp.next(), OsdMark.seekBack);
  }

  bool get _seekable {
    switch (player.transportState.value) {
      case TransportState.playing:
      case TransportState.paused:
        return true;
      case TransportState.idle:
      case TransportState.stopped:
        return false;
    }
  }

  void _applySeek(Duration delta, OsdMark mark) {
    final Duration from = player.position.value;
    final Duration target = from + delta;
    final Duration clamped = _clamp(target);
    final Duration applied = clamped - from;
    final bool backwards = delta < Duration.zero || applied < Duration.zero;
    final Duration magnitude =
        applied < Duration.zero ? -applied : applied;
    _run(player.seekBy(delta).then((_) {
      osd.show(OsdTransportCard(
        mark: mark,
        text:
            '${backwards ? '-' : '+'}${magnitude.inSeconds}s  ${formatClock(player.position.value)}',
      ));
    }));
  }

  Duration _clamp(Duration t) {
    if (t < Duration.zero) return Duration.zero;
    final Duration dur = player.duration.value;
    if (dur > Duration.zero && t > dur) return dur;
    return t;
  }

  /// Volume +5 (↑ key) — unmutes when it leaves silence. Discrete
  /// actions flash the deck; the volume BAR never does (it has its own
  /// live readout) — so the card is emitted here, not in the bar.
  void volumeUp() {
    _run(player.stepVolume(5).then((_) => _volumeCard()));
  }

  /// Volume −5 (↓ key).
  void volumeDown() {
    _run(player.stepVolume(-5).then((_) => _volumeCard()));
  }

  /// Mute toggle (M key and the speaker mark).
  void toggleMute() {
    _run(player.toggleMute().then((_) => _volumeCard()));
  }

  void _volumeCard() {
    osd.show(OsdVolumeCard(muted: player.isMuted.value));
  }

  /// The Resume toast's Restart action — the only way Stop ever becomes
  /// "start over": jump to `0:00` and play.
  void restart() {
    resetSeekRamps();
    osd.dismiss();
    _run(player.seekTo(Duration.zero).then((_) => player.play()));
  }

  void _run(Future<void> future) {
    unawaited(future.catchError((Object e) {
      debugPrint('[SALU/transport] $e');
    }));
  }
}
