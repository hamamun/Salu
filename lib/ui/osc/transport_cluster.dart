import 'package:flutter/material.dart';

import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/transport_actions.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/transport_marks.dart';
import 'volume_bar.dart';

/// The transport cluster + sound group (outline · §2 — final layout).
///
/// ```
///  >    □    |<<    >>|    <<    >>      ⊂))  [▓▓▓▓62%]
/// ```
///
/// Order after the Open `+`: Play/Pause · Stop · Previous · Next ·
/// Seek backward · Seek forward, then the sound group (speaker + volume
/// bar) attached to the cluster. Pitch is the grouping: 6 px inside a
/// group, 14 px between groups, 26 px before the sound group — nothing
/// is ever drawn around a group or an icon.
///
/// Every control is a [SaluIconButton] (the one hover recipe); the two
/// seek marks use press-and-hold (`onHoldRepeat`) driving the ramp.
/// Enable states follow the matrix in the outline exactly, read from
/// one [PlayerService.transportState] notifier.
class TransportCluster extends StatelessWidget {
  const TransportCluster({super.key});

  /// Gap inside a group (between the pair members).
  static const double _inGroup = 6;

  /// Gap between the three transport groups.
  static const double _betweenGroups = 14;

  /// Gap before the sound group.
  static const double _beforeSound = 26;

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    final QueueService queue = QueueService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        player.transportState,
        player.isPlaying,
        queue.paths,
        queue.index,
      ]),
      builder: (BuildContext context, Widget? _) {
        final TransportState state = player.transportState.value;
        final bool engineLive = state == TransportState.playing ||
            state == TransportState.paused;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ── Group 1 · playback: play/pause + stop ─────────────────
            _PlayPauseButton(state: state),
            const SizedBox(width: _inGroup),
            SaluIconButton(
              tooltip: 'Stop',
              // Stop dims while stopped and while idle; it is never a
              // "start over" (Prev's restart and the toast's Restart
              // are the only restarts).
              enabled: engineLive,
              onTap: TransportActions.instance.stop,
              child: const StopMark(),
            ),

            const SizedBox(width: _betweenGroups),

            // ── Group 2 · items: previous + next ───────────────────────
            SaluIconButton(
              tooltip: 'Previous',
              // `|<<` never dims while a queue exists — it can always
              // restart the item.
              enabled: queue.hasQueue,
              onTap: TransportActions.instance.previous,
              child: const PreviousMark(),
            ),
            const SizedBox(width: _inGroup),
            SaluIconButton(
              tooltip: 'Next',
              // Dimmed when there is no next item (single file = always
              // dim: honest).
              enabled: queue.hasNext,
              onTap: TransportActions.instance.next,
              child: const NextMark(),
            ),

            const SizedBox(width: _betweenGroups),

            // ── Group 3 · time: seek backward + forward ────────────────
            SaluIconButton(
              tooltip: 'Seek backward',
              // Seeks dim while stopped (nothing to seek into) and idle.
              enabled: engineLive,
              onTap: () {}, // hold-repeat drives the ramp
              onHoldRepeat: TransportActions.instance.seekBackward,
              child: const SeekBackMark(),
            ),
            const SizedBox(width: _inGroup),
            SaluIconButton(
              tooltip: 'Seek forward',
              enabled: engineLive,
              onTap: () {}, // hold-repeat drives the ramp
              onHoldRepeat: TransportActions.instance.seekForward,
              child: const SeekForwardMark(),
            ),

            const SizedBox(width: _beforeSound),

            // ── Group 4 · sound: mute + volume bar ─────────────────────
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                player.isMuted,
                player.volumeLevel,
              ]),
              builder: (BuildContext context, Widget? _) {
                return SaluIconButton(
                  tooltip: player.isMuted.value ? 'Unmute' : 'Mute',
                  onTap: TransportActions.instance.toggleMute,
                  child: SpeakerMark(
                    level: player.volumeLevel.value,
                    muted: player.isMuted.value,
                  ),
                );
              },
            ),
            const SizedBox(width: _inGroup),
            const VolumeBar(width: 140),
          ],
        );
      },
    );
  }
}

/// `>` ↔ `II` with the shared swap motion (fade + 0.96 → 1.0, 130 ms —
/// no morphing gimmick). Dims while idle and while stopped.
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state});

  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final bool playing = state == TransportState.playing;
    return SaluIconButton(
      tooltip: playing ? 'Pause' : 'Play',
      enabled: state != TransportState.idle,
      onTap: TransportActions.instance.playOrPause,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 130),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: playing
            ? const PauseMark(key: ValueKey<String>('pause'))
            : const PlayChevronMark(key: ValueKey<String>('play')),
      ),
    );
  }
}
