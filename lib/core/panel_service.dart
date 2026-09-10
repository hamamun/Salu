import 'package:flutter/foundation.dart';

/// App-level state of SALU's slide-out panels (playlist_imp.md §3.2).
///
/// Owned at the app level — not by a widget — so the control-row mark, the
/// keyboard handler and the panel itself all read ONE notifier, exactly as
/// `QueueService` does for the queue.
class PanelService {
  PanelService._internal();

  /// The one and only panel-state holder for the whole app.
  static final PanelService instance = PanelService._internal();

  /// Whether the playlist panel is currently open.
  final ValueNotifier<bool> playlistOpen = ValueNotifier<bool>(false);

  /// Whether the Fetch button's track panel is currently open (cc.md
  /// §6 / D14). Owned here, same recipe: the control mark, the Esc
  /// tier and the panel itself all read ONE notifier.
  final ValueNotifier<bool> trackPanelOpen = ValueNotifier<bool>(false);

  /// Toggle (the control-row mark; Ctrl+L). Opening the playlist closes
  /// other popups (follow.md rule 3's one-popup world).
  void togglePlaylist() {
    final bool next = !playlistOpen.value;
    if (next) closeTrackPanel();
    playlistOpen.value = next;
  }

  /// Close (Esc, the header's Close ✕).
  void closePlaylist() => playlistOpen.value = false;

  /// Toggle the Fetch track panel — opening it closes other popups
  /// (follow.md rule 3's one-popup world).
  void toggleTrackPanel() {
    final bool next = !trackPanelOpen.value;
    if (next) closePlaylist();
    trackPanelOpen.value = next;
  }

  /// Close (Esc, click-outside, media change — §6.2).
  void closeTrackPanel() => trackPanelOpen.value = false;
}
