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

  /// Toggle (the control-row mark; Ctrl+L).
  void togglePlaylist() => playlistOpen.value = !playlistOpen.value;

  /// Close (Esc, the header's Close ✕).
  void closePlaylist() => playlistOpen.value = false;
}
