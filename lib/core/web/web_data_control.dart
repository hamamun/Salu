import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../settings_service.dart';
import 'web_autoclear_policy.dart';
import 'web_download_service.dart';
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

/// What a WebView2 profile entry on disk is: browser cache, cookies &
/// site data, or neither (runtime internals SALU never reports).
enum WebProfileStoreKind { none, cache, siteData }

/// Data footprint summary for browsing data items.
@immutable
class WebDataFootprint {
  const WebDataFootprint({
    this.historyCount = 0,
    this.historyBytes = 0,
    this.cookiesBytes = 0,
    this.cacheBytes = 0,
    this.profilePurgePending = false,
  });

  final int historyCount;
  final int historyBytes;
  final int cookiesBytes;
  final int cacheBytes;

  /// True when a full profile purge is already promised for the next
  /// startup (a Clear or auto-clear ran while the engine held the
  /// folder). The locked cookies/cache leftovers behind it count as
  /// cleaned — the badge says "None", never the stale pre-clear size.
  final bool profilePurgePending;

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

  /// The viewer's current page-colours choice (Settings → Web → Page
  /// colours) — what `prefers-color-scheme` is told, engine-wide.
  static WebPageScheme get currentPageScheme =>
      SettingsService.instance.webPageScheme.value;

  /// [WebPageScheme] in the engine's own numbers — the
  /// `CoreWebView2PreferredColorScheme` values exactly (auto = 0,
  /// light = 1, dark = 2). This is the browser-profile control Edge's own
  /// Appearance setting drives; it decides what `prefers-color-scheme`
  /// answers and applies live, no reload or restart.
  static int pageSchemeValue(WebPageScheme scheme) => switch (scheme) {
        WebPageScheme.system => 0,
        WebPageScheme.light => 1,
        WebPageScheme.dark => 2,
      };

  /// Pushes [scheme] into every live engine view right now. The engine
  /// re-evaluates `prefers-color-scheme` in place — the page re-themes
  /// itself the way it would on an OS theme flip. Views started later read
  /// [currentPageScheme] at birth ([WebTab._start]), so one call covers
  /// the whole browser.
  Future<void> applyPageScheme(WebPageScheme scheme) async {
    final int value = pageSchemeValue(scheme);
    for (final WebviewController controller in List.of(_live)) {
      try {
        await controller.setPreferredColorScheme(value);
      } catch (_) {
        // A controller that died between the snapshot and the call, or a
        // runtime too old for the profile API — it simply keeps following
        // the OS. Nothing to clean up.
      }
    }
  }

  void _onPageSchemeChanged() {
    unawaited(applyPageScheme(SettingsService.instance.webPageScheme.value));
  }

  /// Settings → Web → Downloads, the asking half: whether every download
  /// is offered a Save As before a byte of it is written.
  static bool get askWhereToSave =>
      SettingsService.instance.webAskDownloadLocation.value;

  /// Settings → Web → Downloads, the folder half, exactly as the engine
  /// wants it: an absolute path, or '' for "leave the engine's own alone"
  /// — which is Windows' Downloads folder, a relocated one included. SALU
  /// never guesses a path into the profile.
  static String get configuredDownloadFolder =>
      SettingsService.instance.webDownloadFolder.value.trim();

  /// Pushes both halves of Downloads into every live engine view right
  /// now: the asking half applies from the next download, the folder half
  /// to the profile every tab shares (which the engine itself persists in
  /// its user data folder). Views started later read the settings at birth
  /// ([WebTab._start]), so one call covers the whole browser.
  Future<void> applyDownloadPreferences() async {
    final bool ask = askWhereToSave;
    final String folder = configuredDownloadFolder;
    for (final WebviewController controller in List.of(_live)) {
      try {
        await controller.setDownloadPreferences(
          askWhereToSave: ask,
          defaultDownloadFolder: folder,
        );
      } catch (_) {
        // A controller that died between the snapshot and the call, or a
        // runtime too old for the profile API. The asking half lives in
        // the plugin and applies either way; the folder half simply stays
        // at Windows' own Downloads.
      }
    }
  }

  void _onDownloadPreferenceChanged() {
    unawaited(applyDownloadPreferences());
  }

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
        _registerPageSchemeListener();
        _registerDownloadPreferenceListeners();
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

