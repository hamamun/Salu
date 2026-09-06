import 'package:flutter/foundation.dart';

import 'playlist_window.dart';

/// App-level state for SALU's slide-out panels (playlist_imp.md §3.2).
///
/// One notifier the control, the keyboard and the panel all read, exactly
/// as `QueueService` does for the queue. The filter text lives here too
/// (not in a widget) so the loose window can mirror it and docking back
/// restores exactly what was on screen (§4.8).
class PanelService {
  PanelService._();

  static final PanelService instance = PanelService._();

  /// The desktop_multi_window `arguments` marker identifying the playlist
  /// child window's engine (any other arguments = the main window).
  static const String kPlaylistWindowArguments = 'salu-playlist-window';

  /// The docked playlist panel is showing.
  final ValueNotifier<bool> playlistOpen = ValueNotifier<bool>(false);

  /// The panel's filter text (mirrored to the loose window while undocked).
  final ValueNotifier<String> filterText = ValueNotifier<String>('');

  /// The playlist left the player and floats as its own window (§4.8):
  /// the docked slot stays empty and exactly one playlist view exists.
  final ValueNotifier<bool> playlistUndocked = ValueNotifier<bool>(false);

  void togglePlaylist() {
    if (playlistUndocked.value) {
      // While loose, the mark and Ctrl+L SUMMON AND RAISE the window —
      // they never open a second, empty docked panel. One queue, one truth.
      PlaylistWindow.instance.summon();
      return;
    }
    playlistOpen.value = !playlistOpen.value;
  }

  void closePlaylist() => playlistOpen.value = false;
}
