import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_address.dart';
import 'package:salu/core/web/web_suggestions.dart';

/// The dropdown's merge rules (web.md · address bar): own data first,
/// Google after, deduped on destination, capped.

void main() {
  group('parseSuggestBody — Google\'s plain-JSON shape', () {
    test('the second array is the suggestion list', () {
      expect(WebSuggestClient.parseSuggestBody('["flux",["flux capacitor","flux net"]]'),
          <String>['flux capacitor', 'flux net']);
    });
    test('garbage answers with nothing', () {
      expect(WebSuggestClient.parseSuggestBody('not json'), isEmpty);
      expect(WebSuggestClient.parseSuggestBody('["only-one"]'), isEmpty);
      expect(WebSuggestClient.parseSuggestBody('{"a":1}'), isEmpty);
    });
    test('blank strings are dropped', () {
      expect(WebSuggestClient.parseSuggestBody('["q",["ok","   ",42]]'),
          <String>['ok']);
    });
    test('the request asks the firefox client for raw JSON', () {
      final Uri uri = WebSuggestClient.suggestUri('salu player');
      expect(uri.queryParameters['client'], 'firefox');
      expect(uri.queryParameters['q'], 'salu player');
    });
  });

  group('mergeWebSuggestions', () {
    final List<WebSuggestion> favs = <WebSuggestion>[
      WebSuggestion(
          kind: WebSuggestionKind.favourite,
          text: 'MDN',
          url: 'https://developer.mozilla.org/docs'),
    ];
    final List<WebSuggestion> hist = <WebSuggestion>[
      WebSuggestion(
          kind: WebSuggestionKind.history,
          text: 'Example',
          url: 'https://example.com/'),
      WebSuggestion(
          kind: WebSuggestionKind.history,
          text: 'Docs',
          url: 'https://developer.mozilla.org/docs/'), // == the favourite
    ];

    test('own data first, Google last', () {
      final List<WebSuggestion> merged = mergeWebSuggestions(
        'ex',
        favourites: favs,
        history: hist,
        google: <String>['example english', 'examples'],
      );
      expect(merged.map((WebSuggestion s) => s.kind).toList(),
          <WebSuggestionKind>[
            WebSuggestionKind.favourite,
            WebSuggestionKind.history,
            WebSuggestionKind.search,
            WebSuggestionKind.search,
          ]);
    });

    test('rows dedupe on destination, canonically', () {
      final List<WebSuggestion> merged = mergeWebSuggestions(
        'ex',
        favourites: favs,
        history: hist,
        google: const <String>[],
      );
      expect(merged.length, 2); // the /docs/ twin folded into the save
    });

    test('the exactly-typed URL is not offered back as history', () {
      final List<WebSuggestion> merged = mergeWebSuggestions(
        'https://example.com',
        favourites: const <WebSuggestion>[],
        history: hist,
        google: const <String>[],
      );
      expect(merged.where((WebSuggestion s) => s.url == 'https://example.com/'),
          isEmpty);
      expect(merged.length, 1); // 'Docs' still offered
    });

    test('search rows become Google URLs', () {
      final List<WebSuggestion> merged = mergeWebSuggestions(
        'kittens',
        google: const <String>['kittens videos'],
      );
      expect(merged.single.url, WebAddress.searchUrl('kittens videos'));
    });

    test('the list is capped', () {
      final List<WebSuggestion> merged = mergeWebSuggestions(
        'x',
        google: <String>[for (int i = 0; i < 30; i++) 'q$i'],
        limit: 9,
      );
      expect(merged.length, 9);
    });
  });
}
