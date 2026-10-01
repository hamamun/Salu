import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent;
import 'package:flutter/material.dart';

import '../../core/clock_format.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/settings_service.dart';
import '../../core/timeline_thumbnail_service.dart';
import '../../core/transport_actions.dart';
import '../../theme/app_theme.dart';
import '../widgets/live_light.dart';
import 'hover_chip.dart';

/// Formats live in `lib/core/clock_format.dart` (formatClock here,
/// formatClockCompact in the Resume toast).

/// SALU's unified timeline — identical for video and audio.
///
/// A paste-window style thick bar: a gentle light fill grows from the left
/// over a darker track. The time readouts live INSIDE the bar:
///   · left   — playback position   (hh:mm:ss)
///   · middle — −remaining time     (−hh:mm:ss, hidden when narrow)
///   · right  — total media time    (hh:mm:ss)
/// all in one single quiet tone.
///
/// Interactions (playback is never paused or disturbed by any of them):
///   · click anywhere            → instant precise jump
///   · press + drag, release     → live scrub preview, jump on release
///   · mouse wheel over the bar  → ±1 second per notch (fine scrub)
///   · hover                     → faint minute-rule ticks + a time chip
///                                below the bar showing the target time
///
/// Channel mode (§10.8a): the bar is EMPTY and inert — no fill, no
/// readouts (not even zeros), no hover, no chip, no pointer response at
/// all. A live stream has no position. Its only content is the still
/// soft light ([StillSoftLight], point 9 Final option A): present while
/// data arrives, quietly fading away when the stream stalls.
///
/// The track and the progress fill are surface paints and follow the
/// global **Overlay transparency** setting, like every other SALU-owned
/// surface. The playhead notch, the ruler ticks and the in-bar time
/// readouts are foregrounds and stay fully opaque, so the position stays
/// readable while the bar behind it is see-through.
class MediaTimeline extends StatefulWidget {
  const MediaTimeline({super.key});

  /// Full widget height: the bar plus room for the chip underneath.
  static const double widgetHeight = 48;

  /// Visual height of the thick bar itself.
  static const double barHeight = 23;

  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  final PlayerService _player = PlayerService.instance;
  late final Listenable _merged;

  /// Pointer x as a fraction of the bar (0..1) — shows the hover chip.
  double? _hoverFrac;

  /// The frame shown under the cursor — from the shared cache
  /// ([TimelineThumbnailService]); null while the aimed second has no
  /// frame yet.
  Uint8List? _hoverThumbnail;

  /// The aimed second ('$path@$timeMs') — a decoded frame is shown only
  /// when it is for exactly this one, so a late frame for a second the
  /// cursor already left is never painted at the wrong spot.
  String? _thumbnailKey;

  /// True while this widget has the background strip armed.
  bool _stripArmed = false;

  /// Press/drag scrub position (0..1) — preview only; committed on release.
  double? _pressFrac;

  /// X where the current press started (for the drag slop check).
  double? _downX;

  /// Whether the press has moved beyond slop (i.e. it is a drag, not a
  /// click). A click commits on release; a drag previews live and commits
  /// on release at the final position.
  bool _dragging = false;

  /// Movement (in logical px) that turns a press into a drag.
  static const double _dragSlop = 6;

