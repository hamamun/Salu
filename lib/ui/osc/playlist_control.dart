import 'package:flutter/material.dart';

import '../../core/panel_service.dart';
import '../../core/queue_service.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// SALU's Playlist control — the Now Row mark, sitting immediately right
/// of the Open `+` in the control row's left zone (playlist_imp.md §§1–3).
///
/// It is a TOGGLE, never a launcher: clicking it while the panel is open
/// closes it (and while the panel is loose, it summons and raises the
/// window instead of opening a second docked one). It is always enabled —
/// a view toggle is not a verb — and its open state is only the `active:`
/// glow: the mark itself reports position in thirds, never the panel's
/// state.
class PlaylistControl extends StatelessWidget {
  const PlaylistControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        QueueService.instance.items,
        QueueService.instance.index,
        PanelService.instance.playlistOpen,
        PanelService.instance.playlistUndocked,
      ]),
      builder: (BuildContext context, Widget? _) {
        final QueueService queue = QueueService.instance;
        final bool open = PanelService.instance.playlistOpen.value;
        final bool undocked = PanelService.instance.playlistUndocked.value;
        return SaluIconButton(
          // Names the control, never teaches (rule 1). Follows state
          // exactly like the sound mark's 'Unmute' / 'Mute'.
          tooltip: (open || undocked) ? 'Hide playlist' : 'Playlist',
          size: 36,
          active: open || undocked,
          enabled: true, // ALWAYS — playlist_imp.md §3.1
          onTap: PanelService.instance.togglePlaylist,
          child: NowRowMark(
            size: 20,
            now: playlistRowOf(queue.index.value, queue.items.value.length),
          ),
        );
      },
    );
  }
}
