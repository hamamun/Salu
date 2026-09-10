import 'package:flutter/material.dart';

import '../../core/media_utils.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// The Fetch button (cc.md §6 / D14) — the control row's right zone,
/// immediately left of fullscreen.
///
/// Live ONLY while a local video file is playing (D6): audio files,
/// channel mode, and remote URL streams all leave it **greyed out and
/// inert — never hidden** (SaluIconButton's `enabled: false` already
/// dims the mark and keeps the tooltip name, exactly what D6 asks for
/// and what follow.md prescribes). A tap toggles the slide-down track
/// panel via [PanelService].
class FetchControl extends StatelessWidget {
  const FetchControl({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    final PanelService panels = PanelService.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: player.currentPath,
      builder: (BuildContext context, String? path, Widget? _) {
        final bool enabled = path != null &&
            !path.contains('://') &&
            !QueueService.instance.isChannelList &&
            MediaUtils.isVideo(path);
        return ValueListenableBuilder<bool>(
          valueListenable: panels.trackPanelOpen,
          builder: (BuildContext context, bool open, Widget? _) {
            return SaluIconButton(
              tooltip: 'Tracks',
              enabled: enabled,
              active: open,
              onTap: panels.toggleTrackPanel,
              child: const CcMark(size: 19),
            );
          },
        );
      },
    );
  }
}
