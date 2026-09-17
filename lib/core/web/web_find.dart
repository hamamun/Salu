import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Find-in-page for the built-in browser (the ⋮ menu's "Find in page"):
/// WebView2 exposes no Find API to this plugin, so SALU highlights with
/// its own script — wrap every match, mark the current one, scroll it
/// into view — and Dart only keeps {query, total, index}.
///
/// Pure functions + one script template, so the parsing and the query
/// escaping are unit-testable (`test/web_find_test.dart`).
class WebFind {
  WebFind._();

  /// The script never wraps more than this many matches — a 50 000-hit
  /// page must highlight, not hang.
  static const int maxMatches = 500;

  /// Builds the find script for [query] with the [index]-th match current
  /// (1-based; past either end it clamps). The query travels inside a
  /// JSON string literal, so quotes, backslashes and newlines can never
  /// break out of it.
  static String buildScript(String query, int index) {
    final String q = jsonEncode(query);
    final int want = index < 1 ? 1 : index;
    return '''
(function () {
  if (!document.body) return { total: 0, index: 0 };
  var CLS = '__saluFind', CUR = '__saluCur';
  if (!document.getElementById('__saluFindCss')) {
    var st = document.createElement('style');
    st.id = '__saluFindCss';
    st.textContent = '.__saluFind{background:rgba(76,158,235,.38);'
      + 'border-radius:2px}'
      + '.__saluCur{background:#4C9EEB !important;color:#fff !important}';
    (document.head || document.documentElement).appendChild(st);
  }
  var prev = document.querySelectorAll('.' + CLS);
  for (var i = 0; i < prev.length; i++) {
    var s = prev[i], p = s.parentNode;
    if (p) {
      p.replaceChild(document.createTextNode(s.textContent), s);
      p.normalize();
    }
  }
  var q = $q;
  if (!q) return { total: 0, index: 0 };
  var ql = q.toLowerCase(), found = [];
  var skip = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1,
    INPUT: 1, SELECT: 1, BUTTON: 1 };
  var walker = document.createTreeWalker(
      document.body, NodeFilter.SHOW_TEXT, null);
  var nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (var n = 0; n < nodes.length && found.length < $maxMatches; n++) {
    var node = nodes[n];
    if (!node.parentNode || skip[node.parentNode.tagName]) continue;
    var text = node.nodeValue, tl = text.toLowerCase();
    var at = 0, k, frag = null;
    while ((k = tl.indexOf(ql, at)) >= 0 &&
        found.length < $maxMatches) {
      if (!frag) frag = document.createDocumentFragment();
      frag.appendChild(document.createTextNode(text.slice(at, k)));
      var mark = document.createElement('span');
      mark.className = CLS;
      mark.textContent = text.substr(k, q.length);
      frag.appendChild(mark);
      found.push(mark);
      at = k + q.length;
    }
    if (frag) {
      frag.appendChild(document.createTextNode(text.slice(at)));
      node.parentNode.replaceChild(frag, node);
    }
  }
  var total = found.length;
  if (total === 0) return { total: 0, index: 0 };
  var want = $want;
  if (want > total) want = total;
  var cur = found[want - 1];
  cur.classList.add(CUR);
  try { cur.scrollIntoView({ block: 'center' }); } catch (e) {}
  return { total: total, index: want };
})()''';
  }

  /// Lifts every highlight (and the style tag) back out of the page.
  static const String clearScript = '''
(function () {
  var prev = document.querySelectorAll('.__saluFind');
  for (var i = 0; i < prev.length; i++) {
    var s = prev[i], p = s.parentNode;
    if (p) {
      p.replaceChild(document.createTextNode(s.textContent), s);
      p.normalize();
    }
  }
  var css = document.getElementById('__saluFindCss');
  if (css && css.parentNode) css.parentNode.removeChild(css);
  return { total: 0, index: 0 };
})()''';
}

/// One find answer: how many matches the page holds, and which one is
/// current (1-based; 0/0 = nothing found — or nothing asked yet).
@immutable
class WebFindResult {
  const WebFindResult({required this.total, required this.index});

  final int total;
  final int index;

  static const WebFindResult none =
      WebFindResult(total: 0, index: 0);

  /// Parses the script's return value (`executeScript` json-decodes it
  /// into a Map). Anything unexpected is 0/0 — never a crash.
  static WebFindResult parse(Object? raw) {
    if (raw is Map) {
      final Object? t = raw['total'];
      final Object? i = raw['index'];
      if (t is int && i is int && t >= 0) {
        // `clamp` answers `num` even for ints — the `.toInt()` is load-
        // bearing, not decoration.
        return WebFindResult(total: t, index: i.clamp(0, t).toInt());
      }
    }
    return none;
  }
}
