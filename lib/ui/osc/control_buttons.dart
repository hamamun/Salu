import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../managers/ui_visibility_manager.dart';
import '../widgets/osd_indicator.dart';

/// A single monochromatic OSC icon button with a subtle hover highlight.
class OscIconButton extends StatefulWidget {
  const OscIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 21,
    this.highlightColor,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? highlightColor;

  @override
  State<OscIconButton> createState() => _OscIconButtonState();
}

class _OscIconButtonState extends State<OscIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final Color color = widget.active
        ? AppColors.accent
        : (enabled ? AppColors.textPrimary : AppColors.textSecondary.withAlpha(102));
    final Widget button = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.captionButtonHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: widget.size, color: color),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// The main transport + right-side button cluster of the OSC
/// (Phase 3 · Step 4).
class ControlButtons extends StatelessWidget {
  const ControlButtons({
    super.key,
    required this.onPlayPauseFlash,
    required this.onTogglePanel,
    required this.onToggleHud,
    required this.onToggleLibrary,
  });

  /// Performs play/pause and triggers the center-screen flash.
  final VoidCallback onPlayPauseFlash;

  final VoidCallback onTogglePanel;
  final VoidCallback onToggleHud;
  final VoidCallback onToggleLibrary;

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    return Row(
      children: <Widget>[
        // Phase 6 · Step 3: on a live stream the skip buttons disappear and
        // Previous/Next become Channel Down / Channel Up.
        ValueListenableBuilder<bool>(
          valueListenable: player.isLiveStream,
          builder: (BuildContext context, bool live, Widget? _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OscIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: live ? 'Channel down' : 'Previous',
                  onPressed: () => player.previous(),
                ),
                if (!live)
                  OscIconButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Backward 10 s',
                    onPressed: () => _skip(player, -10),
                  ),
                const SizedBox(width: 2),
                _PlayPauseButton(onPressed: onPlayPauseFlash),
                const SizedBox(width: 2),
                if (!live)
                  OscIconButton(
                    icon: Icons.forward_10_rounded,
                    tooltip: 'Forward 10 s',
                    onPressed: () => _skip(player, 10),
                  ),
                OscIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: live ? 'Channel up' : 'Next',
                  onPressed: () => player.next(),
                ),
              ],
            );
          },
        ),
        const SizedBox(width: 14),
        Container(width: 1, height: 22, color: AppColors.divider),
        const SizedBox(width: 14),
        const _VolumeControl(),
        const SizedBox(width: 6),
        const _AudioTrackButton(),
        const _SubtitleTrackButton(),
        const Spacer(),
        // PiP & Fullscreen are disabled in Music Mode (Phase 3 · Step 7).
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[player.pip, player.isMusicMode]),
          builder: (BuildContext context, Widget? _) {
            final bool music = player.isMusicMode.value;
            final bool pip = player.pip.value;
            return OscIconButton(
              icon: pip
                  ? Icons.picture_in_picture_alt_rounded
                  : Icons.picture_in_picture_alt_outlined,
              tooltip: music ? 'Unavailable in Music Mode' : 'Picture-in-Picture',
              active: pip,
              onPressed: music ? null : () => player.togglePip(),
            );
          },
        ),
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[player.fullscreen, player.isMusicMode]),
          builder: (BuildContext context, Widget? _) {
            final bool music = player.isMusicMode.value;
            final bool fs = player.fullscreen.value;
            return OscIconButton(
              icon: fs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              tooltip: music
                  ? 'Unavailable in Music Mode'
                  : (fs ? 'Exit fullscreen' : 'Fullscreen'),
              onPressed: music ? null : () => player.toggleFullscreen(),
            );
          },
        ),
        OscIconButton(
          icon: Icons.info_outline_rounded,
          tooltip: 'Media Inspector',
          onPressed: onToggleHud,
        ),
        OscIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Quick Settings',
          onPressed: onTogglePanel,
        ),
        OscIconButton(
          icon: Icons.video_library_outlined,
          tooltip: 'Library / Streams',
          onPressed: onToggleLibrary,
        ),
      ],
    );
  }

  void _skip(PlayerService player, int seconds) {
    player.seekBy(Duration(seconds: seconds));
    OsdController.instance.show(
      '${seconds > 0 ? '+' : ''}$seconds s',
      icon: seconds > 0 ? Icons.forward_10_rounded : Icons.replay_10_rounded,
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlayerService.instance.playing,
      builder: (BuildContext context, bool playing, Widget? _) {
        return Tooltip(
          message: playing ? 'Pause' : 'Play',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mute toggle + a volume slider that expands on hover.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl();

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: player.muted,
            builder: (BuildContext context, bool muted, Widget? _) {
              return OscIconButton(
                icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                tooltip: muted ? 'Unmute' : 'Mute',
                active: muted,
                onPressed: () {
                  player.setMuted(!muted);
                  OsdController.instance.show(
                    muted ? 'Unmuted' : 'Muted',
                    icon: muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  );
                },
              );
            },
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: _hovered ? 96 : 0,
            child: _hovered
                ? ValueListenableBuilder<double>(
                    valueListenable: player.baseVolume,
                    builder: (BuildContext context, double volume, Widget? _) {
                      return SizedBox(
                        height: 34,
                        child: Slider(
                          value: volume.clamp(0.0, 100.0).toDouble(),
                          min: 0,
                          max: 100,
                          onChangeStart: (_) {
                            UiVisibilityManager.instance.lockInteraction();
                          },
                          onChanged: (double v) => player.setBaseVolume(v),
                          onChangeEnd: (double v) {
                            UiVisibilityManager.instance.unlockInteraction();
                            OsdController.instance.show(
                              'Volume ${v.round()}%',
                              icon: Icons.volume_up_rounded,
                            );
                          },
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// A non-tappable hover button used as the [PopupMenuButton] child, so the
/// menu's own InkWell handles the tap (the inner button must not steal it).
class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.captionButtonHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            size: 21,
            color: widget.enabled
                ? AppColors.textPrimary
                : AppColors.textSecondary.withAlpha(102),
          ),
        ),
      ),
    );
  }
}

/// Fast pop-up for switching embedded audio tracks.
class _AudioTrackButton extends StatelessWidget {
  const _AudioTrackButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Tracks?>(
      valueListenable: PlayerService.instance.tracks,
      builder: (BuildContext context, Tracks? tracks, Widget? _) {
        final List<AudioTrack> audio = tracks?.audio ?? const <AudioTrack>[];
        return PopupMenuButton<AudioTrack>(
          enabled: audio.isNotEmpty,
          tooltip: 'Audio track',
          position: PopupMenuPosition.over,
          onSelected: (AudioTrack track) => PlayerService.instance.setAudioTrack(track),
          itemBuilder: (BuildContext context) {
            final String? currentId =
                PlayerService.instance.currentTrack.value?.audio.id;
            return <PopupMenuEntry<AudioTrack>>[
              for (int i = 0; i < audio.length; i++)
                PopupMenuItem<AudioTrack>(
                  value: audio[i],
                  child: _TrackTile(
                    title: audio[i].title ?? audio[i].language ?? 'Track ${i + 1}',
                    subtitle: audio[i].language,
                    selected: audio[i].id == currentId,
                  ),
                ),
            ];
          },
          child: _MenuButton(
            icon: Icons.audiotrack_outlined,
            tooltip: 'Audio track',
            enabled: audio.isNotEmpty,
          ),
        );
      },
    );
  }
}

/// Fast pop-up for switching embedded subtitle tracks, with "Disable" on top.
class _SubtitleTrackButton extends StatelessWidget {
  const _SubtitleTrackButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Tracks?>(
      valueListenable: PlayerService.instance.tracks,
      builder: (BuildContext context, Tracks? tracks, Widget? _) {
        final List<SubtitleTrack> subs = tracks?.subtitle ?? const <SubtitleTrack>[];
        return PopupMenuButton<SubtitleTrack>(
          enabled: subs.isNotEmpty,
          tooltip: 'Subtitles',
          position: PopupMenuPosition.over,
          onSelected: (SubtitleTrack track) => PlayerService.instance.setSubtitleTrack(track),
          itemBuilder: (BuildContext context) {
            final String? currentId =
                PlayerService.instance.currentTrack.value?.subtitle.id;
            return <PopupMenuEntry<SubtitleTrack>>[
              PopupMenuItem<SubtitleTrack>(
                value: SubtitleTrack.no(),
                child: const _TrackTile(title: 'Disable / Off', selected: false),
              ),
              const PopupMenuDivider(),
              for (int i = 0; i < subs.length; i++)
                PopupMenuItem<SubtitleTrack>(
                  value: subs[i],
                  child: _TrackTile(
                    title: subs[i].title ?? subs[i].language ?? 'Track ${i + 1}',
                    subtitle: subs[i].language,
                    selected: subs[i].id == currentId,
                  ),
                ),
            ];
          },
          child: _MenuButton(
            icon: Icons.subtitles_outlined,
            tooltip: 'Subtitles',
            enabled: subs.isNotEmpty,
          ),
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.title, this.subtitle, this.selected = false});

  final String title;
  final String? subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 22,
          child: selected
              ? const Icon(Icons.check_rounded,
                  size: 16, color: AppColors.accent)
              : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            subtitle == null || subtitle!.isEmpty ? title : '$title · $subtitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: selected ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
