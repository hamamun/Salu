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

  /// Whether the Equalizer button's Tune panel is open (eq_imp.md §1.2) —
  /// the same recipe a third time: one notifier for the mark, the Esc tier
  /// and the panel.
  final ValueNotifier<bool> tunePanelOpen = ValueNotifier<bool>(false);

  /// Toggle (the control-row mark; Ctrl+L). Opening the playlist closes
  /// other popups (follow.md rule 3's one-popup world).
  void togglePlaylist() {
    final bool next = !playlistOpen.value;
    if (next) {
      closeTrackPanel();
      closeTunePanel();
    }
    playlistOpen.value = next;
  }

  /// Close (Esc, the header's Close ✕).
  void closePlaylist() => playlistOpen.value = false;

  /// Toggle the Fetch track panel — opening it closes other popups
  /// (follow.md rule 3's one-popup world).
  void toggleTrackPanel() {
    final bool next = !trackPanelOpen.value;
    if (next) {
      closePlaylist();
      closeTunePanel();
    }
    trackPanelOpen.value = next;
  }

  /// Close (Esc, click-outside, media change — §6.2).
  void closeTrackPanel() => trackPanelOpen.value = false;

  /// Toggle the Tune panel (the Equalizer mark; Ctrl+E). Opening it closes
  /// the other popups — eq_imp.md §1.2's "same recipe as the Tracks panel".
  void toggleTunePanel() {
    final bool next = !tunePanelOpen.value;
    if (next) {
      closePlaylist();
      closeTrackPanel();
    }
    tunePanelOpen.value = next;
  }

  /// Close (Esc, click-outside).
  void closeTunePanel() => tunePanelOpen.value = false;

  /// Whether any panel is up — the chrome's "do not hide under me" check.
  bool get anyOpen =>
      playlistOpen.value || trackPanelOpen.value || tunePanelOpen.value;
}
