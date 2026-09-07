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

/// Which files continue from where you stopped (Settings → General →
/// Resume). Gates both saving and resuming, per file kind.
enum ResumeMode {
  /// Video and audio pick up where they stopped.
  all,

  /// Video resumes; audio starts from the beginning.
  videoOnly,

  /// Audio resumes; video starts from the beginning.
  audioOnly,

  /// Everything starts from the beginning.
  off,
}

/// What happens when exactly one local media file is loaded (Settings →
/// General → Folder auto-load; autoload_imp.md §1 lock 1).
enum FolderAutoloadMode {
  /// Everything of the file's kind in its folder is queued around the
  /// picked file (the factory default — owner's pick).
  allVideos,

  /// Only files whose name shape matches the picked one (the rest of
  /// the series), never the whole folder.
  sameSeries,

  /// Only the picked file loads — Phase A behavior, untouched.
  off,
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
  static const String _keyResumeMode = 'resume_mode';
  static const String _keyFolderAutoloadMode = 'folder_autoload_mode';

  /// How the title bar handles itself while idle (see [TitleBarMode]).
  final ValueNotifier<TitleBarMode> titleBarMode =
      ValueNotifier<TitleBarMode>(TitleBarMode.borderless);

  /// Which files continue from where you stopped (see [ResumeMode]).
  final ValueNotifier<ResumeMode> resumeMode =
      ValueNotifier<ResumeMode>(ResumeMode.all);

  /// What a single-file load turns into (see [FolderAutoloadMode]).
  /// Default ON (`allVideos`) — owner's lock 2; persisted, so a manual
  /// Off is remembered across sessions.
  final ValueNotifier<FolderAutoloadMode> folderAutoloadMode =
      ValueNotifier<FolderAutoloadMode>(FolderAutoloadMode.allVideos);

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
      final String? rawResume = prefs.getString(_keyResumeMode);
      if (rawResume != null) {
        resumeMode.value =
            ResumeMode.values.asNameMap()[rawResume] ?? ResumeMode.all;
      }
      final String? rawAutoload = prefs.getString(_keyFolderAutoloadMode);
      if (rawAutoload != null) {
        folderAutoloadMode.value =
            FolderAutoloadMode.values.asNameMap()[rawAutoload] ??
                FolderAutoloadMode.allVideos;
      }
    } catch (_) {
      // Corrupt/missing prefs — fall back to the defaults, silently.
      titleBarMode.value = TitleBarMode.borderless;
      resumeMode.value = ResumeMode.all;
      folderAutoloadMode.value = FolderAutoloadMode.allVideos;
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

  /// Applies a new resume mode instantly and persists it. Switching to
  /// [ResumeMode.off] stops saving *and* resuming but never wipes stored
  /// positions — switching back restores the memory.
  Future<void> setResumeMode(ResumeMode mode) async {
    resumeMode.value = mode;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyResumeMode, mode.name);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }

  /// Applies a new folder auto-load mode instantly and persists it.
  /// Takes effect from the NEXT single-file load — the live queue is
  /// never retrofitted (autoload_imp.md §2.1).
  Future<void> setFolderAutoloadMode(FolderAutoloadMode mode) async {
    folderAutoloadMode.value = mode;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFolderAutoloadMode, mode.name);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }
}
