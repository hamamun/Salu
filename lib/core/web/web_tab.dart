import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

import 'web_address.dart';
import 'web_data_control.dart';
import 'web_history_service.dart';
import 'web_popup_service.dart';

/// One pop-up the page asked for that SALU held back — the capture shim
/// reported it, the policy refused it. The address bar's badge counts
/// these; the blocked list offers each one back with an "Open".
@immutable
class BlockedPopup {
  const BlockedPopup({required this.url, required this.at});

  final String url;
  final DateTime at;
}

/// The lifecycle of one WebView2 view behind a browser tab (web.md ·
/// "WebView2 wrapper").
///
/// A tab is LAZY: it holds no controller until it is first activated with
/// something to show ([navigate] or a re-show of a loaded page), which is
/// what keeps RAM in check while the hub keeps ten tabs alive. While a
/// tab loses the stage — a tab switch, or the whole browser going behind
/// the player on a mode switch (web.md · mode keep-alive) — its engine is
/// suspended rather than destroyed: the page keeps its place, the memory
/// gives it up.
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

  /// Pop-ups this tab's page tried to open that SALU held back (the shim
  /// reports, the policy refuses) — the address bar's badge counts this
  /// list. Cleared by the next navigation: a new page starts unaccused.
  final ValueNotifier<List<BlockedPopup>> blocked =
      ValueNotifier<List<BlockedPopup>>(const <BlockedPopup>[]);

  /// Fires when the page asked for a pop-up the policy ALLOWS — the
  /// browser screen opens it as a new foreground tab (Chrome parity). Set
  /// by the screen at tab birth; null anywhere else.
  void Function(String url)? onPopupAllowed;

  /// Page zoom, 1.0 = 100% — per tab, applied through the engine's own
  /// zoom factor the moment it changes (the ⋮ menu's − / % / +).
  final ValueNotifier<double> zoom = ValueNotifier<double>(1.0);

  /// Desktop mode — when true the tab identifies as Edge-on-Windows no
  /// matter what the runtime reports, for sites that serve WebView2 a
  /// broken mobile page. Takes a reload to re-dress the page.
  final ValueNotifier<bool> desktopMode = ValueNotifier<bool>(false);

  /// The runtime's own User-Agent, caught from a live document the first
  /// time one answers — what Desktop-off restores.
  String? _nativeUserAgent;

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
    if (blocked.value.isNotEmpty) blocked.value = const <BlockedPopup>[];
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

  /// The engine's own Back — also leaves the start page (Home on top of a
  /// loaded page must be escapable the browser way).
  Future<void> goBack() async {
    startMode.value = false;
    if (blocked.value.isNotEmpty) blocked.value = const <BlockedPopup>[];
    final WebviewController? c = _controller;
    if (c == null) return;
    try {
      await c.goBack();
    } catch (_) {}
  }

  Future<void> goForward() async {
    startMode.value = false;
    if (blocked.value.isNotEmpty) blocked.value = const <BlockedPopup>[];
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

  /// The browser Home button navigates the active website to its own root
  /// page — for example, a YouTube video becomes `youtube.com/` — while
  /// staying in the same tab. A fresh tab has no website home, so it keeps
  /// SALU's Flutter start page instead.
  Future<void> goHome() async {
    if (_disposed) return;
    final String? target =
        url.value == null ? null : WebAddress.homeUrl(url.value!);
    if (target == null) {
      showStartPage();
      return;
    }
    await navigate(target);
  }

  /// Shows SALU's own start page for a fresh tab or an empty browser state.
  void showStartPage() {
    startMode.value = true;
    if (blocked.value.isNotEmpty) blocked.value = const <BlockedPopup>[];
  }

  // ── Zoom + Desktop mode (the ⋮ menu) ───────────────────────────────────

  /// Chrome's zoom ladder, low to high — zoomIn/zoomOut climb it.
  static const List<double> zoomSteps = <double>[
    0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9,
    1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0,
  ];

  /// What a Desktop-mode tab claims to be — Edge on Windows 10/11.
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';

  /// Sets this tab's zoom ([zoomSteps] bounds it) and applies it to the
  /// engine when one exists — a lazy tab simply remembers it for boot.
  Future<void> setZoom(double factor) async {
    final double next =
        factor.clamp(zoomSteps.first, zoomSteps.last).toDouble();
    zoom.value = next;
    final WebviewController? c = _controller;
    if (c == null) return;
    _fire(() => c.setZoomFactor(next));
  }

  Future<void> zoomIn() async {
    double next = zoomSteps.last;
    for (final double s in zoomSteps) {
      if (s > zoom.value + 0.001) {
        next = s;
        break;
      }
    }
    await setZoom(next);
  }

  Future<void> zoomOut() async {
    double next = zoomSteps.first;
    for (final double s in zoomSteps.reversed) {
      if (s < zoom.value - 0.001) {
        next = s;
        break;
      }
    }
    await setZoom(next);
  }

  Future<void> resetZoom() => setZoom(1.0);

  /// Flips Desktop mode for this tab. Turning it on re-dresses an
  /// already-loaded page with a reload; turning it off restores the
  /// runtime's own User-Agent (caught from the first live document — or
  /// an empty string, which hands the choice back to the engine).
  Future<void> setDesktopMode(bool on) async {
    desktopMode.value = on;
    final WebviewController? c = _controller;
    if (c == null) return; // applied at boot, when the engine arrives
    if (on && _nativeUserAgent == null && !startMode.value) {
      try {
        final Object? raw = await c
            .executeScript('navigator.userAgent')
            .timeout(const Duration(seconds: 2));
        if (raw is String && raw.trim().isNotEmpty) {
          _nativeUserAgent = raw;
        }
      } catch (_) {}
    }
    final String dress = on ? desktopUserAgent : (_nativeUserAgent ?? '');
    _fire(() => c.setUserAgent(dress));
    if (!startMode.value) unawaited(reload());
  }

  // ── Stage management (tab switching · mode switching) ─────────────────

  /// Whether the engine view is suspended right now — an off-stage tab,
  /// or a tab the mode switch parked (web.md · mode keep-alive). The page
  /// keeps its place; the renderer gives up its memory.
  bool _suspended = false;

  void activate() {
    final WebviewController? c = _controller;
    if (c == null) {
      // A virgin tab with a saved destination starts the moment it first
      // takes the stage — that is the lazy rule in one line.
      final String? pending = initialUrl;
      if (pending != null) unawaited(navigate(pending));
      return;
    }
    _suspended = false;
    _fire(() => c.resume());
  }

  void deactivate() {
    final WebviewController? c = _controller;
    if (c == null) return;
    _suspended = true;
    _fire(() => c.suspend());
  }

  /// The mode switch's leaving leg (web.md · mode keep-alive): the whole
  /// browser goes behind the player, so every RUNNING page parks instead
  /// of dying. The page's own media pauses first — a mode exit must never
  /// leave a site playing behind the player, the same courtesy SALU's
  /// player gets when Web mode opens — and only then the renderer
  /// suspends (the off-stage tabs' contract, extended to the stage
  /// itself). A tab that already gave up its renderer stays exactly as it
  /// is. Coming back to Web mode, [activate] on the active tab brings the
  /// page back — intact, and paused.
  Future<void> park() async {
    final WebviewController? c = _controller;
    if (c == null || _suspended) return;
    try {
      await c
          .executeScript(_pauseAllMediaJs)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    _suspended = true;
    _fire(() => c.suspend());
  }

  void _fire(Future<void> Function() action) {
    unawaited(() async {
      try {
        await action();
      } catch (_) {}
    }());
  }

  /// The pop-up capture shim — injected BEFORE the page's own scripts run
  /// (`addScriptToExecuteOnDocumentCreated`), which is what makes it a
  /// capture instead of a race:
  /// · `window.open` never reaches the engine: the URL is reported home
  ///   over `chrome.webview.postMessage` and a stub handle is returned, so
  ///   the "allow pop-ups to continue" gates adorning ad-boom streaming
  ///   sites see a valid window and load the video — while no ad ever
  ///   renders anywhere;
  /// · `target=_blank` clicks (which the `deny` engine policy would
  ///   silently swallow) are reported the same way, so an allowed site
  ///   still opens them — as SALU tabs, never OS windows.
  /// The engine policy stays `deny` regardless: nothing can ever escape
  /// SALU into a native window, shim or no shim.
  static const String _popupShimJs = r'''
if (!window.__saluPop) {
  window.__saluPop = true;
  var __saluReport = function (u) {
    try {
      if (window.chrome && chrome.webview && chrome.webview.postMessage) {
        chrome.webview.postMessage(JSON.stringify(
            { t: 'salu-popup', url: String(u == null ? '' : u) }));
      }
    } catch (e) {}
  };
  window.open = function (url) {
    __saluReport(url);
    return {
      closed: false,
      close: function () {}, focus: function () {}, blur: function () {}
    };
  };
  document.addEventListener('click', function (e) {
    try {
      var t = e.target;
      var a = (t && t.closest) ? t.closest('a[target="_blank"]') : null;
      if (a && a.href) {
        e.preventDefault();
        e.stopPropagation();
        __saluReport(a.href);
      }
    } catch (err) {}
  }, true);
}
''';

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

  /// The mode switch's courtesy (web.md · mode keep-alive): every media
  /// element in the page — and in every same-origin frame — pauses before
  /// the renderer suspends. A cross-origin frame refuses the reach-in and
  /// is skipped; its media stops with the freeze, like the page's own.
  static const String _pauseAllMediaJs = r'''
(function () {
  function pauseAll(doc) {
    if (!doc) return;
    var media = doc.querySelectorAll('video, audio');
    for (var i = 0; i < media.length; i++) {
      try { if (!media[i].paused) media[i].pause(); } catch (e) {}
    }
    var frames = doc.querySelectorAll('iframe');
    for (var j = 0; j < frames.length; j++) {
      try { pauseAll(frames[j].contentDocument); } catch (e) {}
    }
  }
  pauseAll(document);
})();
''';

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
      // Popups blocked by default (web.md · popups lock) — awaited, and
      // the capture shim with it, because both must be in force BEFORE
      // the first loadUrl lands: `addScriptToExecuteOnDocumentCreated`
      // only answers for documents created after it registers. The dark
      // base color can trail behind (first paint is cosmetic, not policy).
      try {
        await c
            .setPopupWindowPolicy(WebviewPopupWindowPolicy.deny)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await c
            .addScriptToExecuteOnDocumentCreated(_popupShimJs)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      // Page colours (web.md · Page colours): the engine's own
      // PreferredColorScheme — the profile control Edge's Appearance
      // setting drives. Set before the first load so the first paint
      // already answers `prefers-color-scheme` with the viewer's choice;
      // later changes reach this view live via WebDataControlService.
      try {
        await c
            .setPreferredColorScheme(WebDataControlService.pageSchemeValue(
                WebDataControlService.currentPageScheme))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      // A lazy tab may have chosen its zoom / dress before the engine
      // existed — apply the memory now that there is something to wear.
      if (zoom.value != 1.0) {
        try {
          await c.setZoomFactor(zoom.value).timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      if (desktopMode.value) {
        try {
          await c
              .setUserAgent(desktopUserAgent)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
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
      ..add(c.title.listen((String t) {
        final String trimmed = t.trim();
        title.value = trimmed.isEmpty ? null : trimmed;
        final String? u = url.value;
        if (u != null && trimmed.isNotEmpty) {
          WebHistoryService.instance.retitle(u, trimmed);
        }
      }))
      ..add(c.url.listen((String u) {
        url.value = u.isEmpty ? null : u;
      }))
      ..add(c.historyChanged.listen((HistoryChanged h) {
        canGoBack.value = h.canGoBack;
        canGoForward.value = h.canGoForward;
      }))
      ..add(c.loadingState.listen((LoadingState state) {
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
          // Catch the runtime's own User-Agent from the first live
          // document that answers — Desktop-off restores exactly this.
          if (_nativeUserAgent == null && !desktopMode.value) {
            _fire(() async {
              try {
                final Object? raw = await c
                    .executeScript('navigator.userAgent')
                    .timeout(const Duration(seconds: 2));
                if (raw is String && raw.trim().isNotEmpty) {
                  _nativeUserAgent = raw;
                }
              } catch (_) {}
            });
          }
        }
      }))
      ..add(c.onLoadError.listen((WebErrorStatus _) {
        failed.value = true;
        loading.value = false;
      }))
      ..add(c.containsFullScreenElementChanged.listen((bool v) {
        wantsFullscreen.value = v;
      }))
      // The plugin json-decodes every `webMessageReceived` itself and
      // answers `addError` for anything that is not JSON — the error leg
      // must be held, or a chatty page faults the zone.
      ..add(c.webMessage.listen(_onWebMessage, onError: (_) {}));
  }

  /// The shim's reports arrive here (`chrome.webview.postMessage` → the
  /// plugin's `webMessage` stream, which arrives already json-decoded —
  /// our reports land as a Map). Anything that is not one of ours —
  /// pages using the channel for their own ends — is ignored.
  void _onWebMessage(dynamic message) {
    try {
      final Object? decoded =
          message is String ? jsonDecode(message) : message;
      if (decoded is! Map) return;
      if (decoded['t'] != 'salu-popup') return;
      final Object? u = decoded['url'];
      if (u is! String || u.trim().isEmpty) return;
      _routePopup(u.trim());
    } catch (_) {
      // A garbled report is a dropped report — never a crash.
    }
  }

  void _routePopup(String url) {
    if (_disposed) return;
    final String lower = url.toLowerCase();
    // Script-born blanks are never destinations — OAuth's rare
    // `open('')`-then-write dance included: surfacing them would only
    // mint empty tabs, so they fall out of the count entirely.
    if (lower.startsWith('about:') || lower.startsWith('javascript:')) {
      return;
    }
    if (WebPopupService.instance.resolve(this.url.value)) {
      onPopupAllowed?.call(url);
      return;
    }
    noteBlocked(url);
  }

  /// Parks [url] in the held-back list (the badge's count): same-URL
  /// repeats within the minute collapse — ad networks retry in bursts,
  /// and the badge must count attempts, not spam — and the list keeps
  /// its newest twenty.
  void noteBlocked(String url) {
    if (_disposed) return;
    final DateTime now = DateTime.now();
    final List<BlockedPopup> list = List<BlockedPopup>.of(blocked.value);
    for (final BlockedPopup e in list) {
      if (e.url == url &&
          now.difference(e.at) < const Duration(minutes: 1)) {
        return;
      }
    }
    list.add(BlockedPopup(url: url, at: now));
    while (list.length > 20) {
      list.removeAt(0);
    }
    blocked.value = List<BlockedPopup>.unmodifiable(list);
  }

  /// Drops one held-back pop-up (its "Open" row was used).
  void dropBlocked(String url) {
    if (_disposed) return;
    final List<BlockedPopup> list = List<BlockedPopup>.of(blocked.value);
    list.removeWhere((BlockedPopup e) => e.url == url);
    blocked.value = List<BlockedPopup>.unmodifiable(list);
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
    onPopupAllowed = null;
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
    blocked.dispose();
    zoom.dispose();
    desktopMode.dispose();
  }
}