  /// Registers the one live listener that carries a Page colours change
  /// into every running engine view the moment it is picked (Settings →
  /// Web → Page colours). Idempotent — `prepare` runs once per process.
  void _registerPageSchemeListener() {
    SettingsService.instance.webPageScheme.addListener(_onPageSchemeChanged);
  }

  /// The two live listeners that carry a Downloads change (Settings → Web
  /// → Downloads) into every running engine view the moment it is made —
  /// the same contract Page colours has. Idempotent, because `prepare`
  /// runs once per process.
  void _registerDownloadPreferenceListeners() {
    SettingsService.instance.webAskDownloadLocation
        .addListener(_onDownloadPreferenceChanged);
    SettingsService.instance.webDownloadFolder
        .addListener(_onDownloadPreferenceChanged);
  }

  /// Creates the shared environment — the per-process home of the one
  /// WebView2 browser instance SALU runs. No browser-process flags are
  /// passed: page colours go through the engine's own profile API
  /// ([applyPageScheme] / [pageSchemeValue]), which is the supported
  /// control and applies live; the earlier `--blink-settings` command-line
  /// switch was both undocumented and ineffective for this.
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
  ///
  /// "Downloads history" is SALU's own log as well now that the engine's
  /// reports are kept: the rows go, and the FILES stay exactly where
  /// they landed — which is what the dialog's own line always promised.
  Future<void> clear(WebDataClearFlags flags) async {
    if (flags.history) WebHistoryService.instance.clear();

    if (flags.downloads) WebDownloadService.instance.clear();

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

    // The engine-side calls above only reach the live cookie jar and the
    // in-memory HTTP cache. Whatever cache files they leave on disk that
    // the running engine does not hold locked goes now too, so a reopened
    // dialog measures a genuinely smaller cache — not the stale size.
    // (Before the first environment there is nothing live to sweep — the
    // folder delete above already took everything.)
    if (flags.cache && _prepared) await sweepUnlockedCacheFiles();
  }

  static const Duration _perTabTimeout = Duration(seconds: 3);

  // ── Data Footprint Measurement ──────────────────────────────────────────
  //
  // The badges measure SALU's own WebView2 profile — nothing else. Stores
  // are recognised by what they ARE (well-known Chromium store names),
  // wherever the runtime parked them inside the profile (`EBWebView\Default`,
  // `Default`, future layouts) — never by subtracting one guess from
  // another, and never by counting runtime internals (Crashpad, prefs,
  // updaters) as browsing data.

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

  /// Directory names that ARE browser cache inside the profile.
  static const Set<String> _cacheStoreNames = <String>{
    'cache',
    'code cache',
    'gpucache',
    'shadercache',
    'dawncache',
  };

  /// Directory names that ARE cookies & site data (storage the sites own).
  static const Set<String> _siteDataDirNames = <String>{
    'local storage',
    'session storage',
    'indexeddb',
    'databases',
    'service worker',
    'shared storage',
  };

  /// File names that ARE cookies & site data.
  static const Set<String> _siteDataFileNames = <String>{
    'cookies',
    'cookies-journal',
    'cookies-wal',
    'cookies-shm',
  };

  /// Deep enough for `EBWebView\<profile>\Network\Cookies` and friends,
  /// shallow enough to never wander into a store's own contents.
  static const int _scanMaxDepth = 5;

