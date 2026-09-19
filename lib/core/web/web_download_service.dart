import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Where one download stands.
///
/// `failed` has two sources. The engine's own interrupted state is one —
/// but the vendored plugin swallows it (`webview.cc` catches
/// `DOWNLOAD_STATE_INTERRUPTED` and forwards nothing), so until that
/// vendor delta lands the state SALU can actually see is the other one:
/// its own stale sweep. A row that has not moved for
/// [WebDownloadService.staleAfter] is reported interrupted, which keeps a
/// dead download from holding the badge hostage — and it self-corrects,
/// because the next real progress report puts the row back to `running`.
enum WebDownloadState { running, completed, failed }

/// One download row: what the engine said, in SALU's own words.
///
/// [key] is the row's identity — the engine's target path, which is
/// decided at `DownloadStarting` and never changes for that download.
/// Two downloads of the same URL get two different paths from the engine
/// (`file.mp4`, `file (1).mp4`), so the path is the only stable key the
/// event stream carries (the plugin's event has no download id —
/// `third_party/webview_windows/windows/webview.h`, `WebviewDownloadEvent`).
@immutable
class WebDownloadItem {
  const WebDownloadItem({
    required this.key,
    required this.url,
    required this.path,
    required this.received,
    required this.total,
    required this.state,
    required this.startedMs,
    this.endedMs,
    this.lastEventMs = 0,
  });

  final String key;
  final String url;

  /// The file's full path on disk. Known from the first event, so a row
  /// can be revealed in Explorer before its last byte lands.
  final String path;

  final int received;

  /// Total size in bytes; `0` = the server never said (then [progress]
  /// is `null` and the row shows bytes only, never a fake percentage).
  final int total;

  final WebDownloadState state;
  final int startedMs;
  final int? endedMs;

  /// When this row last heard anything from the engine — the stale
  /// sweep's clock. Not persisted: a row that survives a restart is
  /// already finished.
  final int lastEventMs;

  bool get isRunning => state == WebDownloadState.running;
  bool get isCompleted => state == WebDownloadState.completed;
  bool get isFailed => state == WebDownloadState.failed;

  /// The file's own name — the row's headline. The path always carries
  /// one; the URL is the fallback for a row the engine named nowhere,
  /// stripped of its query and fragment so a token never reaches the
  /// screen (the channel-failure rule, playlist_imp.md §10.10e).
  String get fileName {
    final String base = p.basename(path);
    if (base.isNotEmpty && base != '.' && base != '/') return base;
    final String bare = url.split('?').first.split('#').first;
    final String tail = p.basename(bare);
    return tail.isEmpty ? 'download' : tail;
  }

  /// 0…1 while the server gave a size, else `null`.
  double? get progress {
    if (total <= 0) return null;
    final double f = received / total;
    if (f < 0) return 0.0;
    return f > 1 ? 1.0 : f;
  }

  WebDownloadItem copyWith({
    String? path,
    int? received,
    int? total,
    WebDownloadState? state,
    int? endedMs,
    int? lastEventMs,
  }) {
    return WebDownloadItem(
      key: key,
      url: url,
      path: path ?? this.path,
      received: received ?? this.received,
      total: total ?? this.total,
      state: state ?? this.state,
      startedMs: startedMs,
      endedMs: endedMs ?? this.endedMs,
      lastEventMs: lastEventMs ?? this.lastEventMs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        'path': path,
        'received': received,
        'total': total,
        'state': state.index,
        'at': startedMs,
        if (endedMs != null) 'ended': endedMs,
      };

  static WebDownloadItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    final Object? path = m['path'];
    final Object? at = m['at'];
    final Object? state = m['state'];
    if (path is! String || path.isEmpty) return null;
    if (at is! int) return null;
    final int si = state is int ? state : WebDownloadState.completed.index;
    // A row that was still running when the app closed never finished —
    // the engine cannot resume it, so it is restored as failed rather
    // than left spinning on the badge for a download that is not there.
    final WebDownloadState st =
        si == WebDownloadState.running.index || si >= WebDownloadState.values.length
            ? WebDownloadState.failed
            : WebDownloadState.values[si];
    final Object? ended = m['ended'];
    return WebDownloadItem(
      key: path,
      url: m['url'] is String ? m['url'] as String : '',
      path: path,
      received: m['received'] is int ? m['received'] as int : 0,
      total: m['total'] is int ? m['total'] as int : 0,
      state: st,
      startedMs: at,
      endedMs: ended is int ? ended : null,
    );
  }
}

