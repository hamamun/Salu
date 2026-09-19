import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../settings_service.dart';

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

/// The shape of a Save As answer: the chosen path, or `null` for the
/// dialog's Cancel. One seam type so a test can stand in for the shell.
typedef WebSavePicker = Future<String?> Function({
  required String suggestedName,
  String? initialDirectory,
});

/// The shape of a folder-picker answer: the chosen folder, or `null`.
typedef WebFolderPicker = Future<String?> Function();

/// What one Save As question came back with (Settings → Web → Downloads).
enum WebSaveKind {
  /// The viewer chose a place — [WebSaveAnswer.path] is it.
  save,

  /// The viewer walked away from the dialog: the download never happens.
  cancel,

  /// SALU could not ask (asking is off, the picker refused, anything
  /// unexpected) — the engine's own path stands and the file still lands.
  engineDefault,
}

/// SALU's answer about where one download should land.
///
/// Deliberately free of the plugin's own types: this service still knows
/// nothing about the engine, and [WebTab] is the translator in this
/// direction exactly as it is for the reports coming the other way.
@immutable
class WebSaveAnswer {
  /// Save the file to [path] — an absolute path, file name included. The
  /// parameter is non-nullable on purpose: a "save" with no place to save
  /// to is not a save, and the other two answers say what they mean.
  const WebSaveAnswer.toPath(String savePath)
      : path = savePath,
        kind = WebSaveKind.save;

  /// Drop the download: nothing is written and nothing is reported.
  const WebSaveAnswer.cancelled()
      : path = null,
        kind = WebSaveKind.cancel;

  /// Let the engine use the path it had already worked out.
  const WebSaveAnswer.engineDefault()
      : path = null,
        kind = WebSaveKind.engineDefault;

  final WebSaveKind kind;
  final String? path;

  bool get isSave => kind == WebSaveKind.save;
  bool get isCancel => kind == WebSaveKind.cancel;
  bool get isEngineDefault => kind == WebSaveKind.engineDefault;
}

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