  /// Classifies one profile entry (already lower-cased basename).
  static WebProfileStoreKind classifyProfileEntry(
    String lowerName, {
    required bool isDirectory,
  }) {
    if (isDirectory) {
      if (_cacheStoreNames.contains(lowerName)) {
        return WebProfileStoreKind.cache;
      }
      if (_siteDataDirNames.contains(lowerName)) {
        return WebProfileStoreKind.siteData;
      }
      return WebProfileStoreKind.none;
    }
    return _siteDataFileNames.contains(lowerName)
        ? WebProfileStoreKind.siteData
        : WebProfileStoreKind.none;
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

  /// Walks the profile once and sums every store [kind] entry; a matched
  /// directory is measured whole, so its contents are never double-counted
  /// and never misclassified.
  static int _scanProfileStores(Directory root, WebProfileStoreKind kind) {
    int total = 0;
    void walk(Directory dir, int depth) {
      if (depth > _scanMaxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final FileSystemEntity entity in entries) {
        final String lower = p.basename(entity.path).toLowerCase();
        if (entity is Directory) {
          final WebProfileStoreKind found =
              classifyProfileEntry(lower, isDirectory: true);
          if (found == kind) {
            total += _calculateDirSize(entity);
          } else if (found == WebProfileStoreKind.none) {
            walk(entity, depth + 1);
          }
          // A store of the OTHER kind: leave it to its own scan.
        } else if (entity is File) {
          if (classifyProfileEntry(lower, isDirectory: false) == kind) {
            try {
              total += entity.lengthSync();
            } catch (_) {}
          }
        }
      }
    }

    walk(root, 0);
    return total;
  }

  /// On-disk size of the profile's browser caches (HTTP cache, code cache,
  /// GPU/shader caches) — discovered, not assumed.
  static int getCacheBytes() {
    final String? profile = profilePath();
    if (profile == null) return 0;
    final Directory dir = Directory(profile);
    if (!dir.existsSync()) return 0;
    return _scanProfileStores(dir, WebProfileStoreKind.cache);
  }

  /// On-disk size of cookies & site data (cookie jars, local/session
  /// storage, IndexedDB, Service Workers) — discovered, not assumed.
  static int getCookiesAndSiteDataBytes() {
    final String? profile = profilePath();
    if (profile == null) return 0;
    final Directory dir = Directory(profile);
    if (!dir.existsSync()) return 0;
    return _scanProfileStores(dir, WebProfileStoreKind.siteData);
  }

  /// Best-effort immediate drop of cache files the running engine does not
  /// hold locked — Chromium keeps HTTP-cache entries open with delete
  /// sharing, so these go even mid-session. Locked stragglers simply wait
  /// for the startup purge like everything else the engine owns.
  Future<void> sweepUnlockedCacheFiles() async {
    if (!Platform.isWindows) return;
    final String? profile = profilePath();
    if (profile == null) return;
    final Directory root = Directory(profile);
    if (!root.existsSync()) return;

    final List<Directory> cacheDirs = <Directory>[];
    void walk(Directory dir, int depth) {
      if (depth > _scanMaxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final FileSystemEntity entity in entries) {
        if (entity is! Directory) continue;
        final WebProfileStoreKind kind = classifyProfileEntry(
          p.basename(entity.path).toLowerCase(),
          isDirectory: true,
        );
        if (kind == WebProfileStoreKind.cache) {
          cacheDirs.add(entity);
        } else if (kind == WebProfileStoreKind.none) {
          walk(entity, depth + 1);
        }
      }
    }

    walk(root, 0);

    for (final Directory cacheDir in cacheDirs) {
      List<FileSystemEntity> entries;
      try {
        entries = cacheDir.listSync(recursive: true, followLinks: false);
      } catch (_) {
        continue;
      }
      for (final FileSystemEntity entity in entries) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {
            // Still locked by the live engine — the startup purge takes it.
          }
        }
      }
    }
  }

  /// Returns the estimate of browsing data footprint for all categories:
  /// - history count (number of visits) and JSON size
  /// - cookies & site data size in bytes
  /// - cached images & files size in bytes
  ///
  /// When a profile purge is already promised (a Clear or auto-clear ran
  /// while the engine held the folder), the locked cookie/cache stores
  /// report as cleaned — never the stale pre-clear size that made the
  /// badges look frozen after cleaning.
  static Future<WebDataFootprint> measureFootprint() async {
    // 1. History
    final int historyCount = WebHistoryService.instance.entries.value.length;
    int historyBytes = 0;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(WebHistoryService.prefsKey);
      if (raw != null) historyBytes = raw.length;
    } catch (_) {}

    // 2. Cache + 3. Cookies & site data
    int cacheBytes = 0;
    int cookiesBytes = 0;
    final bool purgePending = instance.purgePending;

    if (Platform.isWindows && !purgePending) {
      try {
        cacheBytes = getCacheBytes();
        cookiesBytes = getCookiesAndSiteDataBytes();
      } catch (_) {}
    }
    // purgePending → both stay 0 ("None"): that data is already promised
    // to the next-startup purge, so it counts as cleaned.

    return WebDataFootprint(
      historyCount: historyCount,
      historyBytes: historyBytes,
      cookiesBytes: cookiesBytes,
      cacheBytes: cacheBytes,
      profilePurgePending: purgePending,
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