/// SALU's download log and the badge's only source of truth.
///
/// The engine reports every download itself — `add_DownloadStarting`,
/// `add_BytesReceivedChanged` and `add_StateChanged` in the vendored
/// plugin (`third_party/webview_windows/windows/webview.cc`) reach Dart
/// as `WebviewController.onDownloadEvent`. `WebTab._wire` listens and
/// hands the plain values here through [report], so this service knows
/// nothing about the plugin and stays unit-testable.
///
/// What it keeps:
///   · [items]     — the log, newest first (running rows included)
///   · [running]   — how many are still travelling (the badge's ring)
///   · [unseen]    — finishes nobody has looked at yet (the badge's
///                   reason to stay after the last byte lands)
///   · [finished]  — the completion pulse the Player-mode deck listens to
///
/// Finished rows persist as one JSON blob under [prefsKey], newest
/// first, capped at [maxEntries]; a running row never does — the engine
/// cannot resume it, so restoring one would only be a lie.
class WebDownloadService {
  WebDownloadService._internal();

  static final WebDownloadService instance = WebDownloadService._internal();

  static const int maxEntries = 200;
  static const String prefsKey = 'web_downloads';

  /// Disk writes coalesce for this long after the last change.
  static const Duration _writeThrottle = Duration(milliseconds: 400);

  /// `BytesReceivedChanged` fires per network chunk; publishing every one
  /// of them would rebuild the shelf dozens of times a second. Progress
  /// reports inside this window are dropped unless they complete the row.
  static const Duration progressThrottle = Duration(milliseconds: 200);

  /// How long a row may sit motionless before SALU calls it what it
  /// looks like: interrupted. Generous on purpose — a big file on a slow
  /// line still reports every chunk it gets, so two minutes of absolute
  /// silence is a dead connection, not a slow one. And the verdict is
  /// reversible: the next real report puts the row back to running.
  static const Duration staleAfter = Duration(minutes: 2);

  /// How often the sweep looks.
  static const Duration _sweepEvery = Duration(seconds: 15);

  final ValueNotifier<List<WebDownloadItem>> items =
      ValueNotifier<List<WebDownloadItem>>(const <WebDownloadItem>[]);

  /// Live download count — the badge's ring and the shelf's headline.
  final ValueNotifier<int> running = ValueNotifier<int>(0);

  /// Finishes since the shelf was last looked at.
  final ValueNotifier<int> unseen = ValueNotifier<int>(0);

  final StreamController<WebDownloadItem> _finished =
      StreamController<WebDownloadItem>.broadcast();

  /// Fires once per finished download (completed OR failed) — the
  /// Player-mode deck's cue that something landed while you watch.
  Stream<WebDownloadItem> get finished => _finished.stream;

  bool _loaded = false;
  bool _shelfOpen = false;
  Timer? _writeTimer;
  Future<void> _lastWrite = Future<void>.value();
  final Map<String, int> _lastProgressMs = <String, int>{};
  Timer? _sweepTimer;

  bool get isEmpty => items.value.isEmpty;
  bool get isBusy => running.value > 0;

  /// Whether the badge has any business being on screen: something is
  /// travelling, or something finished and nobody has seen it yet.
  bool get hasBadge => running.value > 0 || unseen.value > 0;

