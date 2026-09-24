import 'dart:async';

/// `web_key` and `web_focus_get` (pc_part.md A3 · remote.md §17.13.5):
/// the phone's Web-mode D-pad walks the page's own tab order — `a[href]`,
/// `button`, `input`, `select`, `textarea`, and `[tabindex]` that is not
/// `-1` — filtered to visible, enabled elements in document order. It never
/// invents a seat the site does not have; that is the honest limit, and
/// `focus.count === 0` is its honest answer.
///
/// The builders/parser are pure Dart (string-in, string-out) so
/// `test/remote_web_focus_test.dart` can assert them without a WebView; the
/// adapter ([RemoteWebFocusBridge]) injects them through the same
/// `WebTab.executeScript` seam as the web-media bridge (2 s timeout, errors
/// swallowed, top document only).
abstract final class RemoteWebFocusScripts {
  /// The focus order, in one expression (the same one every script shares).
  /// Top document only: an iframe's inner focusable lives in the iframe's
  /// own document and stays out of this list — the honest limit, unchanged.
  static const String orderBody = r'''
  function __saluFocusList() {
    var nodes = Array.prototype.slice.call(document.querySelectorAll(
      'a[href], button, input, select, textarea, [tabindex]'));
    return nodes.filter(function (el) {
      if (el.disabled) return false;
      var tab = el.getAttribute('tabindex');
      if (tab !== null && Number(tab) < 0) return false;
      try {
        var r = el.getBoundingClientRect();
        if (r.width <= 0 && r.height <= 0) return false;
        if (getComputedStyle(el).visibility === 'hidden') return false;
        if (getComputedStyle(el).display === 'none') return false;
      } catch (e) { return false; }
      return true;
    });
  }
''';

  /// One element described the phone's way: its own text as `label`, its
  /// element name as `tag`, its seat (0-based) and the size of the order as
  /// `index`/`count`, and whether it is an editable (caret-owning) field.
  static const String describe = r'''
  function __saluDescribe(el, list) {
    if (!el || !list) return {found: false, count: 0};
    var label = '';
    try {
      label = (el.innerText || '').replace(/\s+/g, ' ').trim();
      if (!label && typeof el.value === 'string') label = String(el.value);
      if (!label) label = el.getAttribute('aria-label') || '';
      if (!label) label = el.getAttribute('alt') || '';
      if (!label) label = el.getAttribute('title') || '';
    } catch (e) { label = ''; }
    if (label.length > 60) label = label.slice(0, 60);
    var tag = 'body';
    try { tag = (el.tagName || 'body').toLowerCase(); } catch (e) { tag = 'body'; }
    var editable = false;
    try {
      var name = (el.tagName || '').toLowerCase();
      editable = !!(name === 'input' || name === 'textarea');
      if (!editable) {
        var ce = false;
        try { ce = !!el.isContentEditable; } catch (e) { ce = false; }
        editable = ce;
      }
    } catch (e) { editable = false; }
    var index = -1;
    try {
      index = list.indexOf(el);
      if (index < 0) {
        for (var i = 0; i < list.length; i++) {
          if (list[i] === el) { index = i; break; }
        }
      }
    } catch (e) { index = -1; }
    return {found: true, count: list.length, label: label, tag: tag,
      index: index, editable: editable};
  }
''';

  /// The focus ring, drawn page-side by injecting one scoped style plus the
  /// element class (a 2 px accent outline with a soft glow) — part of the
  /// package per §17.13.5, not a follow-up. Scoped and idempotent: the style
  /// is injected once per document (`__saluRingCss`), the class is moved to
  /// the current element, and every other element is cleared. The SALU
  /// accent (`#4C9EEB`) matches `AppColors.accent` from `app_theme.dart`.
  static const String ring = r'''
  var __saluRing = function (el) {
    try {
      if (!document.getElementById('__saluRingCss')) {
        var st = document.createElement('style');
        st.id = '__saluRingCss';
        st.textContent = '.__saluRing{outline:2px solid #4C9EEB !important;'
          + 'outline-offset:2px;box-shadow:0 0 0 1px rgba(76,158,235,.35),'
          + '0 0 12px 2px rgba(76,158,235,.35) !important;'
          + 'border-radius:2px}';
        (document.head || document.documentElement).appendChild(st);
      }
      var prev = document.getElementsByClassName('__saluRing');
      for (var i = prev.length - 1; i >= 0; i--) {
        prev[i].classList.remove('__saluRing');
      }
      if (el) el.classList.add('__saluRing');
    } catch (e) {}
  };
''';

