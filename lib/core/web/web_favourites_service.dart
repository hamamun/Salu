import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_address.dart';
import 'web_suggestions.dart';

/// One saved page — the 15-slot Web Bookmark store (web.md · key
/// function 9, saved instantly with `shared_preferences` like every other
/// SALU list).
@immutable
class WebFavourite {
  const WebFavourite({
    required this.name,
    required this.url,
    this.folder = '',
  });

  final String name;
  final String url;

  /// Folder label for the favourites hub's grouping; `''` = unsorted
  /// (shown under the flat top of the list).
  final String folder;

  WebFavourite copyWith({String? name, String? url, String? folder}) {
    return WebFavourite(
      name: name ?? this.name,
      url: url ?? this.url,
      folder: folder ?? this.folder,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'url': url,
        if (folder.isNotEmpty) 'folder': folder,
      };

  static WebFavourite? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final Object? name = raw['name'];
    final Object? folder = raw['folder'];
    return WebFavourite(
      name: (name is String && name.trim().isNotEmpty)
          ? name.trim()
          : WebAddress.labelFor(url),
      url: url,
      folder: folder is String ? folder.trim() : '',
    );
  }
}

/// The browser's favourites — up to [maxEntries], persisted instantly as
/// one JSON list. Feeds three UIs: the star in the URL bar (two-state
/// save/edit, web.md · favourite star lock), the favourites hub on the
/// tab bar (grouping, search, edit, delete), and the address bar's
/// merged suggestion list (third source).
class WebFavouritesService {
  WebFavouritesService._internal();

  static final WebFavouritesService instance =
      WebFavouritesService._internal();

  static const int maxEntries = 15;
  static const String _prefsKey = 'web_favourites';

  /// The live list, in user order (newest at the bottom of "unsorted").
  final ValueNotifier<List<WebFavourite>> favourites =
      ValueNotifier<List<WebFavourite>>(const <WebFavourite>[]);

  bool get isFull => favourites.value.length >= maxEntries;

  bool _loaded = false;
  Future<void> _lastWrite = Future<void>.value();

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
      favourites.value = decoded
          .map((Object? e) => WebFavourite.fromJson(
              e is Map ? e.cast<String, Object?>() : e))
          .whereType<WebFavourite>()
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      // Corrupt prefs — start clean, silently.
      favourites.value = const <WebFavourite>[];
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(favourites.value
            .map((WebFavourite e) => e.toJson())
            .toList(growable: false)),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }

  void _set(List<WebFavourite> next) {
    favourites.value = List<WebFavourite>.unmodifiable(next);
    _lastWrite = _persist();
  }

  /// Completes the pending write — the close guard's bookkeeping.
  Future<void> flush() => _lastWrite;

  /// Saves [url]. Returns false when the 15 slots are full; an already
  /// saved page (same canonical URL) is a no-op success.
  bool add({
    required String url,
    String? name,
    String folder = '',
  }) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final List<WebFavourite> list = List<WebFavourite>.of(favourites.value);
    if (list.any((WebFavourite e) => WebAddress.samePage(e.url, trimmed))) {
      return true;
    }
    if (list.length >= maxEntries) return false;
    final String finalName = (name == null || name.trim().isEmpty)
        ? WebAddress.labelFor(trimmed)
        : name.trim();
    list.add(WebFavourite(
      name: finalName,
      url: trimmed,
      folder: folder.trim(),
    ));
    _set(list);
    return true;
  }

  /// The saved entry for [url], if the page is bookmarked — what makes
  /// the URL bar's star light up (web.md: filled = saved).
  WebFavourite? findFor(String url) {
    for (final WebFavourite f in favourites.value) {
      if (WebAddress.samePage(f.url, url)) return f;
    }
    return null;
  }

  /// Removes the entry at [index] and returns it (for the hub's Undo).
  WebFavourite? removeAt(int index) {
    final List<WebFavourite> list = List<WebFavourite>.of(favourites.value);
    if (index < 0 || index >= list.length) return null;
    final WebFavourite removed = list.removeAt(index);
    _set(list);
    return removed;
  }

  /// Restores a previously removed entry (Undo).
  void insertAt(int index, WebFavourite entry) {
    final List<WebFavourite> list = List<WebFavourite>.of(favourites.value);
    if (list.length >= maxEntries) return;
    list.insert(index.clamp(0, list.length).toInt(), entry);
    _set(list);
  }

  /// In-place edit — the favourite panel's Rename / Change folder /
  /// re-point flows (web.md · favourite star lock).
  void update(
    int index, {
    String? name,
    String? url,
    String? folder,
  }) {
    final List<WebFavourite> list = List<WebFavourite>.of(favourites.value);
    if (index < 0 || index >= list.length) return;
    list[index] = list[index].copyWith(
      name: (name == null || name.trim().isEmpty) ? null : name.trim(),
      url: (url == null || url.trim().isEmpty) ? null : url.trim(),
      folder: folder,
    );
    _set(list);
  }

  /// Drag-reorder.
  void move(int from, int to) {
    final List<WebFavourite> list = List<WebFavourite>.of(favourites.value);
    if (from < 0 || from >= list.length) return;
    final WebFavourite item = list.removeAt(from);
    list.insert(to.clamp(0, list.length).toInt(), item);
    _set(list);
  }

  /// The folder labels in use, alphabetical — the hub's groups and the
  /// save panel's chips.
  List<String> get folders {
    final Set<String> seen = <String>{};
    for (final WebFavourite f in favourites.value) {
      if (f.folder.isNotEmpty) seen.add(f.folder);
    }
    final List<String> out = seen.toList();
    out.sort();
    return out;
  }

  /// Suggestion rows for the address bar: name or URL contains [query].
  List<WebSuggestion> suggest(String query, {int limit = 3}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const <WebSuggestion>[];
    final List<WebSuggestion> out = <WebSuggestion>[];
    for (final WebFavourite f in favourites.value) {
      if (out.length >= limit) break;
      if (f.url.toLowerCase().contains(q) || f.name.toLowerCase().contains(q)) {
        out.add(WebSuggestion(
          kind: WebSuggestionKind.favourite,
          text: f.name,
          url: f.url,
        ));
      }
    }
    return out;
  }
}
