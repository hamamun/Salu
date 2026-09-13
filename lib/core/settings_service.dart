import 'dart:convert';
import 'dart:math';

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

  // ── Subtitles (cc.md §2 · D2 · D3 · D5 · D13 amended 2026-09-13) ─────
  static const String _keySubtitleApiKey = 'subtitle_api_key';
  static const String _keySubtitleUsername = 'subtitle_username';
  static const String _keySubtitlePassword = 'subtitle_password';
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
  /// so a session's first download can login silently. The Bearer token
  /// never lives here and never touches disk — it stays `SubtitleService`'s
  /// in-memory session state (D13).
  final ValueNotifier<String> subtitleUsername = ValueNotifier<String>('');

  /// The OpenSubtitles account password.
  ///
  /// **D13 AMENDED (owner, 2026-09-13):** this is now persisted, scrambled
  /// by [SubtitleScramble], beside the key and the username. The original
  /// D13 kept it in RAM only — which meant `/download` (key **and** Bearer,
  /// cc.md §4) was dead after every restart until the field was retyped,
  /// and the AUTO engine's one trigger (§3.1) always fired before that
  /// retyping could happen: no card, no subtitle, no clue. The token still
  /// never touches disk; restart = one silent re-login.
  ///
  /// **This is obfuscation, NOT encryption** — reversible by anyone holding
  /// both the prefs file and SALU's source. It keeps the password out of
  /// plain sight in `%APPDATA%`, nothing more.
  final ValueNotifier<String> subtitlePassword = ValueNotifier<String>('');

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
      // D13 amended: the password comes back scrambled — [SubtitleScramble]
      // hands back '' for anything it cannot decode (corrupt/hand-edited
      // prefs), which is exactly the signed-out state SALU already handles.
      final String? rawSubtitlePass =
          prefs.getString(_keySubtitlePassword);
      if (rawSubtitlePass != null && rawSubtitlePass.isNotEmpty) {
        subtitlePassword.value = SubtitleScramble.decode(rawSubtitlePass);
      }
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
      subtitlePassword.value = '';
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

  /// Subtitles — the password field (D13 amended 2026-09-13). Persisted
  /// scrambled the moment it changes, like every other SALU field (no Save
  /// button anywhere). NOT trimmed — a password is literal, and a trailing
  /// space is part of it.
  ///
  /// Empty removes the stored value entirely rather than writing an empty
  /// blob: clearing the field in Settings signs SALU out for good.
  Future<void> setSubtitlePassword(String password) async {
    subtitlePassword.value = password;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (password.isEmpty) {
        await prefs.remove(_keySubtitlePassword);
      } else {
        await prefs.setString(
            _keySubtitlePassword, SubtitleScramble.encode(password));
      }
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

/// The subtitle password's scramble (D13 AMENDED, owner 2026-09-13).
///
/// `shared_preferences` on Windows is a plain XML file under `%APPDATA%`,
/// so the original "never persisted" rule left one bad choice: either the
/// password sits there readable, or `/download` is dead after every restart
/// (it needs a Bearer token only `/login` can mint — cc.md §4). The owner
/// picked the middle: **stored, but not as text**.
///
/// Shape: `base64( nonce(8 random bytes) ‖ xor-keystream(password) )`, the
/// keystream being xorshift32 seeded from the app salt **and the nonce** —
/// so the same password never stores the same blob twice, and two passwords
/// sharing a prefix share nothing in the file (a fixed keystream would leak
/// exactly that).
///
/// **THIS IS OBFUSCATION, NOT ENCRYPTION.** It defeats a glance at the prefs
/// file and nothing stronger: the salt is a constant in this source tree, so
/// anyone holding both the file and SALU's source recovers the password.
/// Stated here and in cc.md so nobody later mistakes it for real protection.
/// A real secret store would be Windows DPAPI behind a plugin — a separate
/// owner call, and against follow.md §7 (`shared_preferences` only) as it
/// stands.
class SubtitleScramble {
  SubtitleScramble._();

  /// The app salt the keystream is seeded from. Changing it invalidates
  /// every stored password (they decode to garbage → caught → `''` →
  /// the signed-out state SALU already handles).
  static const String salt = 'SALU-subtitle-password-v1';

  /// Random bytes stored in front of the blob so no keystream is ever
  /// reused. 8 is well past what a preferences value needs.
  static const int _nonceBytes = 8;

  static const int _mask32 = 0xFFFFFFFF;

  static final Random _random = Random.secure();

  /// Scrambles [plain] into a storable, non-readable blob.
  static String encode(String plain) {
    final List<int> bytes = utf8.encode(plain);
    final List<int> nonce =
        List<int>.generate(_nonceBytes, (int _) => _random.nextInt(256));
    int state = _seed(nonce);
    final List<int> out = List<int>.filled(_nonceBytes + bytes.length, 0);
    for (int i = 0; i < _nonceBytes; i++) {
      out[i] = nonce[i];
    }
    for (int i = 0; i < bytes.length; i++) {
      state = _next(state);
      out[_nonceBytes + i] = bytes[i] ^ (state & 0xFF);
    }
    return base64Encode(out);
  }

  /// Reverses [encode]. Anything undecodable — hand-edited, truncated,
  /// written under a different salt, or a pre-amendment value — returns
  /// `''`, the signed-out state SALU already handles.
  static String decode(String stored) {
    try {
      final List<int> raw = base64Decode(stored);
      if (raw.length < _nonceBytes) return '';
      int state = _seed(raw.sublist(0, _nonceBytes));
      final List<int> out = List<int>.filled(raw.length - _nonceBytes, 0);
      for (int i = 0; i < out.length; i++) {
        state = _next(state);
        out[i] = raw[_nonceBytes + i] ^ (state & 0xFF);
      }
      return utf8.decode(out);
    } catch (_) {
      return '';
    }
  }

  /// FNV-1a over the salt then the nonce → a stable-per-blob, non-zero
  /// 32-bit seed.
  static int _seed(List<int> nonce) {
    int h = 2166136261;
    for (final int c in salt.codeUnits) {
      h = ((h ^ c) * 16777619) & _mask32;
    }
    for (final int b in nonce) {
      h = ((h ^ b) * 16777619) & _mask32;
    }
    return h == 0 ? 0x9E3779B9 : h;
  }

  /// xorshift32 — one keystream byte per call, so the stream never repeats
  /// on a short period the way a fixed XOR key would.
  static int _next(int state) {
    int x = state & _mask32;
    x = (x ^ ((x << 13) & _mask32)) & _mask32;
    x = (x ^ (x >> 17)) & _mask32;
    x = (x ^ ((x << 5) & _mask32)) & _mask32;
    return x == 0 ? 0x9E3779B9 : x;
  }
}
