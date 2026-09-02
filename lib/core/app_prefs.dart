import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where the OSC (On-Screen Controller) lives on the window.
///
/// Phase 3 ships all three layouts; the user switches between them from the
/// Phase 4 Settings → User Interface. `top` is the default per the Phase 3
/// spec ("Top-Anchored (Default): attached directly beneath the title bar").
enum OscLayout {
  top('Top-Anchored', 'Merged into one block just beneath the title bar'),
  floating('Floating Bottom', 'Floats slightly above the bottom edge'),
  fixed('Fixed Bottom', 'Attached flush to the bottom edge');

  const OscLayout(this.label, this.description);

  final String label;
  final String description;
}

/// In-memory user preferences.
///
/// Phase 4 only drafts the Settings UI — persistence (shared_preferences)
/// is wired up in Phase 5/6. Until then everything lives in memory for the
/// session, which is enough for the UI to be fully interactive.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();

  static final AppPrefs instance = AppPrefs._();

  // ── User Interface ─────────────────────────────────────────────────────

  OscLayout _oscLayout = OscLayout.top;
  OscLayout get oscLayout => _oscLayout;
  set oscLayout(OscLayout value) {
    if (_oscLayout == value) return;
    _oscLayout = value;
    notifyListeners();
  }

  Color _accentColor = const Color(0xFF4C9EEB);
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    notifyListeners();
  }

  // ── Playback ───────────────────────────────────────────────────────────

  /// Resume playback from the last position (logic lands in Phase 5).
  bool _resumeLastPosition = true;
  bool get resumeLastPosition => _resumeLastPosition;
  set resumeLastPosition(bool value) {
    if (_resumeLastPosition == value) return;
    _resumeLastPosition = value;
    notifyListeners();
  }

  /// True → Left/Right use exact (millisecond) seeking by default.
  /// False → keyframe seeking (the IINA default).
  bool _exactSeekByDefault = false;
  bool get exactSeekByDefault => _exactSeekByDefault;
  set exactSeekByDefault(bool value) {
    if (_exactSeekByDefault == value) return;
    _exactSeekByDefault = value;
    notifyListeners();
  }

  /// Hardware decoding preference: 'auto' (GPU) or 'disabled' (CPU).
  /// Applied to the engine in Phase 5; the picker lives here now.
  String _hwdec = 'auto';
  String get hwdec => _hwdec;
  set hwdec(String value) {
    if (_hwdec == value) return;
    _hwdec = value;
    notifyListeners();
  }

  // ── Subtitles ──────────────────────────────────────────────────────────

  /// OpenSubtitles API key pasted by the user (used in Phase 7).
  String _openSubtitlesApiKey = '';
  String get openSubtitlesApiKey => _openSubtitlesApiKey;
  set openSubtitlesApiKey(String value) {
    if (_openSubtitlesApiKey == value) return;
    _openSubtitlesApiKey = value;
    notifyListeners();
  }

  /// Whether to auto-download subtitles on video load (Phase 7 logic).
  bool _autoDownloadSubtitles = false;
  bool get autoDownloadSubtitles => _autoDownloadSubtitles;
  set autoDownloadSubtitles(bool value) {
    if (_autoDownloadSubtitles == value) return;
    _autoDownloadSubtitles = value;
    notifyListeners();
  }

  // ── Remote ─────────────────────────────────────────────────────────────

  /// Whether the Android remote WebSocket server is enabled (Phase 8).
  bool _remoteControlEnabled = false;
  bool get remoteControlEnabled => _remoteControlEnabled;
  set remoteControlEnabled(bool value) {
    if (_remoteControlEnabled == value) return;
    _remoteControlEnabled = value;
    notifyListeners();
  }
}
