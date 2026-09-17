import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

import 'web_address.dart';
import 'web_data_control.dart';
import 'web_history_service.dart';

/// The lifecycle of one WebView2 view behind a browser tab (web.md ·
/// "WebView2 wrapper").
///
/// A tab is LAZY: it holds no controller until it is first activated with
/// something to show ([navigate] or a re-show of a loaded page), which is
/// what keeps RAM in check while the hub keeps ten tabs alive. While a
/// tab loses the stage, its engine is [suspend]ed rather than destroyed —
/// the page keeps its place, the memory gives it up.
///
/// The notifiers below are the single source of truth for the whole browser
/// UI (tab chips, address bar, back/forward state, the fullscreen hand-off
/// to the page); the widget layer only mirrors them.
class WebTab {
  WebTab({this.initialUrl, this.initialTitle}) : id = ++_seq;

  static int _seq = 0;

  final int id;

  /// The URL a not-yet-started tab was created to load (consumed at the
  /// first [navigate]-style start; null for the start page).
  String? initialUrl;

  /// Optional label for a lazy tab with no page title yet (bookmark name).
  final String? initialTitle;

  final ValueNotifier<String?> url = ValueNotifier<String?>(null);
  final ValueNotifier<String?> title = ValueNotifier<String?>(null);
  final ValueNotifier<bool> canGoBack = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canGoForward = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// The last navigation failed (offline, DNS, the WebView2 runtime is
  /// missing) — the content area answers with its error state.
  final ValueNotifier<bool> failed = ValueNotifier<bool>(false);

  /// The page asked to own the screen (web.md · "Fullscreen is handed to
  /// the web page"). The browser screen mirrors the ACTIVE tab's value.
  final ValueNotifier<bool> wantsFullscreen = ValueNotifier<bool>(false);

  /// True while the tab shows SALU's own Flutter start page instead of a
  /// live view — a fresh tab, or "Home" on a loaded one. The engine behind
  /// a loaded tab keeps its history; navigating or going back leaves.
  final ValueNotifier<bool> startMode = ValueNotifier<bool>(true);

