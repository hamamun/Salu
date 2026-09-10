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

  // ── Subtitles (cc.md §2 · D2 · D3 · D5 · D13) ────────────────────────
  static const String _keySubtitleApiKey = 'subtitle_api_key';
  static const String _keySubtitleUsername = 'subtitle_username';
  static const String _keySubtitleLanguage = 'subtitle_language';
  static const String _keySubtitleAutoDownload = 'subtitle_autodownload';

  /// Default preferred-subtitle language (D5 — ISO 639-1 `en`).
  static const String defaultSubtitleLanguage = 'en';

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

  /// The OpenSubtitles.com API key (D2). Empty = signed-out state: the
  /// engine no-ops and surfaces its single once-per-session
  /// `cc not configured` card (D11). Persisted the moment the field
  /// changes (§2.1).
  final ValueNotifier<String> subtitleApiKey = ValueNotifier<String>('');

  /// The OpenSubtitles account username (D13). Plain, low-risk, persisted
  /// so a session's first download can login silently. The PASSWORD and
  /// the Bearer token never live here and never touch disk — they are
  /// `SubtitleService`'s in-memory session state (D13).
  final ValueNotifier<String> subtitleUsername = ValueNotifier<String>('');

  /// Preferred subtitle language (D5) — ISO 639-1 code, default `en`.
  /// Auto: preferred → English → nothing (§2.2); manual search groups
  /// "best 3 in this language" (§6.5). Governs DOWNLOADS only — never an
  /// mpv override (D17).
  final ValueNotifier<String> subtitleLanguage =
      ValueNotifier<String>(defaultSubtitleLanguage);

  /// Auto-download toggle (D3 — default ON). OFF stops future fetches
  /// only; already-downloaded `.srt` files are never touched (D12).
  final ValueNotifier<bool> subtitleAutoDownload =
      ValueNotifier<bool>(true);

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
      final String? rawSubtitleKey = prefs.getString(_keySubtitleApiKey);
      if (rawSubtitleKey != null) subtitleApiKey.value = rawSubtitleKey;
      final String? rawSubtitleUser =
          prefs.getString(_keySubtitleUsername);
      if (rawSubtitleUser != null) subtitleUsername.value = rawSubtitleUser;
      final String? rawSubtitleLang = prefs.getString(_keySubtitleLanguage);
      if (rawSubtitleLang != null && rawSubtitleLang.isNotEmpty) {
        subtitleLanguage.value = rawSubtitleLang;
      }
      subtitleAutoDownload.value =
          prefs.getBool(_keySubtitleAutoDownload) ?? true;
    } catch (_) {
      // Corrupt/missing prefs — fall back to the defaults, silently.
      titleBarMode.value = TitleBarMode.borderless;
      resumeMode.value = ResumeMode.all;
      folderAutoloadMode.value = FolderAutoloadMode.allVideos;
      subtitleApiKey.value = '';
      subtitleUsername.value = '';
      subtitleLanguage.value = defaultSubtitleLanguage;
      subtitleAutoDownload.value = true;
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

  /// Subtitles — the API key field (§2.1): applies and persists the
  /// moment it changes (no Save button anywhere in SALU). A change to a
  /// credential releases the subtitle engine's 401 pause (§3.5 — "engine
  /// pauses until settings change"), which `SubtitleService` answers by
  /// listening to these notifiers.
  Future<void> setSubtitleApiKey(String key) async {
    subtitleApiKey.value = key.trim();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySubtitleApiKey, subtitleApiKey.value);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }

  /// Subtitles — the username field (§2.1 / D13).
  Future<void> setSubtitleUsername(String username) async {
    subtitleUsername.value = username.trim();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySubtitleUsername, subtitleUsername.value);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }

  /// Subtitles — the preferred-language selector (§2.2 / D5). Governs
  /// what SALU downloads; mpv's own track picking stays untouched (D17).
  Future<void> setSubtitleLanguage(String code) async {
    if (code.isEmpty) return;
    subtitleLanguage.value = code;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySubtitleLanguage, code);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }

  /// Subtitles — the auto-download toggle (§2.3 / D3). OFF stops future
  /// fetches only: every already-downloaded `.srt` stays exactly where it
  /// is (D12).
  Future<void> setSubtitleAutoDownload(bool on) async {
    subtitleAutoDownload.value = on;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keySubtitleAutoDownload, on);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }
}