  /// `web_focus_get`: report the current seat without moving it. `body` is
  /// the current seat (the fallback per §17.13.5 — "no focus" honesty).
  static String read() => '(function () {\n'
      '  try {\n'
      '    $orderBody\n'
      '    $describe\n'
      '    var list = __saluFocusList();\n'
      '    var el = document.activeElement || null;\n'
      '    if (el && el.tagName === "BODY") el = null;\n'
      '    if (!el) {\n'
      '      // No focus yet, or the focus is the body: say so honestly, and\n'
      '      // seat 0 so the next ArrowDown lands on the first element.\n'
      '      var next = list.length ? list[0] : null;\n'
      '      if (next) return __saluDescribe(next, list);\n'
      '      return {found: true, count: 0, label: "", tag: "body", index: -1,\n'
      '        editable: false};\n'
      '    }\n'
      '    if (list.indexOf(el) < 0) {\n'
      '      // The seat is not in the filtered order (a div with a tabindex\n'
      '      // that does not match, or a non-focusable). Describe it anyway.\n'
      '      var d = __saluDescribe(el, list);\n'
      '      d.index = 0;\n'
      '      return d;\n'
      '    }\n'
      '    return __saluDescribe(el, list);\n'
      '  } catch (e) { return {found: false, count: 0}; }\n'
      '})()';

  /// `web_key` with [key] = `ArrowUp` / `ArrowDown` / `Enter` / `Escape`.
  /// The key travels into the script through the `__SALU_KEY__` placeholder,
  /// escaped for a double-quoted JS literal so a pathological key can never
  /// break out of the injected program (the handler only forwards a known
  /// set, but the seam itself stays safe and unit-testable).
  static String key(String key) {
    const String body = r'''
(function () {
  try {
    ORDER
    DESCRIBE
    RING
    var list = __saluFocusList();
    var el = document.activeElement || null;
    if (el && el.tagName === "BODY") el = null;
    var current = -1;
    if (el) current = list.indexOf(el);
    var isEditable = false;
    if (current >= 0) {
      var name = (el.tagName || "").toLowerCase();
      isEditable = name === "input" || name === "textarea" ||
        !!el.isContentEditable;
    }
    var k = "__SALU_KEY__";
    if (k === "ArrowDown" || k === "ArrowUp") {
      if (list.length === 0) {
        return {found: true, count: 0, label: "", tag: "body",
          index: -1, editable: false};
      }
      if (isEditable) {
        // The arrows belong to the caret while a text field is
        // focused: do not hop elements; report editable:true so the
        // phone's line changes to say so.
        return __saluDescribe(el, list);
      }
      var seat = current;
      if (seat < 0) {
        seat = k === "ArrowDown" ? 0 : list.length - 1;
      } else {
        seat = k === "ArrowDown" ? seat + 1 : seat - 1;
        if (seat >= list.length) seat = list.length - 1;
        if (seat < 0) seat = 0;
      }
      var next = list[seat];
      try { next.focus(); next.scrollIntoView({block:"center"}); }
      catch (e) {}
      __saluRing(next);
      return __saluDescribe(next, list);
    }
    if (k === "Enter") {
      if (el == null) {
        return {found: true, count: list.length, label: "", tag: "body",
          index: 0, editable: false};
      }
      if (isEditable) {
        // A text field submits its form (Enter's own meaning in a
        // field); otherwise Enter presses the element.
        var f = el.form || (el.closest ? el.closest("form") : null);
        if (f) {
          try { if (f.requestSubmit) f.requestSubmit(); }
          catch (e) { try { el.click(); } catch (e2) {} }
        } else {
          try { el.click(); } catch (e) {}
        }
      } else {
        try { el.click(); } catch (e) {}
      }
      return __saluDescribe(el, list);
    }
    if (k === "Escape") {
      // Element fullscreen, then page fullscreen, then the topmost
      // dialog — the order that can never strand the PC in a
      // full-screen advert.
      try {
        if (document.webkitExitFullscreen) document.webkitExitFullscreen();
      } catch (e) {}
      try {
        if (document.exitFullscreen && document.fullscreenElement) {
          document.exitFullscreen();
        }
      } catch (e) {}
      try {
        var dialogs = document.querySelectorAll("dialog[open]");
        if (dialogs.length) dialogs[dialogs.length - 1].close();
      } catch (e) {}
      return {found: true, count: list.length, label: "", tag: "escape",
        index: 0, editable: false};
    }
    return {found: true, count: list.length, label: "", tag: "body",
      index: 0, editable: false};
  } catch (e) { return {found: false, count: 0}; }
})()''';
    return body
        .replaceFirst('ORDER', orderBody)
        .replaceFirst('DESCRIBE', describe)
        .replaceFirst('RING', ring)
        .replaceFirst('__SALU_KEY__', _jsEscape(key));
  }

