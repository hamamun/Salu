import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Play-health of a saved URL, remembered from the last play attempt.
/// Drives the status dot in the Open-URL modal:
///   gray = never tried · green = last attempt played · red = it failed.
enum UrlHealth { unknown, alive, dead }

/// One saved stream URL.
///
/// There is no "hidden" flag: the row-hide (eye) action was removed by
/// owner decision — with at most seven entries, drag-reorder already
/// covers "push the one I rarely use to the bottom". Legacy `hidden`
/// keys left in `shared_preferences` are simply ignored on load.
@immutable
class SavedUrl {
  const SavedUrl({
    required this.name,
    required this.url,
    this.health = UrlHealth.unknown,
  });

  final String name;
  final String url;

  final UrlHealth health;

  SavedUrl copyWith({
    String? name,
    String? url,
    UrlHealth? health,
  }) {
    return SavedUrl(
      name: name ?? this.name,
      url: url ?? this.url,
      health: health ?? this.health,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'url': url,
        'health': health.name,
      };

  static SavedUrl? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final Object? name = raw['name'];
    final Object? health = raw['health'];
    return SavedUrl(
      name: (name is String && name.isNotEmpty) ? name : url,
      url: url,
      health: health is String
          ? (UrlHealth.values.asNameMap()[health] ?? UrlHealth.unknown)
          : UrlHealth.unknown,
    );
  }
}

/// SALU's saved stream URLs — at most [maxEntries], persisted instantly to
/// `shared_preferences` as one JSON list (follow.md: no databases).
///
/// The service is pure data: ordering and health flags. All visual rules
/// (hover actions, undo toast, dimming Save at 7/7) live in the UI.
class UrlLibraryService {
  UrlLibraryService._internal();

  static final UrlLibraryService instance = UrlLibraryService._internal();

  static const int maxEntries = 7;
  static const String _prefsKey = 'saved_stream_urls';

  /// The live list, in user order. UI listens and rebuilds.
  final ValueNotifier<List<SavedUrl>> entries =
      ValueNotifier<List<SavedUrl>>(const <SavedUrl>[]);

  bool get isFull => entries.value.length >= maxEntries;

  bool _loaded = false;

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
          .map((Object? e) =>
              SavedUrl.fromJson(e is Map ? e.cast<String, Object?>() : e))
          .whereType<SavedUrl>()
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      // Corrupt prefs — start clean, silently.
      entries.value = const <SavedUrl>[];
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(entries.value.map((SavedUrl e) => e.toJson()).toList()),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }

  void _set(List<SavedUrl> next) {
    entries.value = List<SavedUrl>.unmodifiable(next);
    _persist();
  }

  /// Adds a URL (deduplicates by URL). Returns false when full.
  bool add(String url, {String? name}) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    if (list.any((SavedUrl e) => e.url == trimmed)) return true;
    if (list.length >= maxEntries) return false;
    list.add(SavedUrl(
      name: (name == null || name.trim().isEmpty)
          ? _suggestName(trimmed)
          : name.trim(),
      url: trimmed,
    ));
    _set(list);
    return true;
  }

  /// Removes the entry at [index] and returns it (for the Undo toast).
  SavedUrl? removeAt(int index) {
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    if (index < 0 || index >= list.length) return null;
    final SavedUrl removed = list.removeAt(index);
    _set(list);
    return removed;
  }

  /// Restores a previously removed entry (Undo).
  void insertAt(int index, SavedUrl entry) {
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    if (list.length >= maxEntries) return;
    list.insert(index.clamp(0, list.length).toInt(), entry);
    _set(list);
  }

  /// In-place edit of name and/or URL.
  void update(int index, {String? name, String? url}) {
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    if (index < 0 || index >= list.length) return;
    final String? nextUrl =
        (url == null || url.trim().isEmpty) ? null : url.trim();
    list[index] = list[index].copyWith(
      name: (name == null || name.trim().isEmpty) ? null : name.trim(),
      url: nextUrl,
      // A changed address means its health is unknown again.
      health: nextUrl != null && nextUrl != list[index].url
          ? UrlHealth.unknown
          : null,
    );
    _set(list);
  }

  /// Drag-reorder.
  void move(int from, int to) {
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    if (from < 0 || from >= list.length) return;
    final SavedUrl item = list.removeAt(from);
    list.insert(to.clamp(0, list.length).toInt(), item);
    _set(list);
  }

  /// Records the outcome of a play attempt for [url] (if it is saved).
  void markHealth(String url, UrlHealth health) {
    final List<SavedUrl> list = List<SavedUrl>.of(entries.value);
    final int index = list.indexWhere((SavedUrl e) => e.url == url);
    if (index < 0) return;
    if (list[index].health == health) return;
    list[index] = list[index].copyWith(health: health);
    _set(list);
  }

  /// Whether [text] plausibly points at a playable network stream —
  /// used both for input validation and the clipboard auto-fill.
  static bool looksLikeUrl(String text) {
    final String t = text.trim();
    if (t.isEmpty || t.contains('\n') || t.length > 2048) return false;
    final Uri? uri = Uri.tryParse(t);
    if (uri == null) return false;
    const Set<String> schemes = <String>{
      'http', 'https', 'rtmp', 'rtsp', 'rtp', 'mms', 'udp', 'srt', 'ftp',
    };
    if (uri.hasScheme && schemes.contains(uri.scheme.toLowerCase())) {
      final String scheme = uri.scheme.toLowerCase();
      // Web schemes need a host; exotic stream schemes (udp://…) may not.
      if (scheme == 'http' || scheme == 'https' || scheme == 'ftp') {
        return uri.host.isNotEmpty;
      }
      return true;
    }
    // Scheme-less but stream-ish: "server/live/list.m3u8".
    final String lower = t.toLowerCase();
    return !t.contains(' ') &&
        (lower.endsWith('.m3u') ||
            lower.endsWith('.m3u8') ||
            lower.endsWith('.mpd'));
  }

  /// A short human name derived from the URL (host, or last path bit).
  static String _suggestName(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.pathSegments.isNotEmpty) {
      final String last = uri.pathSegments.last;
      if (last.isNotEmpty && last.length <= 40) {
        final int dot = last.lastIndexOf('.');
        final String stem = dot > 0 ? last.substring(0, dot) : last;
        if (stem.isNotEmpty) return stem;
      }
    }
    return uri.host.isNotEmpty ? uri.host : url;
  }
}
