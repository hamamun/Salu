import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_address.dart';
import 'web_suggestions.dart';

/// One visited page, newest first.
@immutable
class WebHistoryEntry {
  const WebHistoryEntry({
    required this.url,
    required this.title,
    required this.visitedMs,
  });

  final String url;

  /// The page's own `<title>` when it had one — empty until it does.
  final String title;
  final int visitedMs;

  String get displayTitle =>
      title.isNotEmpty ? title : WebAddress.labelFor(url);

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        if (title.isNotEmpty) 'title': title,
        'at': visitedMs,
      };

  static WebHistoryEntry? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final Object? title = raw['title'];
    final Object? at = raw['at'];
    return WebHistoryEntry(
      url: url,
      title: title is String ? title : '',
      visitedMs: at is int ? at : 0,
    );
  }
}

/// SALU's own browsing history for the web mode — the second suggestion
/// source, and the data the Clear dialog's "Browsing history" checkbox
/// wipes (web.md · address bar and Clear locks).
///
/// It is deliberately separate from the resume store (`resume_positions`):
/// clearing the browser's footprint must never touch playback memory —
/// "Clearing never touches SALU's own data" (web.md · Clear lock).
///
/// The list is persisted as one JSON blob under `web_browsing_history`,
/// newest first, capped at [maxEntries]; writes are throttled so a fast
/// redirect chain does not hammer the disk.
class WebHistoryService {
  WebHistoryService._internal();

  static final WebHistoryService instance = WebHistoryService._internal();

  static const int maxEntries = 500;
  static const String _prefsKey = 'web_browsing_history';

  /// Consecutive visits to the SAME page collapse while the title keeps
  /// arriving (redirects, in-page pushes); beyond this window a real
  /// revisit is recorded again.
  static const Duration _mergeWindow = Duration(minutes: 2);

  /// Disk writes coalesce for this long after the last change.
  static const Duration _writeThrottle = Duration(milliseconds: 400);

  /// The live list, newest first. UI listens and rebuilds.
  final ValueNotifier<List<WebHistoryEntry>> entries =
      ValueNotifier<List<WebHistoryEntry>>(const <WebHistoryEntry>[]);

  bool _loaded = false;
  Timer? _writeTimer;
  Future<void> _lastWrite = Future<void>.value();

  bool get isEmpty => entries.value.isEmpty;

  /// Reads the persisted list once (safe to call repeatedly).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      entries.value = decoded
          .map((Object? e) => WebHistoryEntry.fromJson(
              e is Map ? e.cast<String, Object?>() : e))
          .whereType<WebHistoryEntry>()
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      // Corrupt prefs — start clean, silently (the UrlLibraryService rule).
      entries.value = const <WebHistoryEntry>[];
    }
  }

  void _set(List<WebHistoryEntry> next) {
    entries.value = List<WebHistoryEntry>.unmodifiable(next);
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
      await prefs.setString(
        _prefsKey,
        jsonEncode(entries.value
            .map((WebHistoryEntry e) => e.toJson())
            .toList(growable: false)),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }

  /// Completes every pending write — called from the close guard so the
  /// last visit of a session is never lost.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    final Future<void> pending = _lastWrite;
    _lastWrite = _persist();
    await pending;
    await _lastWrite;
  }

  /// Records a finished navigation. Non-web pages (`about:`, blank) are
  /// not visits and never enter the store.
  void record(String url, {String? title}) {
    if (!_isWebPage(url)) return;
    final List<WebHistoryEntry> list = List<WebHistoryEntry>.of(entries.value);
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (list.isNotEmpty &&
        WebAddress.samePage(list.first.url, url) &&
        now - list.first.visitedMs <= _mergeWindow.inMilliseconds) {
      // Same page again within the window — merge, keeping the freshest
      // title. Redirects must not stack a row per hop.
      final String nextTitle =
          (title != null && title.isNotEmpty) ? title : list.first.title;
      if (nextTitle == list.first.title) return;
      list[0] = WebHistoryEntry(
        url: url,
        title: nextTitle,
        visitedMs: list.first.visitedMs,
      );
      _set(list);
      return;
    }
    list.insert(
      0,
      WebHistoryEntry(url: url, title: title ?? '', visitedMs: now),
    );
    if (list.length > maxEntries) list.length = maxEntries;
    _set(list);
  }

  /// A late `document.title` arrival re-labels the row for [url] without
  /// creating a second visit.
  void retitle(String url, String title) {
    if (title.trim().isEmpty) return;
    final List<WebHistoryEntry> list = List<WebHistoryEntry>.of(entries.value);
    final int index =
        list.indexWhere((WebHistoryEntry e) => WebAddress.samePage(e.url, url));
    if (index < 0 || list[index].title == title) return;
    if (list[index].title.isNotEmpty) return; // the page spoke once already
    final WebHistoryEntry old = list[index];
    list[index] = WebHistoryEntry(
      url: old.url,
      title: title,
      visitedMs: old.visitedMs,
    );
    _set(list);
  }

  /// Suggestion rows for the address bar: freshest hit per page, rows
  /// matching [query] in title or URL, case-insensitive containment.
  List<WebSuggestion> suggest(String query, {int limit = 4}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const <WebSuggestion>[];
    final List<WebSuggestion> out = <WebSuggestion>[];
    final Set<String> seen = <String>{};
    for (final WebHistoryEntry e in entries.value) {
      if (out.length >= limit) break;
      final bool hit = e.url.toLowerCase().contains(q) ||
          e.displayTitle.toLowerCase().contains(q);
      if (!hit) continue;
      if (!seen.add(WebAddress.canonical(e.url))) continue;
      out.add(WebSuggestion(
        kind: WebSuggestionKind.history,
        text: e.displayTitle,
        url: e.url,
      ));
    }
    return out;
  }

  /// "Browsing history" — the store empties instantly (no confirm dialog;
  /// browser data has no undo path, matching Edge/Chrome's clear tool).
  void clear() {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (entries.value.isEmpty) return;
    _set(const <WebHistoryEntry>[]);
  }

  static bool _isWebPage(String url) =>
      url.startsWith('http://') || url.startsWith('https://');
}
