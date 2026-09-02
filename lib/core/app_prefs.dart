import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// User preferences, persisted with `shared_preferences` (Phase 5).
///
/// Every setter writes through to disk asynchronously, so a value the user
/// flips in the Settings window survives an app restart. [load] must be
/// awaited once during startup, before the UI reads anything.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();

  static final AppPrefs instance = AppPrefs._();

  SharedPreferences? _store;
  bool _loaded = false;

  /// True once [load] has completed.
  bool get loaded => _loaded;

  // Storage keys.
  static const String _kOscLayout = 'ui.oscLayout';
  static const String _kAccent = 'ui.accentColor';
  static const String _kResume = 'playback.resumeLastPosition';
  static const String _kExactSeek = 'playback.exactSeekByDefault';
  static const String _kHwdec = 'playback.hwdec';
  static const String _kAutoQueue = 'playback.autoQueueFolder';
  static const String _kApiKey = 'subtitles.openSubtitlesApiKey';
  static const String _kAutoSubs = 'subtitles.autoDownload';
  static const String _kRemote = 'remote.enabled';

  /// Reads every stored value into memory. Safe to call more than once.
  Future<void> load() async {
    try {
      final SharedPreferences store = await SharedPreferences.getInstance();
      _store = store;

      final String? layout = store.getString(_kOscLayout);
      if (layout != null) {
        _oscLayout = OscLayout.values.firstWhere(
          (OscLayout l) => l.name == layout,
          orElse: () => OscLayout.top,
        );
      }
      final int? accent = store.getInt(_kAccent);
      if (accent != null) _accentColor = Color(accent);

      _resumeLastPosition = store.getBool(_kResume) ?? _resumeLastPosition;
      _exactSeekByDefault = store.getBool(_kExactSeek) ?? _exactSeekByDefault;
      _hwdec = store.getString(_kHwdec) ?? _hwdec;
      _autoQueueFolder = store.getBool(_kAutoQueue) ?? _autoQueueFolder;
      _openSubtitlesApiKey = store.getString(_kApiKey) ?? _openSubtitlesApiKey;
      _autoDownloadSubtitles = store.getBool(_kAutoSubs) ?? _autoDownloadSubtitles;
      _remoteControlEnabled = store.getBool(_kRemote) ?? _remoteControlEnabled;
    } catch (error) {
      debugPrint('[SALU] preferences load failed: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  void _writeString(String key, String value) {
    _store?.setString(key, value);
  }

  void _writeBool(String key, bool value) {
    _store?.setBool(key, value);
  }

  void _writeInt(String key, int value) {
    _store?.setInt(key, value);
  }

  // ── User Interface ─────────────────────────────────────────────────────

  OscLayout _oscLayout = OscLayout.top;
  OscLayout get oscLayout => _oscLayout;
  set oscLayout(OscLayout value) {
    if (_oscLayout == value) return;
    _oscLayout = value;
    _writeString(_kOscLayout, value.name);
    notifyListeners();
  }

  Color _accentColor = const Color(0xFF4C9EEB);
  Color get accentColor => _accentColor;
  set accentColor(Color value) {
    if (_accentColor == value) return;
    _accentColor = value;
    _writeInt(_kAccent, value.value);
    notifyListeners();
  }

  // ── Playback ───────────────────────────────────────────────────────────

  /// Resume playback from the last saved position (Phase 5 · Step 3).
  bool _resumeLastPosition = true;
  bool get resumeLastPosition => _resumeLastPosition;
  set resumeLastPosition(bool value) {
    if (_resumeLastPosition == value) return;
    _resumeLastPosition = value;
    _writeBool(_kResume, value);
    notifyListeners();
  }

  /// True → Left/Right use exact (millisecond) seeking by default.
  /// False → keyframe seeking (the IINA default); Shift flips the behaviour.
  bool _exactSeekByDefault = false;
  bool get exactSeekByDefault => _exactSeekByDefault;
  set exactSeekByDefault(bool value) {
    if (_exactSeekByDefault == value) return;
    _exactSeekByDefault = value;
    _writeBool(_kExactSeek, value);
    notifyListeners();
  }

  /// Hardware decoding preference: 'auto' (GPU) or 'disabled' (CPU).
  String _hwdec = 'auto';
  String get hwdec => _hwdec;
  set hwdec(String value) {
    if (_hwdec == value) return;
    _hwdec = value;
    _writeString(_kHwdec, value);
    notifyListeners();
  }

  /// Silently queue the rest of the folder when a single file is opened.
  bool _autoQueueFolder = true;
  bool get autoQueueFolder => _autoQueueFolder;
  set autoQueueFolder(bool value) {
    if (_autoQueueFolder == value) return;
    _autoQueueFolder = value;
    _writeBool(_kAutoQueue, value);
    notifyListeners();
  }

  // ── Subtitles ──────────────────────────────────────────────────────────

  /// OpenSubtitles API key pasted by the user (used in Phase 7).
  String _openSubtitlesApiKey = '';
  String get openSubtitlesApiKey => _openSubtitlesApiKey;
  set openSubtitlesApiKey(String value) {
    if (_openSubtitlesApiKey == value) return;
    _openSubtitlesApiKey = value;
    _writeString(_kApiKey, value);
    notifyListeners();
  }

  /// Whether to auto-download subtitles on video load (Phase 7 logic).
  bool _autoDownloadSubtitles = false;
  bool get autoDownloadSubtitles => _autoDownloadSubtitles;
  set autoDownloadSubtitles(bool value) {
    if (_autoDownloadSubtitles == value) return;
    _autoDownloadSubtitles = value;
    _writeBool(_kAutoSubs, value);
    notifyListeners();
  }

  // ── Remote ─────────────────────────────────────────────────────────────

  /// Whether the Android remote WebSocket server is enabled (Phase 8).
  bool _remoteControlEnabled = false;
  bool get remoteControlEnabled => _remoteControlEnabled;
  set remoteControlEnabled(bool value) {
    if (_remoteControlEnabled == value) return;
    _remoteControlEnabled = value;
    _writeBool(_kRemote, value);
    notifyListeners();
  }
}