  WebviewController? _controller;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];
  Future<void>? _starting;
  String? _pendingTarget;
  bool _disposed = false;

  WebviewController? get controller => _controller;

  /// The engine view exists (its texture can be hosted by a `Webview`).
  bool get started => _controller != null;

  /// Nothing was ever loaded into this tab — the start page is its content.
  bool get isVirgin => !started && url.value == null;

  /// A tab that shows a page of its own (used by the star / clear /
  /// history affordances).
  bool get hasPage => url.value != null && !startMode.value;

  /// The label for the tab chip: page title, else the saved name, else
  /// the host, else "New tab".
  String get displayTitle {
    final String? t = title.value;
    if (t != null && t.trim().isNotEmpty) return t;
    final String? u = url.value;
    if (u != null) return WebAddress.labelFor(u);
    return initialTitle ?? 'New tab';
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  /// Loads [target] in this tab, creating the engine on first use.
  Future<void> navigate(String target) async {
    if (_disposed) return;
    startMode.value = false;
    failed.value = false;
    final String trimmed = target.trim();
    if (trimmed.isEmpty) return;
    _pendingTarget = trimmed;
    initialUrl = trimmed; // a tab that never started keeps its first load
    await _ensureStarted();
    final WebviewController? c = _controller;
    if (_disposed || c == null) return;
    if (!identical(_pendingTarget, trimmed)) return; // a newer request won
    _pendingTarget = null;
    try {
      await c.loadUrl(trimmed);
    } catch (_) {
      failed.value = true;
    }
  }

  /// The engine's own Back — also leaves the start page overlay (Home
  /// parked on top of a loaded page must be escapable the browser way).
  Future<void> goBack() async {
    startMode.value = false;
    final WebviewController? c = _controller;
    if (c == null) return;
    try {
      await c.goBack();
    } catch (_) {}
  }

  Future<void> goForward() async {
    startMode.value = false;
    final WebviewController? c = _controller;
    if (c == null) return;
    try {
      await c.goForward();
    } catch (_) {}
  }

  Future<void> reload() async {
    if (startMode.value) return; // nothing loaded — nothing to reload
    final WebviewController? c = _controller;
    if (c == null) return;
    failed.value = false;
    try {
      await c.reload();
    } catch (_) {}
  }

  /// The Home button (web.md · navigation buttons): the tab returns to
  /// SALU's start page. A loaded engine keeps its page — going back
  /// through [goBack] re-reveals it; the view itself is [suspend]ed.
  void showStartPage() => startMode.value = true;

  // ── Stage management (tab switching) ──────────────────────────────────

  void activate() {
    final WebviewController? c = _controller;
    if (c == null) {
      // A virgin tab with a saved destination starts the moment it first
      // takes the stage — that is the lazy rule in one line.
      final String? pending = initialUrl;
      if (pending != null) unawaited(navigate(pending));
      return;
    }
    _fire(() => c.resume());
  }

  void deactivate() {
    final WebviewController? c = _controller;
    if (c == null) return;
    _fire(() => c.suspend());
  }

  void _fire(Future<void> Function() action) {
    unawaited(() async {
      try {
        await action();
      } catch (_) {}
    }());
  }

  /// Page-side Escape listener that hands the fullscreen release back to
  /// the browser (web.md · "Fullscreen is handled by the web page").
  static const String _escapeListenerJs = '''
if (!window.__saluEsc) {
  window.__saluEsc = true;
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && document.fullscreenElement) {
      document.exitFullscreen();
    }
  }, true);
}''';

  // ── Engine lifecycle ───────────────────────────────────────────────────

  Future<void> _ensureStarted() {
    if (_controller != null) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      final WebviewController c = WebviewController();
      await c.initialize();
      if (_disposed) {
        // The browser was torn down while this view was booting — give the
        // half-born engine straight back.
        unawaited(c.dispose());
        return;
      }
      _controller = c;
      WebDataControlService.instance.attach(c);
      _wire(c);
      // Popups blocked by default (web.md · popups lock) and a dark base
      // color so first paint never flashes white over SALU's stage.
      _fire(() => c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny));
      _fire(() => c.setBackgroundColor(const Color(0xFF121212)));
    } catch (_) {
      // No runtime / plugin failure — the tab stays visibly unstarted and
      // the content area shows its error state.
      failed.value = true;
    } finally {
      _starting = null;
    }
  }

  void _wire(WebviewController c) {
    _subs
      ..add(c.title.stream.listen((String t) {
        final String trimmed = t.trim();
        title.value = trimmed.isEmpty ? null : trimmed;
        final String? u = url.value;
        if (u != null && trimmed.isNotEmpty) {
          WebHistoryService.instance.retitle(u, trimmed);
        }
      }))
      ..add(c.url.stream.listen((String u) {
        url.value = u.isEmpty ? null : u;
      }))
      ..add(c.historyChanged.stream.listen((HistoryChanged h) {
        canGoBack.value = h.canGoBack;
        canGoForward.value = h.canGoForward;
      }))
      ..add(c.loadingState.stream.listen((LoadingState state) {
        if (state == LoadingState.loading) {
          loading.value = true;
          failed.value = false;
          return;
        }
        loading.value = false;
        if (state == LoadingState.navigationCompleted) {
          final String? u = url.value;
          if (u != null) {
            WebHistoryService.instance.record(u, title: title.value);
          }
          // The page's own Esc should release a fullscreen video, the way
          // every browser does it — WebView2 hands keystrokes to the page
          // before Flutter ever sees them, so the listener lives inside the
          // document itself. The `__saluEsc` flag keeps it one listener a
          // page, however many navigations this tab survives.
          _fire(() => c.executeScript(_escapeListenerJs));
        }
      }))
      ..add(c.onLoadError.stream.listen((WebErrorStatus _) {
        failed.value = true;
        loading.value = false;
      }))
      ..add(c.containsFullScreenElementChanged.stream.listen((bool v) {
        wantsFullscreen.value = v;
      }));
  }

  // ── Teardown (web.md · key function 8: memory cleanup) ────────────────

  /// Destroys this tab's engine: session cache first (the "clear the
  /// session cache, flush RAM" contract), then the controller, then the
  /// notifiers.
  Future<void> destroy() async {
    if (_disposed) return;
    _disposed = true;
    for (final StreamSubscription<Object?> sub in _subs) {
      await sub.cancel().catchError((Object _) {});
    }
    _subs.clear();
    wantsFullscreen.value = false;
    final WebviewController? c = _controller;
    _controller = null;
    if (c != null) {
      WebDataControlService.instance.detach(c);
      try {
        await c.clearCache().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      try {
        await c.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    url.dispose();
    title.dispose();
    canGoBack.dispose();
    canGoForward.dispose();
    loading.dispose();
    failed.dispose();
    wantsFullscreen.dispose();
    startMode.dispose();
  }
}
