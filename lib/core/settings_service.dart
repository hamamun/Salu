import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How SALU's custom title bar behaves while the window is idle.
enum TitleBarMode {
  /// Always auto-hides 3s after inactivity — even when nothing is playing.
  borderless,

  /// Stays pinned while playback is off (nothing loaded, or paused);
  /// auto-hides while a video is actively playing.
  pinWhenPlaybackOff,

  /// Never auto-hides — the bar is always visible.
  locked,
}

/// SALU's persisted settings, backed by `shared_preferences`.
///
/// UI-facing state lives in [ValueNotifier]s so widgets can react instantly;
/// every mutation is mirrored to disk so it survives restarts.
class SettingsService {
  SettingsService._internal();

  /// The single settings holder for the whole app.
  static final SettingsService instance = SettingsService._internal();

  static const String _keyTitleBarMode = 'title_bar_mode';

  /// How the title bar handles itself while idle (see [TitleBarMode]).
  final ValueNotifier<TitleBarMode> titleBarMode =
      ValueNotifier<TitleBarMode>(TitleBarMode.borderless);

  /// Reads persisted settings (called once, before the first frame).
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_keyTitleBarMode);
      if (raw != null) {
        // `asNameMap()` lives on the `EnumByName` extension over
        // `Iterable<T extends Enum>`, so it has to be reached through
        // `values` — the enum type itself has no such static member.
        titleBarMode.value =
            TitleBarMode.values.asNameMap()[raw] ?? TitleBarMode.borderless;
      }
    } catch (_) {
      // Corrupt/missing prefs — fall back to the default, silently.
      titleBarMode.value = TitleBarMode.borderless;
    }
  }

  /// Applies a new title bar mode instantly and persists it.
  Future<void> setTitleBarMode(TitleBarMode mode) async {
    titleBarMode.value = mode;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTitleBarMode, mode.name);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }
}
