import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_find.dart';

/// Find-in-page (the ⋮ menu's "Find in page…"): the query must travel
/// inside a JSON literal it can never break out of, and any answer the
/// script gives parses — or collapses to 0/0, never a crash.

void main() {
  group('the script', () {
    test('carries the query as a JSON literal', () {
      const String query = 'episode 12';
      final String script = WebFind.buildScript(query, 1);
      expect(script, contains('var q = ${jsonEncode(query)};'));
      expect(script, contains('var want = 1;'));
    });

    test('quotes, backslashes and newlines cannot break out', () {
      const String query = 'a"b\\c\nd\u2028e';
      final String script = WebFind.buildScript(query, 3);
      // The literal the page sees is exactly the JSON encoding — the
      // script around it is untouched.
      expect(script, contains('var q = ${jsonEncode(query)};'));
      expect(script, contains('var want = 3;'));
      expect(jsonDecode(jsonEncode(query)), query);
    });

    test('wants below one clamp to the first match', () {
      expect(WebFind.buildScript('x', 0), contains('var want = 1;'));
      expect(WebFind.buildScript('x', -4), contains('var want = 1;'));
    });

    test('caps the match walk', () {
      expect(WebFind.buildScript('x', 1),
          contains('found.length < ${WebFind.maxMatches}'));
    });

    test('the clear script lifts marks and its own style', () {
      expect(WebFind.clearScript, contains('__saluFind'));
      expect(WebFind.clearScript, contains('__saluFindCss'));
    });
  });

  group('the answer', () {
    test('a well-formed answer parses', () {
      final WebFindResult r =
          WebFindResult.parse(<String, Object?>{'total': 12, 'index': 3});
      expect(r.total, 12);
      expect(r.index, 3);
    });

    test('anything unexpected is 0/0', () {
      expect(WebFindResult.parse(null), WebFindResult.none);
      expect(WebFindResult.parse('garbage'), WebFindResult.none);
      expect(WebFindResult.parse(<String, Object?>{}), WebFindResult.none);
      expect(
          WebFindResult.parse(
              <String, Object?>{'total': '12', 'index': 3}),
          WebFindResult.none);
      expect(
          WebFindResult.parse(
              <String, Object?>{'total': -2, 'index': 1}),
          WebFindResult.none);
    });

    test('the index clamps into its total', () {
      final WebFindResult r =
          WebFindResult.parse(<String, Object?>{'total': 4, 'index': 9});
      expect((r.total, r.index), (4, 4));
    });
  });
}
