import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../settings_service.dart';
import 'web_autoclear_policy.dart';
import 'web_history_service.dart';

/// The four checkboxes of the Clear dialog (web.md · Clear data — LOCKED):
/// Browsing history · Cookies & site data · Cached images & files ·
/// Downloads.
@immutable
class WebDataClearFlags {
  const WebDataClearFlags({
    this.history = true,
    this.cookies = true,
    this.cache = true,
    this.downloads = false,
  });

  /// The whole browser footprint — what the auto-clear schedule wipes.
  static const WebDataClearFlags all =
      WebDataClearFlags(history: true, cookies: true, cache: true, downloads: true);

  final bool history;
  final bool cookies;
  final bool cache;
  final bool downloads;
}

/// Data footprint summary for browsing data items.
@immutable
class WebDataFootprint {
  const WebDataFootprint({
    this.historyCount = 0,
    this.historyBytes = 0,
    this.cookiesBytes = 0,
    this.cacheBytes = 0,
  });

  final int historyCount;
  final int historyBytes;
  final int cookiesBytes;
  final int cacheBytes;

  String get historyLabel {
    if (historyCount == 0) return 'None';
    final String items = historyCount == 1 ? '1 item' : '$historyCount items';
    return items;
  }

  String get cookiesLabel {
    if (cookiesBytes <= 0) return 'None';
    return WebDataControlService.formatBytes(cookiesBytes);
  }

  String get cacheLabel {
    if (cacheBytes <= 0) return 'None';
    return WebDataControlService.formatBytes(cacheBytes);
  }
}

/// Owner of everything the browser leaves BEHIND on disk: the WebView2
/// profile (cookies, site storage, download bookkeeping), the browsing
/// history store, and the auto-clear schedule.
///
/// Profile strategy in one paragraph: every tab shares ONE WebView2
/// environment parked under `%LOCALAPPDATA%\SALU\WebView2`, created before
/// the first controller starts. The plugin exposes no profile-wide delete
/// (there is `clearCookies` / `clearCache` per view, nothing for
/// localStorage/IndexedDB), so the thorough clear is a folder purge —
/// and a live environment locks its files. A purge therefore runs at the
/// one moment it is guaranteed to succeed: at startup, before the
/// environment exists. The Clear dialog applies everything the running
/// engine CAN drop immediately, and marks the rest for the next session;
/// auto-clear "on player closing" (the web.md-recommended, most reliable
/// timing) is realised the same way — the close-time sweep hands the
/// actual delete to the next launch, and no browser data ever survives a
/// close into browsing again.
class WebDataControlService {
  WebDataControlService._internal();

  static final WebDataControlService instance = WebDataControlService._internal();

  static const String _purgeKey = 'web_profile_purge_pending';
  static const String _lastAutoClearKey = 'web_last_auto_clear';

  /// The one WebView2 profile SALU ever uses (never the default one, which
  /// would sit next to the executable and be out of reach of a purge).
  static const String _profileFolder = 'WebView2';
  static const String _appFolder = 'SALU';

  bool _purgePending = false;
  bool _prepared = false;
  Future<void>? _prepare;
  bool _autoClearOpenDone = false;

  /// Live controllers — the clear API can speak to them directly.
  final Set<WebviewController> _live = <WebviewController>{};

  void attach(WebviewController controller) => _live.add(controller);

  void detach(WebviewController controller) => _live.remove(controller);

  /// The shared environment is per-process and can only be created once —
  /// the first Webview pays for it (see [WebTab] start-up ordering).
  ///
  /// Awaits: any scheduled purge, then the open-timed auto-clear, THEN the
  /// environment — in that order the folder delete can never fight a live
  /// runtime.
  Future<void> prepare() {
    return _prepare ??= () async {
      try {
        await _purgePendingProfile();
        await runAutoClearOnOpen();
        await _ensureEnvironment();
      } catch (_) {
        // A failing warm-up must not strand the browser in `await` forever;
        // individual tab starts surface their own error state instead.
      } finally {
        _prepared = true;
      }
    }();
  }

  bool get isPrepared => _prepared;

  // ── Profile ────────────────────────────────────────────────────────────

  /// `%LOCALAPPDATA%\SALU\WebView2` — `null` off Windows or without the
  /// env var, where a purge is neither possible nor meaningful.
  static String? profilePath() {
    if (!Platform.isWindows) return null;
    final String? local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    return p.join(local, _appFolder, _profileFolder);
  }

  static bool profileExists() {
    final String? path = profilePath();
    return path != null && Directory(path).existsSync();
  }

  Future<void> _ensureEnvironment() async {
    if (!Platform.isWindows) return;
    final String? path = profilePath();
    if (path == null) return; // no known writable spot — take the default
    try {
      await WebviewController.initializeEnvironment(userDataPath: path);
    } catch (_) {
      // Older runtime / locked path — controllers fall back to whatever
      // environment the plugin itself can build (or fail per-tab, visibly).
    }
  }

