import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'web_address.dart';

/// What one suggestion row is — the dropdown merges all three sources into
/// one list (web.md · address bar lock (1)).
enum WebSuggestionKind { search, history, favourite }

/// One merged suggestion row.
@immutable
class WebSuggestion {
  const WebSuggestion({
    required this.kind,
    required this.text,
    required this.url,
  });

  /// Row label: the query text, the page title, or the bookmark name.
  final WebSuggestionKind kind;
  final String text;

  /// Where tapping the row goes — a Google results page for [search],
  /// the saved page otherwise.
  final String url;
}

/// Fetcher seam — the live Google client by default, a fake in tests.
typedef WebSuggestFetcher = Future<List<String>> Function(String query);

/// Google's public suggest endpoint (`web.md` · address bar lock (1)).
///
/// The request asks for the plain-JSON shape (`client=firefox`); every
/// failure mode — offline, timeout, malformed body — degrades to an empty
/// list, because the dropdown's other two sources are SALU's own data.
class WebSuggestClient {
  WebSuggestClient({WebSuggestFetcher? fetcher})
      : _fetcher = fetcher ?? _httpFetch;

  static const String endpoint =
      'https://suggestqueries.google.com/complete/search';

  /// A slow network must never hold the dropdown hostage.
  static const Duration timeout = Duration(milliseconds: 2500);

  final WebSuggestFetcher _fetcher;

  /// Suggestion texts for [query]; never throws.
  Future<List<String>> fetch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <String>[];
    try {
      return await _fetcher(q).timeout(timeout);
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<List<String>> _httpFetch(String query) async {
    final http.Response response =
        await http.get(suggestUri(query)).timeout(timeout);
    return parseSuggestBytes(response.bodyBytes);
  }

  /// The exact request URL — `client=firefox` returns raw JSON (the
  /// `chrome` client answers with a JSONP callback wrapper).
  @visibleForTesting
  static Uri suggestUri(String query) => Uri.parse(endpoint).replace(
        queryParameters: <String, String>{
          'client': 'firefox',
          'hl': 'en',
          'q': query.trim(),
        },
      );

  /// Parses the `["query",["s1","s2",…]]` shape. Anything unrecognised —
  /// a captcha page, a truncated body — yields no suggestions.
  static List<String> parseSuggestBody(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! List || decoded.length < 2) return const <String>[];
      final Object? list = decoded[1];
      if (list is! List) return const <String>[];
      return list
          .whereType<String>()
          .where((String s) => s.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// Byte-level variant: the endpoint sometimes forgets to declare its
  /// charset, so UTF-8 is tried first and Latin-1 is the fallback.
  static List<String> parseSuggestBytes(List<int> bytes) {
    try {
      return parseSuggestBody(utf8.decode(bytes));
    } catch (_) {
      try {
        return parseSuggestBody(latin1.decode(bytes));
      } catch (_) {
        return const <String>[];
      }
    }
  }
}

/// Merges the three sources into the dropdown's final list.
///
/// Order: the user's own data first (favourites, then history), Google
/// after — a saved page outranks a guessed query. Rows dedupe on their
/// destination (URL rows canonically, search rows by text).
List<WebSuggestion> mergeWebSuggestions(
  String query, {
  List<WebSuggestion> favourites = const <WebSuggestion>[],
  List<WebSuggestion> history = const <WebSuggestion>[],
  List<String> google = const <String>[],
  int limit = 9,
}) {
  final List<WebSuggestion> out = <WebSuggestion>[];
  final Set<String> seen = <String>{};
  // A history row for the very address the user typed is an echo, not a
  // suggestion — compared by page identity, not raw string.
  final String? typedUrl = WebAddress.urlFrom(query);

  void add(WebSuggestion suggestion) {
    if (out.length >= limit) return;
    final String key = suggestion.kind == WebSuggestionKind.search
        ? 'q:${suggestion.text.trim().toLowerCase()}'
        : 'u:${WebAddress.canonical(suggestion.url)}';
    if (!seen.add(key)) return;
    out.add(suggestion);
  }

  for (final WebSuggestion f in favourites) {
    add(f);
  }
  for (final WebSuggestion h in history) {
    if (typedUrl != null && WebAddress.samePage(h.url, typedUrl)) continue;
    add(h);
  }
  for (final String g in google) {
    add(WebSuggestion(
      kind: WebSuggestionKind.search,
      text: g,
      url: WebAddress.searchUrl(g),
    ));
  }
  return List<WebSuggestion>.unmodifiable(out);
}