  /// Reads the persisted log once (safe to call repeatedly).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      items.value = decoded
          .map(WebDownloadItem.fromJson)
          .whereType<WebDownloadItem>()
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      // Corrupt prefs — start clean, silently (the history service rule).
      items.value = const <WebDownloadItem>[];
    }
    _syncCounts(recountUnseen: false);
  }

  /// Completes any pending write — the close guard calls it so the last
  /// download of a session is never lost.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    final Future<void> pending = _lastWrite;
    _lastWrite = _persist();
    await pending;
    await _lastWrite;
  }

  /// Test-only: drops the one-shot load guard and every row, so a test
  /// can exercise [load] from a genuinely cold start.
  @visibleForTesting
  void debugResetForTest() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _lastProgressMs.clear();
    _loaded = false;
    _shelfOpen = false;
    items.value = const <WebDownloadItem>[];
    running.value = 0;
    unseen.value = 0;
  }

  // ── The engine's reports ─────────────────────────────────────────────

  /// One engine event, already stripped of the plugin's types.
  ///
  /// [path] is the engine's target/result path and doubles as the row's
  /// key; [total] `0` means the server never gave a size.
  void report(
    WebDownloadState state, {
    required String url,
    required String path,
    required int received,
    required int total,
    DateTime? at,
  }) {
    final int nowMs = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final String key = path.isNotEmpty ? path : url;
    if (key.isEmpty) return;

    final List<WebDownloadItem> list = List<WebDownloadItem>.of(items.value);
    final int index = list.indexWhere((WebDownloadItem i) => i.key == key);
    final WebDownloadItem? old = index >= 0 ? list[index] : null;

    // Progress is the chatty one: coalesce it. A report that completes
    // the row always lands, however close behind the last one it comes.
    if (state == WebDownloadState.running && old != null) {
      final int? lastMs = _lastProgressMs[key];
      final bool complete = total > 0 && received >= total;
      if (lastMs != null &&
          !complete &&
          nowMs - lastMs < progressThrottle.inMilliseconds) {
        return;
      }
    }
    if (state == WebDownloadState.running) _lastProgressMs[key] = nowMs;

    final WebDownloadItem next;
    if (old == null) {
      next = WebDownloadItem(
        key: key,
        url: url,
        path: path,
        received: received,
        total: total,
        state: state,
        startedMs: nowMs,
        endedMs: state == WebDownloadState.running ? null : nowMs,
        lastEventMs: nowMs,
      );
      list.insert(0, next);
    } else {
      next = old.copyWith(
        // The engine restates the path on completion — take the freshest.
        path: path.isNotEmpty ? path : old.path,
        received: received,
        total: total > 0 ? total : old.total,
        state: state,
        endedMs: state == WebDownloadState.running ? null : nowMs,
        lastEventMs: nowMs,
      );
      list[index] = next;
    }

    if (list.length > maxEntries) list.length = maxEntries;
    items.value = List<WebDownloadItem>.unmodifiable(list);
    _syncCounts();

    if (state != WebDownloadState.running) {
      _lastProgressMs.remove(key);
      _noteFinished(next);
    } else {
      _armSweep();
    }
  }

  /// One finish, counted and announced.
  void _noteFinished(WebDownloadItem item) {
    if (!_shelfOpen) unseen.value = unseen.value + 1;
    _finished.add(item);
  }

  // ── The stale sweep ────────────────────────────────────────────────────

  /// Runs only while something is travelling, and stops itself the moment
  /// nothing is — a browser with no downloads holds no timer.
  void _armSweep() {
    if (_sweepTimer != null) return;
    _sweepTimer = Timer.periodic(_sweepEvery, (_) => _sweep());
  }

  void _sweep() {
    final DateTime now = DateTime.now();
    final List<WebDownloadItem> list = List<WebDownloadItem>.of(items.value);
    bool changed = false;
    for (int i = 0; i < list.length; i++) {
      if (!isStale(list[i], now)) continue;
      list[i] = list[i].copyWith(
        state: WebDownloadState.failed,
        endedMs: now.millisecondsSinceEpoch,
      );
      _lastProgressMs.remove(list[i].key);
      _noteFinished(list[i]);
      changed = true;
    }
    if (changed) {
      items.value = List<WebDownloadItem>.unmodifiable(list);
      _syncCounts();
    }
    if (running.value == 0) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
  }

  /// The shelf is on screen: every finish so far has been seen, and
  /// finishes from here on are seen as they happen.
  void setShelfOpen(bool open) {
    _shelfOpen = open;
    if (open && unseen.value != 0) unseen.value = 0;
  }

  /// Drops one row (the shelf's per-row ×). No confirm, no undo — browser
  /// data never grows an undo path (the history panel's rule).
  void remove(String key) {
    final List<WebDownloadItem> list = List<WebDownloadItem>.of(items.value);
    final int index = list.indexWhere((WebDownloadItem i) => i.key == key);
    if (index < 0) return;
    list.removeAt(index);
    items.value = List<WebDownloadItem>.unmodifiable(list);
    _syncCounts();
  }

  /// Drops every finished row, keeps the ones still travelling.
  void clearFinished() {
    final List<WebDownloadItem> list = items.value
        .where((WebDownloadItem i) => i.isRunning)
        .toList(growable: true);
    if (list.length == items.value.length) return;
    items.value = List<WebDownloadItem>.unmodifiable(list);
    _syncCounts();
  }

  /// The Clear dialog's "Downloads history" (web.md · Clear lock): the
  /// log empties, the files stay on the PC exactly where they landed.
  void clear() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _lastProgressMs.clear();
    if (items.value.isEmpty && unseen.value == 0) return;
    items.value = const <WebDownloadItem>[];
    _syncCounts();
  }

  // ── Explorer's two answers ───────────────────────────────────────────

  /// Opens the Downloads folder with [path] selected — the honest
  /// "Show in folder": Explorer lands ON the file, not merely near it.
  /// Falls back to the folder itself when the select form is refused.
  Future<void> reveal(String path) async {
    if (path.isEmpty) return openFolder(null);
    try {
      await Process.start('explorer', <String>['/select,', path]);
    } catch (_) {
      await openFolder(path);
    }
  }

  /// Opens the folder holding [path] — or the Downloads folder when
  /// [path] is null (the shelf's footer, which must work with an empty
  /// log). Never throws: a folder that will not open is not an error the
  /// browser can do anything about.
  Future<void> openFolder(String? path) async {
    final String target = path != null && path.isNotEmpty
        ? p.dirname(path)
        : _downloadsFolder();
    if (target.isEmpty) return;
    try {
      await Process.start('explorer', <String>[target]);
    } catch (_) {}
  }

  /// The sweep's rule, pure so a test can pin it without waiting two
  /// minutes on a wall clock: a row is stale when it is still marked
  /// running and the engine has been silent about it for [staleAfter].
  static bool isStale(WebDownloadItem item, DateTime now) {
    if (!item.isRunning) return false;
    final int last =
        item.lastEventMs > 0 ? item.lastEventMs : item.startedMs;
    return now.millisecondsSinceEpoch - last > staleAfter.inMilliseconds;
  }

  static String _downloadsFolder() {
    final String home = Platform.environment['USERPROFILE'] ?? '';
    return home.isEmpty ? '' : p.join(home, 'Downloads');
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _syncCounts({bool recountUnseen = true}) {
    int live = 0;
    for (final WebDownloadItem i in items.value) {
      if (i.isRunning) live++;
    }
    if (running.value != live) running.value = live;
    if (recountUnseen && unseen.value > items.value.length) {
      unseen.value = items.value.length;
    }
    _schedulePersist();
  }

  void _schedulePersist() {
    _writeTimer?.cancel();
    _writeTimer = Timer(_writeThrottle, () {
      _writeTimer = null;
      _lastWrite = _persist();
    });
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Running rows never reach disk — a restored spinner would be a
      // download that is not happening.
      final List<Map<String, Object?>> rows = items.value
          .where((WebDownloadItem i) => !i.isRunning)
          .map((WebDownloadItem i) => i.toJson())
          .toList(growable: false);
      if (rows.isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, jsonEncode(rows));
      }
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }
}