  /// Escapes [key] for a double-quoted JS string literal. The keys this
  /// builder accepts are a known set (no backslash, no quote), but the
  /// escape keeps the seam safe for any caller.
  static String _jsEscape(String key) => key.replaceAllMapped(
        RegExp(r'[\\"]'),
        (Match m) => '\\${m[0]}',
      );
}

/// One focus answer, in the phone's shape (`remote_apk_ui.md` §6.0): the
/// element's own text truncated to 60 characters, its element name, its
/// seat in the order, the size of the order, and whether the seat is an
/// editable (caret-owning) field. `tag:'body'` is the "nothing focused
/// yet / nothing to focus" answer; `found:false` means the page answered
/// with no focus document at all (a broken injection).
class RemoteWebFocusResult {
  const RemoteWebFocusResult({
    required this.found,
    this.label = '',
    this.tag = 'body',
    this.index = -1,
    this.count = 0,
    this.editable = false,
  });

  /// False only when the page answered with no focus document (a broken
  /// injection). `true` with `tag:'body'` is the honest "nothing focused"
  /// seat — the phone draws *Nothing focused yet*.
  final bool found;
  final String label;
  final String tag;
  final int index;
  final int count;
  final bool editable;

  /// The label the phone renders under the pad, e.g.
  /// `Subscribe · BUTTON · 4 of 120` — empty when there is nothing to name.
  String get line {
    if (!found || count <= 0 || index < 0) return '';
    final String tagged = tag.toUpperCase();
    return '$label · $tagged · ${index + 1} of $count';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'found': found,
        'label': label,
        'tag': tag,
        'index': index,
        'count': count,
        'editable': editable,
      };

  factory RemoteWebFocusResult.fromScript(Object? raw) {
    if (raw is! Map) return const RemoteWebFocusResult(found: false);
    final int size = raw['count'] is int ? raw['count'] as int : 0;
    return RemoteWebFocusResult(
      found: raw['found'] == true,
      label: raw['label'] is String ? raw['label'] as String : '',
      tag: raw['tag'] is String ? raw['tag'] as String : 'body',
      index: raw['index'] is int ? raw['index'] as int : -1,
      count: size < 0 ? 0 : size,
      editable: raw['editable'] == true,
    );
  }
}

/// Thin adapter around the `executeScript` callback owned by BrowserScreen —
/// the same seam as the web-media bridge, so a D-pad key can never create a
/// second navigation path or WebView.
class RemoteWebFocusBridge {
  RemoteWebFocusBridge({this.executeScript});

  Future<Object?> Function(String script)? executeScript;

  /// The keys `web_key` answers (remote.md §17.4). Unknown keys are the
  /// handler's `invalid_arguments`, not a silent ack.
  static const Set<String> supportedKeys = <String>{
    'ArrowUp',
    'ArrowDown',
    'Enter',
    'Escape',
  };

  Future<RemoteWebFocusResult> get() => _run(RemoteWebFocusScripts.read());

  /// Runs one `web_key` script and returns the *focus payload* the ack
  /// carries (the handler never needs the bare true/false — the phone's
  /// card is the description, not a boolean).
  Future<RemoteWebFocusResult> key(String key) =>
      _run(RemoteWebFocusScripts.key(key));

  Future<RemoteWebFocusResult> _run(String script) async {
    final Future<Object?> Function(String)? run = executeScript;
    if (run == null) return const RemoteWebFocusResult(found: false);
    try {
      final Object? result =
          await run(script).timeout(const Duration(seconds: 2));
      return RemoteWebFocusResult.fromScript(result);
    } catch (_) {
      return const RemoteWebFocusResult(found: false);
    }
  }
}
