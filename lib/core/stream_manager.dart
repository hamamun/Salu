import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved network stream (M3U / IPTV / direct HTTP URL).
class SavedStream {
  const SavedStream({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'name': name, 'url': url};

  static SavedStream? fromJson(Map<String, dynamic> json) {
    final Object? name = json['name'];
    final Object? url = json['url'];
    if (url is! String || url.isEmpty) return null;
    return SavedStream(
      name: (name is String && name.isNotEmpty) ? name : url,
      url: url,
    );
  }
}

/// A saved website bookmark for the built-in browser.
class SavedBookmark {
  const SavedBookmark({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'name': name, 'url': url};

  static SavedBookmark? fromJson(Map<String, dynamic> json) {
    final Object? name = json['name'];
    final Object? url = json['url'];
    if (url is! String || url.isEmpty) return null;
    return SavedBookmark(
      name: (name is String && name.isNotEmpty) ? name : url,
      url: url,
    );
  }
}

/// Persistent library of saved streams and bookmarks (Phase 6 · Step 2).
///
/// Hard limits per the SALU spec: **10** M3U streams, **15** bookmarks.
class StreamManager extends ChangeNotifier {
  StreamManager._();

  static final StreamManager instance = StreamManager._();

  static const int maxStreams = 10;
  static const int maxBookmarks = 15;

  static const String _kStreams = 'library.streams';
  static const String _kBookmarks = 'library.bookmarks';

  SharedPreferences? _store;

  final List<SavedStream> _streams = <SavedStream>[];
  final List<SavedBookmark> _bookmarks = <SavedBookmark>[];

  List<SavedStream> get streams => List<SavedStream>.unmodifiable(_streams);

  List<SavedBookmark> get bookmarks =>
      List<SavedBookmark>.unmodifiable(_bookmarks);

  bool get streamsFull => _streams.length >= maxStreams;

  bool get bookmarksFull => _bookmarks.length >= maxBookmarks;

  Future<void> load() async {
    try {
      final SharedPreferences store = await SharedPreferences.getInstance();
      _store = store;

      _streams
        ..clear()
        ..addAll(_decode(store.getString(_kStreams))
            .map(SavedStream.fromJson)
            .whereType<SavedStream>());
      _bookmarks
        ..clear()
        ..addAll(_decode(store.getString(_kBookmarks))
            .map(SavedBookmark.fromJson)
            .whereType<SavedBookmark>());
    } catch (error) {
      debugPrint('[SALU] library load failed: $error');
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  // ── Streams ────────────────────────────────────────────────────────────

  /// Saves a stream. Returns `null` on success or an error message
  /// (duplicate URL / limit reached / invalid URL).
  String? addStream(String name, String url) {
    final String cleanUrl = url.trim();
    if (!isValidUrl(cleanUrl)) return 'Enter a valid http(s) URL';
    if (_streams.any((SavedStream s) => s.url == cleanUrl)) {
      return 'That stream is already saved';
    }
    if (streamsFull) return 'Stream limit reached ($maxStreams)';
    final String cleanName = name.trim().isEmpty ? cleanUrl : name.trim();
    _streams.add(SavedStream(name: cleanName, url: cleanUrl));
    _saveStreams();
    notifyListeners();
    return null;
  }

  void removeStream(int index) {
    if (index < 0 || index >= _streams.length) return;
    _streams.removeAt(index);
    _saveStreams();
    notifyListeners();
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────

  String? addBookmark(String name, String url) {
    String cleanUrl = url.trim();
    if (cleanUrl.isNotEmpty && !cleanUrl.contains('://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    if (!isValidUrl(cleanUrl)) return 'Enter a valid http(s) URL';
    if (_bookmarks.any((SavedBookmark b) => b.url == cleanUrl)) {
      return 'That bookmark is already saved';
    }
    if (bookmarksFull) return 'Bookmark limit reached ($maxBookmarks)';
    final String cleanName = name.trim().isEmpty ? cleanUrl : name.trim();
    _bookmarks.add(SavedBookmark(name: cleanName, url: cleanUrl));
    _saveBookmarks();
    notifyListeners();
    return null;
  }

  void removeBookmark(int index) {
    if (index < 0 || index >= _bookmarks.length) return;
    _bookmarks.removeAt(index);
    _saveBookmarks();
    notifyListeners();
  }

  static bool isValidUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return <String>['http', 'https', 'rtmp', 'rtsp', 'udp']
        .contains(uri.scheme.toLowerCase());
  }

  void _saveStreams() {
    _store?.setString(
      _kStreams,
      jsonEncode(_streams.map((SavedStream s) => s.toJson()).toList()),
    );
  }

  void _saveBookmarks() {
    _store?.setString(
      _kBookmarks,
      jsonEncode(_bookmarks.map((SavedBookmark b) => b.toJson()).toList()),
    );
  }
}