/// SALU's download log, the badge's only source of truth — and the answer
/// to where a download lands.
///
/// The engine reports every download itself — `add_DownloadStarting`,
/// `add_BytesReceivedChanged` and `add_StateChanged` in the vendored
/// plugin (`third_party/webview_windows/windows/webview.cc`) reach Dart
/// as `WebviewController.onDownloadEvent`. `WebTab._wire` listens and
/// hands the plain values here through [report], so this service knows
/// nothing about the plugin and stays unit-testable.
///
/// Since the Downloads lock of 2026-09-19 (web.md), the traffic runs the
/// other way as well: with Settings → Web → Downloads asking, the engine
/// holds a download on its own deferral and SALU — through
/// [askWhereToSave] — opens the native Windows Save As for it, one dialog
/// at a time. A place chosen becomes the file's path, a Cancel drops the
/// download before a byte is written (so it never reaches the log at all),
/// and any way the question can fail answers "your own default is fine"
/// rather than losing the file.
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
  /// can exercise [load] from a genuinely cold start. The prompt queue is
  /// emptied with them — a test must never inherit another's waiting Save
  /// As — and the two shell-dialog seams go back to the real dialogs.
  @visibleForTesting
  void debugResetForTest() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _lastProgressMs.clear();
    _promptTail = Future<WebSaveAnswer>.value(
        const WebSaveAnswer.engineDefault());
    debugSaveLocationPicker = null;
    debugFolderPicker = null;
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

  // ── Where a download lands (Settings → Web → Downloads) ──────────────

  /// The Save As seam — `null` in the app, where the native Windows dialog
  /// answers; a test replaces it to answer without a window (and
  /// [debugResetForTest] puts it back). Returns the chosen path, or `null`
  /// when the viewer walked away from the dialog.
  @visibleForTesting
  static WebSavePicker? debugSaveLocationPicker;

  /// The folder-picker seam, beside [debugSaveLocationPicker] for the same
  /// reason (see [pickDownloadFolder]).
  @visibleForTesting
  static WebFolderPicker? debugFolderPicker;

  /// Asks the seam if there is one, the shell if there is not.
  static Future<String?> _pick({
    required String suggestedName,
    String? initialDirectory,
  }) {
    final WebSavePicker? seam = debugSaveLocationPicker;
    if (seam != null) {
      return seam(
        suggestedName: suggestedName,
        initialDirectory: initialDirectory,
      );
    }
    return _nativeSaveLocation(
      suggestedName: suggestedName,
      initialDirectory: initialDirectory,
    );
  }

  /// The native Windows Save As — the same shell dialog Edge and Chrome
  /// open, reached through `file_selector` (already a SALU dependency for
  /// Open File… / Open Folder…), which is why it brings its own overwrite
  /// warning and its own "file (1).mp4" naming for free.
  static Future<String?> _nativeSaveLocation({
    required String suggestedName,
    String? initialDirectory,
  }) async {
    final fs.FileSaveLocation? picked = await fs.getSaveLocation(
      acceptedTypeGroups: _saveTypeGroups(suggestedName),
      initialDirectory: initialDirectory == null || initialDirectory.isEmpty
          ? null
          : initialDirectory,
      suggestedName: suggestedName.isEmpty ? null : suggestedName,
      confirmButtonText: 'Save',
    );
    return picked?.path;
  }

  /// The dialog's filter list: the file's own extension first — the shell
  /// then completes a name typed without one, the way Chrome's Save As
  /// does — and "All files" behind it, so nothing is ever un-saveable.
  static List<fs.XTypeGroup> _saveTypeGroups(String fileName) {
    final String ext = p.extension(fileName);
    final String bare = ext.startsWith('.') ? ext.substring(1) : ext;
    return <fs.XTypeGroup>[
      if (bare.isNotEmpty)
        fs.XTypeGroup(label: bare.toUpperCase(), extensions: <String>[bare]),
      const fs.XTypeGroup(label: 'All files'),
    ];
  }

  /// The folder picker behind Settings → Web → Downloads → Change… — the
  /// native Windows dialog SALU's Open Folder… already uses, and the
  /// setting that follows it. A Cancel changes nothing. Answers whether
  /// the folder actually moved, so the row can stay quiet about a picker
  /// the viewer walked away from.
  ///
  /// The seam lives beside [debugSaveLocationPicker] for the same reason:
  /// every shell dialog SALU opens is in this one service, and a test can
  /// answer both without a window.
  static Future<bool> pickDownloadFolder() async {
    try {
      final WebFolderPicker? seam = debugFolderPicker;
      final String? dir = await (seam == null ? _nativeFolderPick() : seam());
      if (dir == null || dir.trim().isEmpty) return false;
      await SettingsService.instance.setWebDownloadFolder(dir.trim());
      return true;
    } catch (_) {
      // No picker here, or a path the shell would not give back — the
      // folder in force stays in force.
      return false;
    }
  }

  static Future<String?> _nativeFolderPick() => fs.getDirectoryPath();

  /// The prompt queue's tail ([askWhereToSave] owns it). One Save As at a
  /// time: a page that fires three downloads at once must not stack three
  /// dialogs, so each waits for the one before it — and each download
  /// simply sits on its own engine deferral until its turn comes, which is
  /// exactly what the deferral is for.
  Future<WebSaveAnswer> _promptTail =
      Future<WebSaveAnswer>.value(const WebSaveAnswer.engineDefault());

  /// Asks where one download should land, and answers with what the
  /// viewer decided ([WebSaveAnswer]).
  ///
  /// [suggestedPath] is the engine's own full target path — its folder is
  /// the dialog's starting point when the viewer has chosen none, and its
  /// file name is what the dialog pre-fills.
  ///
  /// Never throws and never hangs on a failure: every way this can go
  /// wrong answers [WebSaveAnswer.engineDefault], because a question SALU
  /// could not ask must never cost the viewer their file.
  Future<WebSaveAnswer> askWhereToSave(String suggestedPath) {
    final Future<WebSaveAnswer> mine =
        _promptTail.then((WebSaveAnswer _) => _askOnce(suggestedPath));
    // The tail never carries an error of its own, so a queue can neither
    // stall nor leave an unhandled exception behind it.
    _promptTail =
        mine.catchError((Object _) => const WebSaveAnswer.engineDefault());
    return mine;
  }

  Future<WebSaveAnswer> _askOnce(String suggestedPath) async {
    try {
      // The switch may have been flipped while this prompt waited in the
      // queue — the latest word wins, and "off" means stop asking.
      if (!SettingsService.instance.webAskDownloadLocation.value) {
        return const WebSaveAnswer.engineDefault();
      }
      final String name = p.basename(suggestedPath);
      final String start = _startFolderFor(suggestedPath);
      final String? picked = await _pick(
        suggestedName: name.isEmpty ? 'download' : name,
        initialDirectory: start.isEmpty ? null : start,
      );
      if (picked == null || picked.trim().isEmpty) {
        // The dialog's Cancel: no file, and nothing for the shelf — a
        // download the viewer refused is not a failed download.
        return const WebSaveAnswer.cancelled();
      }
      return WebSaveAnswer.toPath(picked.trim());
    } catch (_) {
      // No picker here, a window that will not open, a path the shell
      // refused — the engine's own folder takes the file instead.
      return const WebSaveAnswer.engineDefault();
    }
  }

  /// Where the Save As starts: the viewer's chosen folder when there is
  /// one (that is the whole point of the setting), else the folder the
  /// engine suggested — which is Windows' own Downloads, relocated one
  /// included, and so a better guess than any SALU could compute.
  static String _startFolderFor(String suggestedPath) {
    final String custom =
        SettingsService.instance.webDownloadFolder.value.trim();
    if (custom.isNotEmpty) return custom;
    final String dir = p.dirname(suggestedPath);
    if (dir.isNotEmpty && dir != '.' && dir != '/' && dir != '\\') return dir;
    return downloadsFolder();
  }

  // ── Explorer's two answers ───────────────────────────────────────────

  /// Opens [path]'s own folder with the file selected — the honest
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

  /// Opens the folder holding [path] — or the download folder when [path]
  /// is null (the shelf's footer, which must work with an empty log).
  /// Never throws: a folder that will not open is not an error the browser
  /// can do anything about.
  Future<void> openFolder(String? path) async {
    final String target =
        path != null && path.isNotEmpty ? p.dirname(path) : downloadsFolder();
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

  /// The folder downloads belong to — the viewer's own choice when there
  /// is one (Settings → Web → Downloads), else Windows' own Downloads.
  /// The shelf's footer opens this; the Save As falls back to it only when
  /// the engine suggested no folder of its own.
  static String downloadsFolder() {
    final String custom =
        SettingsService.instance.webDownloadFolder.value.trim();
    if (custom.isNotEmpty) return custom;
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
