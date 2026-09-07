import 'package:flutter/material.dart';

import '../../core/panel_service.dart';
import '../../core/queue_service.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// SALU's Playlist control — the Now Row mark, sitting immediately right
/// of the Open `+` in the control row (playlist_imp.md §1, decision 1).
///
/// A *view* toggle, never an open verb: it opens and closes the slide-out
/// playlist panel and reports the queue's position in thirds through the
/// chevron's row. Open = the `active:` glow only (follow.md §2 — no
/// second glyph change). Always enabled (§3.1): with an empty queue the
/// three quiet rules already tell the truth, and the empty panel still
/// accepts drops, so a dimmed control would only hide the feature.
class PlaylistControl extends StatelessWidget {
  const PlaylistControl({super.key});

  @override
  Widget build(BuildContext context) {
    final QueueService queue = QueueService.instance;
    final PanelService panel = PanelService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        queue.paths,
        queue.index,
        panel.playlistOpen,
      ]),
      builder: (BuildContext context, Widget? _) {
        final bool open = panel.playlistOpen.value;
        return SaluIconButton(
          // Names the control, never teaches (rule 1); follows state like
          // the sound mark's 'Unmute' / 'Mute'.
          tooltip: open ? 'Hide playlist' : 'Playlist',
          size: 36,
          active: open,
          enabled: true, // always — see §3.1
          onTap: panel.togglePlaylist,
          child: NowRowMark(
            size: 20,
            now: playlistRowOf(queue.index.value, queue.paths.value.length),
          ),
        );
      },
    );
  }
}