  /// Marks the profile folder for deletion at the next startup.
  Future<void> scheduleProfilePurge() async {
    if (!Platform.isWindows) return;
    if (_purgePending) return;
    _purgePending = true;
    await _writeFlag(true);
  }

  bool get purgePending => _purgePending;

  /// Runs a marked purge. Called from [prepare] — before any environment
  /// exists, which is exactly why the delete is guaranteed to work.
  Future<void> _purgePendingProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Read the persisted flag too: a marker written during the last
    // session's close guard must survive into this one.
    final bool flagged = prefs.getBool(_purgeKey) ?? false;
    if (!flagged) return;
    _purgePending = true;
    await deleteProfileFolder();
    await _writeFlag(false);
  }

  /// Deletes the profile folder, best effort (locked stragglers simply
  /// survive into the next purge attempt). Clears the marker either way.
  Future<void> deleteProfileFolder() async {
    _purgePending = false;
    await _writeFlag(false);
    if (!Platform.isWindows) return;
    final String? path = profilePath();
    if (path == null) return;
    try {
      final Directory dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // WebView2 stragglers may still hold the directory for a moment —
      // re-mark so the next startup finishes the job.
      _purgePending = true;
      await _writeFlag(true);
    }
  }

  Future<void> _writeFlag(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_purgeKey, true);
      } else {
        await prefs.remove(_purgeKey);
      }
    } catch (_) {
      // Persistence is best-effort; the in-memory mark still applies.
    }
  }

  // ── The clear itself ───────────────────────────────────────────────────

  /// Applies the Clear dialog (web.md · Clear data). The browser's own
  /// stores drop instantly; profile-only data (site storage, downloads)
  /// goes now when the engine is not up yet, otherwise at the next
  /// startup — the folder purge is the only complete answer and a live
  /// engine locks it.
  Future<void> clear(WebDataClearFlags flags) async {
    if (flags.history) WebHistoryService.instance.clear();

    if (flags.cookies || flags.downloads) {
      if (!_prepared) {
        // Before the first environment: the folder can go right now.
        await deleteProfileFolder();
      } else {
        await scheduleProfilePurge();
      }
    }

    // Copy: the set may change as tabs die.
    for (final WebviewController c in _live.toList()) {
      try {
        if (flags.cookies) await c.clearCookies().timeout(_perTabTimeout);
      } catch (_) {}
      try {
        if (flags.cache) await c.clearCache().timeout(_perTabTimeout);
      } catch (_) {}
    }
  }

  static const Duration _perTabTimeout = Duration(seconds: 3);

  // ── Data Footprint Measurement ──────────────────────────────────────────

  /// Formats byte count into a clean human-readable string (Edge/Chrome style).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    int digitGroups = 0;
    double size = bytes.toDouble();
    while (size >= 1024.0 && digitGroups < units.length - 1) {
      size /= 1024.0;
      digitGroups++;
    }
    if (digitGroups == 0) return '${bytes.toInt()} B';
    return '${size.toStringAsFixed(size >= 10 || digitGroups == 1 ? 0 : 1)} ${units[digitGroups]}';
  }

  /// Calculates the total size in bytes of all files in [dir], recursively.
  static int _calculateDirSize(Directory dir) {
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      final List<FileSystemEntity> entities =
          dir.listSync(recursive: true, followLinks: false);
      for (final FileSystemEntity entity in entities) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Estimates the size of WebView2 cache files.
  /// Common subdirectories in the user profile for cache:
  /// EBWebView/Default/Cache, EBWebView/Default/Code Cache, etc.
  static int getCacheBytes() {
    final String? profile = profilePath();
    if (profile == null) return 0;
    final Directory dir = Directory(profile);
    if (!dir.existsSync()) return 0;

    int total = 0;
    final List<String> candidateRelPaths = <String>[
      p.join('EBWebView', 'Default', 'Cache'),
      p.join('EBWebView', 'Default', 'Code Cache'),
      p.join('EBWebView', 'Default', 'GPUCache'),
      p.join('EBWebView', 'ShaderCache'),
      p.join('Default', 'Cache'),
      p.join('Default', 'Code Cache'),
      p.join('Default', 'GPUCache'),
    ];

    bool foundSpecific = false;
    for (final String rel in candidateRelPaths) {
      final Directory target = Directory(p.join(profile, rel));
      if (target.existsSync()) {
        foundSpecific = true;
        total += _calculateDirSize(target);
      }
    }

    // If standard subfolder structure isn't matched directly, scan for any 'Cache' dir
    if (!foundSpecific) {
      try {
        final List<FileSystemEntity> entities =
            dir.listSync(recursive: false, followLinks: false);
        for (final FileSystemEntity entity in entities) {
          if (entity is Directory && p.basename(entity.path).toLowerCase().contains('cache')) {
            total += _calculateDirSize(entity);
          }
        }
      } catch (_) {}
    }

    return total;
  }

  /// Estimates the size of cookies and site data (storage, IndexedDB, WebSQL, etc).
  static int getCookiesAndSiteDataBytes() {
    final String? profile = profilePath();
    if (profile == null) return 0;
    final Directory dir = Directory(profile);
    if (!dir.existsSync()) return 0;

    final List<String> siteDataRelPaths = <String>[
      p.join('EBWebView', 'Default', 'Cookies'),
      p.join('EBWebView', 'Default', 'Cookies-journal'),
      p.join('EBWebView', 'Default', 'Network', 'Cookies'),
      p.join('EBWebView', 'Default', 'Local Storage'),
      p.join('EBWebView', 'Default', 'IndexedDB'),
      p.join('EBWebView', 'Default', 'Session Storage'),
      p.join('EBWebView', 'Default', 'databases'),
      p.join('EBWebView', 'Default', 'Service Worker'),
      p.join('Default', 'Cookies'),
      p.join('Default', 'Cookies-journal'),
      p.join('Default', 'Network', 'Cookies'),
      p.join('Default', 'Local Storage'),
      p.join('Default', 'IndexedDB'),
      p.join('Default', 'Session Storage'),
      p.join('Default', 'databases'),
    ];

    int total = 0;
    bool foundSpecific = false;
    for (final String rel in siteDataRelPaths) {
      final String full = p.join(profile, rel);
      if (FileSystemEntity.isFileSync(full)) {
        foundSpecific = true;
        try {
          total += File(full).lengthSync();
        } catch (_) {}
      } else if (FileSystemEntity.isDirectorySync(full)) {
        foundSpecific = true;
        total += _calculateDirSize(Directory(full));
      }
    }

    // If specific folders not found but profile exists and not cache,
    // take profile size minus cache
    if (!foundSpecific && total == 0) {
      final int allProfile = _calculateDirSize(dir);
      final int cache = getCacheBytes();
      if (allProfile > cache) {
        total = allProfile - cache;
      }
    }

    return total;
  }

  /// Returns the estimate of browsing data footprint for all categories:
  /// - history count (number of visits) and JSON size
  /// - cookies & site data size in bytes
  /// - cached images & files size in bytes
  /// - downloads record count / folder hint
  static Future<WebDataFootprint> measureFootprint() async {
    // 1. History
    final int historyCount = WebHistoryService.instance.entries.value.length;
    int historyBytes = 0;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(WebHistoryService.prefsKey);
      if (raw != null) historyBytes = raw.length;
    } catch (_) {}

    // 2. Cache
    int cacheBytes = 0;
    // 3. Cookies & Site Data
    int cookiesBytes = 0;

    if (Platform.isWindows) {
      try {
        cacheBytes = getCacheBytes();
        cookiesBytes = getCookiesAndSiteDataBytes();
      } catch (_) {}
    }

    return WebDataFootprint(
      historyCount: historyCount,
      historyBytes: historyBytes,
      cookiesBytes: cookiesBytes,
      cacheBytes: cacheBytes,
    );
  }

  // ── Auto-clear schedule (web.md · Auto-clear — LOCKED) ─────────────────

  /// "On player opening". Runs inside [prepare] so a scheduled purge is
  /// gone BEFORE the environment is created — and never twice a process.
  Future<void> runAutoClearOnOpen() async {
    if (_autoClearOpenDone) return;
    _autoClearOpenDone = true;
    final SettingsService settings = SettingsService.instance;
    if (!WebAutoClearPolicy.firesAt(
        settings.webAutoClearTiming.value, WebAutoClearTrigger.open)) {
      return;
    }
    await _runDue(settings, purgeNow: true);
  }

  /// "On player closing" — the web.md-noted reliable timing. The close
  /// guard awaits this before `exit(0)`: the browser's own stores go
  /// immediately; the locked profile folder is handed to the next
  /// startup's [prepare] (see the class doc for why).
  Future<void> runAutoClearOnClose() async {
    final SettingsService settings = SettingsService.instance;
    if (!WebAutoClearPolicy.firesAt(
        settings.webAutoClearTiming.value, WebAutoClearTrigger.close)) {
      return;
    }
    await _runDue(settings, purgeNow: false);
  }

  Future<void> _runDue(SettingsService settings, {required bool purgeNow}) async {
    final DateTime? last = await _lastRun();
    final DateTime now = DateTime.now();
    if (!WebAutoClearPolicy.isDue(
      interval: settings.webAutoClearDays.value,
      now: now,
      lastRun: last,
    )) {
      return;
    }
    if (!hasBrowserData()) return; // nothing to sweep — stay quiet
    await clear(WebDataClearFlags.all);
    if (purgeNow) await deleteProfileFolder();
    await _recordRun(now);
  }

  bool hasBrowserData() =>
      !WebHistoryService.instance.isEmpty || profileExists();

  Future<DateTime?> _lastRun() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_lastAutoClearKey);
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordRun(DateTime at) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAutoClearKey, at.toIso8601String());
    } catch (_) {
      // Best-effort, like every SALU prefs write.
    }
  }
}