  @override
  void initState() {
    super.initState();
    _merged = Listenable.merge(<Listenable>[
      _player.position,
      _player.duration,
      _player.transportState,
      _player.isBuffering,
      _player.currentPath,
      QueueService.instance.items,
    ]);
    _merged.addListener(_syncStrip);
    _syncStrip();
    TimelineThumbnailService.instance.onFrame = _onFrame;
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  Duration get _duration => _player.duration.value;

  /// The hover preview is a pure cache lookup: the strip lane (background
  /// grid) and the fine lane (this exact second, [requestFine]) keep the
  /// cache warm, so the frame is usually here the instant the pointer
  /// enters a new second — the preview flows continuously while scrubbing,
  /// in either direction, without waiting on a decode.
  void _queueThumbnail(double frac) {
    final String? path = _player.currentPath.value;
    if (path == null || path.contains('://') || !_usable) return;
    final int timeMs = (_targetForFrac(frac).inMilliseconds ~/ 1000) * 1000;
    final String key = '$path@$timeMs';
    if (key == _thumbnailKey) return;
    _thumbnailKey = key;
    final TimelineThumbnailService thumbs =
        TimelineThumbnailService.instance;
    final Uint8List? cached = thumbs.lookup(path, timeMs);
    if (cached != null) {
      setState(() => _hoverThumbnail = cached);
      return;
    }
    setState(() => _hoverThumbnail = null);
    thumbs.requestFine(path, timeMs);
  }

  /// A decoded frame landed (fine lane, or the strip grid filling the
  /// aimed second from behind). Shown only when it is the second the
  /// cursor is aiming at right now.
  void _onFrame(String path, int timeMs, Uint8List bytes) {
    if (!mounted) return;
    final String? key = _thumbnailKey;
    if (key == null || key != '$path@$timeMs') return;
    setState(() => _hoverThumbnail = bytes);
  }

  /// Arms or disarms the background strip with the media's state. The
  /// service is idempotent per (path, duration), so the frequent position
  /// ticks this listener rides on cost one comparison each.
  void _syncStrip() {
    final String? path = _player.currentPath.value;
    if (path == null || path.contains('://') || !_usable) {
      if (_stripArmed) {
        _stripArmed = false;
        TimelineThumbnailService.instance.release();
      }
      return;
    }
    if (!_stripArmed) {
      _stripArmed = true;
      TimelineThumbnailService.instance.ensureStrip(path, _duration);
    }
  }

  void _clearThumbnail() {
    _thumbnailKey = null;
    if (_hoverThumbnail != null) setState(() => _hoverThumbnail = null);
  }

  @override
  void dispose() {
    final TimelineThumbnailService thumbs =
        TimelineThumbnailService.instance;
    if (thumbs.onFrame == _onFrame) thumbs.onFrame = null;
    _merged.removeListener(_syncStrip);
    // The chrome's timeline lives for the app's lifetime, so dispose is
    // app shutdown (or a structural change) — release the grid only when
    // the media is actually gone, so a remount with the video still
    // current reuses the armed strip instead of restarting it.
    if (_stripArmed && !(_usable && _player.currentPath.value != null)) {
      thumbs.release();
    }
    super.dispose();
  }

  /// A live channel is loaded — the empty inert light state (§10.8a).
  bool get _live => _player.isLiveMode;

  /// The bar is live only while the engine actually holds an item —
  /// while STOPPED it is inert and reads zeros (the parked queue has no
  /// timeline), and while idle there is simply nothing to show. Channel
  /// mode is never usable: the light bar below takes over instead.
  bool get _usable =>
      _duration > Duration.zero && _player.hasMedia.value && !_live;

  // ── Seek helpers ──────────────────────────────────────────────────────

  Duration _targetForFrac(double frac) {
    return Duration(milliseconds: (frac * _duration.inMilliseconds).round());
  }

  void _commitFrac(double frac) {
    if (!_usable) return;
    // A timeline click is another transport action — it resets both
    // seek ramps (the outline's ramp rule).
    TransportActions.instance.resetSeekRamps();
    _player.seekTo(_targetForFrac(frac));
  }

  // ── Pointer handling (raw listener — no gesture arena, so presses are
  //    tracked 1:1: preview appears the instant the button goes down, a
  //    stationary click commits on release, a drag previews live and
  //    commits where it is released) ────────────────────────────────────

  double _fracAt(double dx, double width) =>
      _clamp01(width <= 0 ? 0 : dx / width);

  void _onPointerDown(PointerDownEvent e, double w) {
    if (!_usable) return;
    _downX = e.localPosition.dx;
    _dragging = false;
    setState(() => _pressFrac = _fracAt(e.localPosition.dx, w));
  }

  void _onPointerMove(PointerMoveEvent e, double w) {
    if (_pressFrac == null) return; // Button was not pressed on this bar.
    final double dx = e.localPosition.dx;
    if (!_dragging) {
      final double? downX = _downX;
      if (downX == null || (dx - downX).abs() < _dragSlop) return;
      _dragging = true;
    }
    setState(() => _pressFrac = _fracAt(dx, w));
  }

  void _onPointerUp(PointerUpEvent e, double w) {
    final double? frac = _pressFrac;
    if (frac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Click (no drag) and drag both commit exactly where the pointer was
    // released — that is also the press position for a plain click.
    _commitFrac(frac);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_pressFrac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Cancel (rare on desktop) = abandon the scrub, no seek.
  }

  void _onWheel(double dy) {
    if (!_usable) return;
    // Wheel down (positive) scrubs forward, wheel up backward — 1 second
    // per notch. seekTo clamps at the media bounds. Like every seek
    // from outside the ramp, this resets the ramp sequences.
    TransportActions.instance.resetSeekRamps();
    _player.seekBy(
      dy > 0 ? const Duration(seconds: 1) : const Duration(seconds: -1),
    );
  }

  // ── Aiming ruler (minute ticks) ───────────────────────────────────────

  /// Chooses a tick step (from a friendly ladder) so neighboring ticks sit
  /// roughly 60–120 px apart on the given bar width.
  Duration _tickStep(double width) {
    const List<int> ladderMs = <int>[
      500,
      1000,
      2000,
      5000,
      10000,
      15000,
      30000,
      60000,
      120000,
      300000,
      600000,
      900000,
      1800000,
      3600000,
      7200000,
      14400000,
      28800000,
    ];
    final int durMs = _duration.inMilliseconds;
    final double targetMs = durMs * 72 / (width <= 0 ? 1 : width);
    for (final int ms in ladderMs) {
      if (ms >= targetMs) return Duration(milliseconds: ms);
    }
    return Duration(milliseconds: ladderMs.last);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: (BuildContext context, Widget? _) {
        final bool usable = _usable;
        return SizedBox(
          height: MediaTimeline.widgetHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double w = constraints.maxWidth;
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent e) => _onPointerDown(e, w),
                onPointerMove: (PointerMoveEvent e) => _onPointerMove(e, w),
                onPointerUp: (PointerUpEvent e) => _onPointerUp(e, w),
                onPointerCancel: _onPointerCancel,
                onPointerSignal: (PointerSignalEvent event) {
                  if (event is PointerScrollEvent) {
                    _onWheel(event.scrollDelta.dy);
                  }
                },
                child: MouseRegion(
                  onHover: (PointerHoverEvent e) {
                    if (!usable) return;
                    final double frac = _fracAt(e.localPosition.dx, w);
                    setState(() => _hoverFrac = frac);
                    _queueThumbnail(frac);
                  },
                  onExit: (PointerExitEvent e) {
                    if (_hoverFrac != null) setState(() => _hoverFrac = null);
                    _clearThumbnail();
                  },
                  child: _buildBody(w, usable),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(double w, bool usable) {
    final bool live = _live;
    final Duration pos = _player.position.value;
    final Duration dur = usable ? _duration : Duration.zero;
    final int durMs = dur.inMilliseconds;

    // The boundary shown on the bar: the scrub preview while pressing or
    // dragging, the real playback position otherwise.
    final double boundaryFrac =
        _pressFrac ?? (usable ? _clamp01(pos.inMilliseconds / durMs) : 0);
    final double boundaryX = boundaryFrac * w;

    // Time readouts.
    final Duration shown =
        _pressFrac != null && usable ? _targetForFrac(_pressFrac!) : pos;
    final Duration remaining =
        dur - shown > Duration.zero ? dur - shown : Duration.zero;
    final bool showTicks = usable && (_hoverFrac != null || _pressFrac != null);
    final Duration tickStep = usable ? _tickStep(w) : Duration.zero;

    // Tooltip chip — target time under the cursor / thumb.
    const double chipWidth = 96; // HoverChip's timeline width
    final double? chipFrac = _pressFrac ?? _hoverFrac;
    final bool showChip = usable && chipFrac != null;
    final double clampedChipFrac = chipFrac?.clamp(0.0, 1.0).toDouble() ?? 0;
    final double chipLeft = w <= chipWidth
        ? 0
        : (clampedChipFrac * w - chipWidth / 2)
            .clamp(0.0, w - chipWidth)
            .toDouble();

    final TextStyle labelStyle = TextStyle(
      color: context.palette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1,
      letterSpacing: 0.4,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      shadows: <Shadow>[Shadow(color: Color(0x99000000), blurRadius: 2)],
    );

    final bool previewAbove =
        SettingsService.instance.controllerPlacement.value ==
            ControllerPlacement.bottom ||
        SettingsService.instance.controllerPlacement.value ==
            ControllerPlacement.bottomEdge;
    const double previewWidth = 192;
    const double previewHeight = 108;
    final double previewLeft = w <= previewWidth
        ? 0
        : (clampedChipFrac * w - previewWidth / 2)
            .clamp(0.0, w - previewWidth)
            .toDouble();
    final double previewTop = previewAbove
        ? -(previewHeight + 5)
        : MediaTimeline.barHeight + 5;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // ── The thick bar ─────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaTimeline.barHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: <Widget>[
                // Track. The track and the progress fill are SALU-owned
                // surface paints like any panel, so they follow the global
                // Overlay transparency and fade with the rest of the chrome.
                // The playhead notch, the ruler ticks and the in-bar
                // readouts below are FOREGROUND marks and stay fully
                // opaque — they are how the position stays readable once
                // the bar behind them is see-through.
                Positioned.fill(
                  child: ColoredBox(
                    color: context.overlayTint(context.palette.barTrack),
                  ),
                ),
                // Channel mode: only the still soft light (§10.8a) — no
                // fill, no thumb, no ruler, no readouts (not even zeros).
                // The `!live` gates below are belt-and-braces: `_usable`
                // is already false while live, but the light state must
                // never degrade into the stopped-zeros state.
                if (live)
                  Positioned.fill(
                    child: StillSoftLight(visible: _player.isLiveReceiving),
                  ),
                // Paste-window style fill.
                if (!live && boundaryX > 0)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: boundaryX,
                    child: ColoredBox(
                      color: context.overlayTint(context.palette.barFill),
                    ),
                  ),
                // Aiming ruler (hover / scrub) — faint vertical ticks.
                if (showTicks && tickStep > Duration.zero)
                  for (Duration t = tickStep; t < dur; t += tickStep)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: w * (t.inMilliseconds / durMs),
                      child: ColoredBox(
                        color: context.palette.barTick,
                        child: SizedBox(width: 1),
                      ),
                    ),
                // Flat playhead notch at the fill edge (no glow). Hidden
                // only at the exact extremes where it would clip off-bar.
                if (usable && boundaryX > 0.5 && boundaryX < w - 1.5)
                  Positioned(
                    top: 4,
                    bottom: 4,
                    left: boundaryX - 1,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: context.palette.barThumb,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                // Time readouts — inside the bar, all one tone. Absent
                // entirely in channel mode: the light bar carries no
                // numbers at all (§10.8a).
                if (!live)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: <Widget>[
                            Text(
                              usable ? formatClock(shown) : '00:00:00',
                              style: labelStyle,
                            ),
                            const Spacer(),
                            if (w > 560)
                              Text(
                                usable ? '-${formatClock(remaining)}' : '',
                                style: labelStyle,
                              ),
                            const Spacer(),
                            Text(
                              usable ? formatClock(dur) : '00:00:00',
                              style: labelStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Preview is intentionally placed on the video-facing side of the
        // bar: underneath top-mounted chrome, above bottom-mounted chrome.
        if (showChip &&
            _hoverThumbnail != null &&
            _thumbnailKey?.startsWith('${_player.currentPath.value}@') == true)
          Positioned(
            top: previewTop,
            left: previewLeft,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: Image.memory(
                    _hoverThumbnail!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        if (showChip)
          Positioned(
            top: showChip && _hoverThumbnail != null
                ? (previewAbove ? -29 : MediaTimeline.barHeight + 5 + previewHeight - 27)
                : MediaTimeline.barHeight + 2,
            left: chipLeft,
            child: HoverChip(
              label: formatClock(_targetForFrac(clampedChipFrac)),
            ),
          ),
      ],
    );
  }
}
