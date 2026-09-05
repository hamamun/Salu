import 'package:flutter/material.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/salu_icon_button.dart';
import 'media_timeline.dart';
import 'open_media_control.dart';

/// SALU's on-screen controller container.
///
/// Designed to sit directly beneath the top title bar and read as the
/// same single window: it paints no background, border or shadow of its
/// own — the fused parent block (HomeScreen's top chrome) supplies one
/// continuous scrim behind both, edge to edge.
///
/// Layout, top to bottom (follow.md · §5 — rows never shift):
///   · Row 1 — the unified media timeline (identical for video and audio)
///   · Row 2 — the control row. Its one finalized item is the Open Media
///     control at the very left; the existing play/pause + mute + volume
///     stay centered until each is redesigned in its own step.
///
/// The row below the timeline keeps a fixed height: hover popups from the
/// timeline float OVER it, nothing is ever pushed or shifted.
class ControllerPanel extends StatelessWidget {
  const ControllerPanel({super.key});

  /// Total fixed height of the panel (timeline + controls + padding).
  static const double height = 108;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(18, 4, 18, 12);

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    return Container(
      height: height,
      padding: _padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Row 1 · the timeline (bar + floating hover chip in its box).
          const MediaTimeline(),
          // Row 2 · the control row (fixed height, never pushed).
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Left zone · the Open Media control (plus → pill).
                const Align(
                  alignment: Alignment.centerLeft,
                  child: OpenMediaControl(),
                ),
                // Center zone · transport (interim — each control gets
                // its own design step later).
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _PlayPauseButton(player: player),
                    const SizedBox(width: 26),
                    _MuteButton(player: player),
                    const SizedBox(width: 6),
                    const _VolumeBar(width: 120),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Play / pause toggle (SALU icon recipe — lights up, never boxed).
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player.isPlaying,
      builder: (BuildContext context, Widget? _) {
        return SaluIconButton(
          tooltip: 'Play / Pause',
          onTap: player.playOrPause,
          child: Icon(
            player.isPlaying.value
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 21,
          ),
        );
      },
    );
  }
}

/// Mute toggle — the icon reflects both the mute flag and a zero volume.
class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        player.isMuted,
        player.volumeLevel,
      ]),
      builder: (BuildContext context, Widget? _) {
        final bool silent = player.isMuted.value || player.volumeLevel.value < 1;
        return SaluIconButton(
          tooltip: player.isMuted.value ? 'Unmute' : 'Mute',
          onTap: player.toggleMute,
          child: Icon(
            silent
                ? Icons.volume_off_rounded
                : (player.volumeLevel.value < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded),
            size: 21,
          ),
        );
      },
    );
  }
}

/// A slim paste-style volume bar: click anywhere to jump, drag to slide.
/// Dragging up from silence unmutes automatically.
///
/// Raw-pointer driven (no gesture arena) so the value tracks the cursor
/// 1:1 from the very first pixel — no slop, no jump on grab.
class _VolumeBar extends StatefulWidget {
  const _VolumeBar({required this.width});

  final double width;

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  final PlayerService _player = PlayerService.instance;

  /// True while the button is pressed on the bar (tracks drags even when
  /// the cursor leaves the bar's bounds).
  bool _active = false;

  void _apply(double dx, double w) {
    if (!_active) return;
    final double v = (dx / (w <= 0 ? 1 : w)).clamp(0.0, 1.0).toDouble() * 100;
    _player.setVolumeUI(v);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 34,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent e) {
              _active = true;
              _apply(e.localPosition.dx, w);
            },
            onPointerMove: (PointerMoveEvent e) => _apply(e.localPosition.dx, w),
            onPointerUp: (PointerUpEvent e) {
              _active = false;
              _apply(e.localPosition.dx, w); // Final snap before release.
            },
            onPointerCancel: (PointerCancelEvent e) => _active = false,
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                _player.volumeLevel,
                _player.isMuted,
              ]),
              builder: (BuildContext context, Widget? _) {
                final double frac = (_player.isMuted.value
                        ? 0.0
                        : _player.volumeLevel.value / 100)
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 6,
                      width: w,
                      child: Stack(
                        children: <Widget>[
                          const Positioned.fill(
                            child: ColoredBox(color: AppColors.barTrack),
                          ),
                          if (frac > 0)
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              width: w * frac,
                              child: const ColoredBox(color: AppColors.barFill),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
