import 'package:flutter/material.dart';

import '../../core/lyric_service.dart';
import '../../core/media_utils.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// The Fetch button (cc.md §6 / D14 · lrc.md L13 / L14) — the control
/// row's right zone, immediately left of fullscreen.
///
/// Job by media kind:
///   · **Video** → opens the track panel (`Tracks` tooltip). Unchanged.
///   · **Audio with lyrics available** → lyrics on/off toggle (`Lyrics`
///     tooltip). A dot badge means "available and currently off" (L14).
///   · **Audio with no lyrics** (and channels / remote URLs) → greyed
///     out and inert, never hidden.
class FetchControl extends StatelessWidget {
  const FetchControl({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    final PanelService panels = PanelService.instance;
    final LyricService lyrics = LyricService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        player.currentPath,
        lyrics.available,
        lyrics.shown,
        panels.trackPanelOpen,
      ]),
      builder: (BuildContext context, Widget? _) {
        final String? path = player.currentPath.value;
        final bool local = path != null &&
            !path.contains('://') &&
            !QueueService.instance.isChannelList;
        final bool video =
            local && path != null && MediaUtils.isVideo(path);
        final bool audioLyrics = local &&
            path != null &&
            MediaUtils.isAudio(path) &&
            lyrics.available.value;
        final bool audio = local && path != null && MediaUtils.isAudio(path);
        final bool enabled = video || audioLyrics;
        final bool lyricsOn = audioLyrics && lyrics.shown.value;
        return SaluIconButton(
          tooltip: audio ? 'Lyrics' : 'Tracks',
          enabled: enabled,
          active: video ? panels.trackPanelOpen.value : lyricsOn,
          badge: audioLyrics && !lyrics.shown.value,
          onTap: video ? panels.toggleTrackPanel : lyrics.toggleShown,
          child: const CcMark(size: 19),
        );
      },
    );
  }
}
