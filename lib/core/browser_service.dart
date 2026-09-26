import 'dart:async';

import 'package:flutter/foundation.dart';

import 'player_service.dart';
import 'web/web_data_control.dart';
import 'web/web_download_service.dart';
import 'web/web_favourites_service.dart';
import 'web/web_history_service.dart';
import 'web/web_popup_service.dart';
import 'window_state_service.dart';

/// One tab, as the phone's tab sheet sees it (remote.md §17.13.1): the
/// values the tab bar already paints, and nothing else. A **mirror**, never
/// the controllers — `WebTab` keeps owning its `WebviewController`.
@immutable
class WebTabMirror {
  const WebTabMirror({
    required this.title,
    required this.url,
    required this.active,
    required this.loading,
    required this.hasMedia,
  });

  final String? title;
  final String? url;
  final bool active;
  final bool loading;
  final bool hasMedia;
}

/// Which surface owns the window (web.md · the Player/Web toggle, LOCKED
/// to the top-left of the title strip).
enum SaluMode { player, web }

/// A request for the browser to show a URL — a saved bookmark opening the
/// browser (key function 3), or a bookmark clicked while it is already
/// open, which must spawn a NEW tab (key function 6).
@immutable
class WebOpenRequest {
  const WebOpenRequest({required this.url, this.title});

  final String url;

  /// A label for the tab while the page has none of its own (the saved
  /// bookmark's name).
  final String? title;
}

/// The web-mode half of SALU: the Player/Web mode itself, the browser's
/// open-request channel, and the small piece of window state the browser
/// borrows (page fullscreen, the strip's title text).
///
/// Tabs still live and die inside `BrowserScreen`'s tree — the service
/// holds at most a **mirror** (`webTabs`, a `List<WebTabMirror>`, plus the
/// scalars), never the `WebviewController`s (pc_part.md A4 · §17.13.1) —
/// and the screen installs one write-side handler so remote tab verbs and
/// on-screen actions share a single code path. That tree outlives the mode
/// switch (web.md · mode keep-alive): leaving for Player mode HIDES the
/// surface (Offstage) and parks its running pages — media paused, renderers
/// suspended — and coming back finds every page intact and paused. Only
/// an app close tears it down: every `WebviewController` destroyed and
/// each engine's session cache cleared before disposal (web.md · key
/// function 8).
class BrowserService {
  BrowserService._internal();

  /// The single mode holder for the whole app.
  static final BrowserService instance = BrowserService._internal();

  /// The live surface. `player` is the mpv canvas + OSC; `web` is the
  /// built-in browser.
  final ValueNotifier<SaluMode> mode =
      ValueNotifier<SaluMode>(SaluMode.player);

  /// Whether a web page currently owns the screen (web.md · "Fullscreen
  /// is handed to the web page" — SALU's chrome hides while it is true).
  final ValueNotifier<bool> pageFullscreen = ValueNotifier<bool>(false);

  /// The title strip's text while in web mode — the active tab's title.
  /// Player mode ignores it (the strip shows the media title).
  final ValueNotifier<String?> stripTitle = ValueNotifier<String?>(null);

  // Narrow, read-only mirror for SALU Remote. Tab ownership stays in
  // BrowserScreen; these values never contain page bodies or tab contents.
  final ValueNotifier<String?> webTitle = ValueNotifier<String?>(null);
  final ValueNotifier<String?> webUrl = ValueNotifier<String?>(null);
  final ValueNotifier<bool> webCanBack = ValueNotifier<bool>(false);
  final ValueNotifier<bool> webCanForward = ValueNotifier<bool>(false);
  final ValueNotifier<bool> webLoading = ValueNotifier<bool>(false);
  final ValueNotifier<int> webTabCount = ValueNotifier<int>(0);

  /// Whether the ACTIVE tab's page reports a reachable media element — set
  /// by the remote server's completion-based find poll (only while a device
  /// is connected in Web mode) and read by the browser screen for the mirror's
  /// per-tab `hasMedia`, and by the snapshot's `web.hasMedia`.
  final ValueNotifier<bool> webHasMedia = ValueNotifier<bool>(false);

  /// Identity of the browser surface a media script was aimed at. Bumped on
  /// navigation, tab switch/close, mode switch and shutdown so an in-flight
  /// script result can be ignored (pc_part.md Part F4).
  int mediaGeneration = 0;
  int? _mediaTabId;
  String? _mediaUrl;

  /// A live tab has registered its script seam. Polling skips otherwise.
  bool get hasLiveRemoteTab => _remoteScriptHandler != null;

  /// Records the surface a media read is about. No-ops when [tabId] and
  /// [url] are unchanged, so a title-only mirror refresh does not discard
  /// a read that is still about this page.
  void noteMediaSurface({int? tabId, String? url, bool live = true}) {
    if (!live) {
      _mediaTabId = null;
      _mediaUrl = null;
      mediaGeneration++;
      return;
    }
    if (tabId == _mediaTabId && url == _mediaUrl) return;
    _mediaTabId = tabId;
    _mediaUrl = url;
    mediaGeneration++;
  }

  void detachMediaSurface() => noteMediaSurface(live: false);

  /// The tab-strip mirror (pc_part.md A4 · remote.md §17.13.1) — the strip's
  /// own list, one entry per tab, refreshed only by the browser screen where
  /// it already calls [setStripTitle] / [setRemoteWebMirror], plus the tab
  /// add/remove/select paths. Nothing here rides the snapshot; the phone
  /// asks with `web_tabs_get`, capped and truncated at the handler edge.
  final ValueNotifier<List<WebTabMirror>> webTabs =
      ValueNotifier<List<WebTabMirror>>(const <WebTabMirror>[]);

  /// Writes come back through this one handler the browser screen installs,
  /// exactly like the nav handler for `browser_nav` (pc_part.md A4.3): each
  /// closure is the screen's OWN tab method, so a remote tab action and its
  /// on-screen twin can never disagree. [action] is one of [tabActions]; the
  /// returned code is how the strip answers:
  /// `'ok'`, `'tab_not_found'` (a stale index), or `'invalid'` (negative).
  Future<String?> Function(String action, int? index, String? url)?
      _tabHandler;

  /// One D-pad's focus answers run through this script seam — the active
  /// tab's own `executeScript`, registered by the browser screen alongside
  /// the media seam (pc_part.md A3). The focus ring is part of the package:
  /// the key script injects it page-side on every answer.
  Future<Object?> Function(String script)? _remoteFocusHandler;

  /// The one tab verb enum (pc_part.md A4.3): the screen's own select,
  /// close, new — its confirmation, its session bookkeeping, its last-tab
  /// rule — with no second code path.
  static const Set<String> tabActions = <String>{
    'activate',
    'close',
    'new',
  };

  Future<void> Function(String action)? _remoteNavHandler;
  Future<Object?> Function(String script)? _remoteScriptHandler;

  /// The one fullscreen seat's two host-side legs (pc_part.md C1 ·
  /// remote.md §17.14.1), installed by the browser screen for the ACTIVE
  /// tab alongside the nav/script handlers: a **real** click in the view
  /// (device pixels of the view → the composition controller's
  /// `SendMouseInput`, the same path a physical mouse takes — user
  /// activation included), and the screen's own page-fullscreen release.
  Future<bool> Function(double x, double y)? _remotePageClick;
  Future<void> Function()? _remotePageExitFullscreen;

  /// The `browser_nav` actions the screen answers. `home` (added 2026-09-24,
  /// remote.md §17.14.2) is the screen's own Home button: the loaded page
  /// goes to its site's front page, in the same tab.
  static const Set<String> navActions = <String>{
    'back',
    'forward',
    'reload',
    'stop',
    'home',
  };

  /// The download shelf's doorbell. The title bar's badge stands outside
  /// the browser's own tree — it has to, a download started here keeps
  /// running after the mode flips back — so the badge rings this and the
  /// mounted screen opens its shelf. Bumped, never reset: every ring is
  /// a new request, even two in a row.
  final ValueNotifier<int> downloadsRequest = ValueNotifier<int>(0);

  bool get isWeb => mode.value == SaluMode.web;

  /// Whether `BrowserScreen` is mounted and listening. The screen flips
  /// this in initState/dispose; it is the service's only knowledge of the
  /// widget tree, and it exists to route [openInBrowser].
  bool browserMounted = false;

  WebOpenRequest? _pending;

  final StreamController<WebOpenRequest> _requests =
      StreamController<WebOpenRequest>.broadcast();

  /// Open requests for the mounted browser screen.
  Stream<WebOpenRequest> get openRequests => _requests.stream;

  /// Consumes the request made while no browser screen existed yet (the
  /// very first bookmark click, which opened this mode).
  WebOpenRequest? takePendingRequest() {
    final WebOpenRequest? r = _pending;
    _pending = null;
    return r;
  }

  Future<void>? _warm;

  /// Purges any browser data the last session left to sweep, applies the
  /// "on player opening" auto-clear when due, and creates the shared
  /// WebView2 environment — all before the first view starts, in that
  /// order (see `WebDataControlService`). One-shot per process; entering
  /// web mode simply awaits it.
  Future<void> warmUp() => _warm ??= WebDataControlService.instance.prepare();

  /// Reads the browser's own stores (favourites + history + pop-up
  /// rules) alongside the other services, before the first frame.
  Future<void> load() async {
    await WebFavouritesService.instance.load();
    await WebHistoryService.instance.load();
    await WebPopupService.instance.load();
    await WebDownloadService.instance.load();
  }

  /// Applies [next] mode. Entering Web pauses the player — in this mode
  /// SALU draws no transport of its own (web.md · "No SALU media
  /// controls"), so audio must never run unattended behind a page. The
  /// queue parks exactly as the S key parks it; Play in Player mode picks
  /// it back up.
  Future<void> setMode(SaluMode next) async {
    if (mode.value == next) {
      if (next == SaluMode.player) await _releaseWebSurface();
      return;
    }
    mediaGeneration++;
    if (next == SaluMode.web) {
      // The mini bar is a 32-px strip with no room for a browser
      // (mini.md §8) — the full window comes back first.
      if (WindowStateService.instance.isMini) {
        try {
          await WindowStateService.instance.exitMini();
        } catch (_) {}
      }
      await warmUp();
      final PlayerService player = PlayerService.instance;
      if (player.isPlaying.value) {
        try {
          await player.pause();
        } catch (_) {
          // A player that will not pause must never block the browser.
        }
      }
      mode.value = SaluMode.web;
    } else {
      mode.value = SaluMode.player;
      await _releaseWebSurface();
    }
  }

  Future<void> toggleMode() =>
      setMode(isWeb ? SaluMode.player : SaluMode.web);

  /// Opens the download shelf. Web mode comes first — the shelf hangs
  /// off the browser's own chrome, so in Player mode the tap buys the
  /// mode switch (and the pause that contract carries) as well.
  Future<void> openDownloads() async {
    await setMode(SaluMode.web);
    downloadsRequest.value = downloadsRequest.value + 1;
  }

  /// Opens [url] in the browser: flips to Web mode and either delivers the
  /// request to the mounted screen (new tab per key function 6) or leaves
  /// it pending for the screen that is about to mount (key function 3).
  Future<void> openInBrowser(String url, {String? title}) async {
    await setMode(SaluMode.web);
    final WebOpenRequest request = WebOpenRequest(url: url, title: title);
    if (browserMounted) {
      _requests.add(request);
    } else {
      _pending = request;
    }
  }

  /// The browser screen reports the active tab's title here; the title
  /// strip shows it in web mode (and only in web mode).
  void setStripTitle(String? title) {
    if (stripTitle.value == title) return;
    stripTitle.value = title;
  }

  /// Installed by the active browser tab only. Remote commands therefore use
  /// the same WebTab object and controller as the on-screen buttons.
  void setRemoteHandlers({
    Future<void> Function(String action)? navigate,
    Future<Object?> Function(String script)? executeScript,
  }) {
    _remoteNavHandler = navigate;
    _remoteScriptHandler = executeScript;
  }

  Future<bool> remoteNavigate(String action) async {
    final Future<void> Function(String)? handler = _remoteNavHandler;
    if (handler == null) return false;
    if (!navActions.contains(action)) return false;
    await handler(action);
    return true;
  }

  Future<Object?> remoteExecuteScript(String script) async {
    final Future<Object?> Function(String)? handler = _remoteScriptHandler;
    if (handler == null) return null;
    return handler(script);
  }

  /// Installed by the browser screen with the active tab (pc_part.md C1):
  /// the real-click and page-fullscreen-release legs of `web_fullscreen`.
  void setRemotePageHandlers({
    Future<bool> Function(double x, double y)? click,
    Future<void> Function()? exitFullscreen,
  }) {
    _remotePageClick = click;
    _remotePageExitFullscreen = exitFullscreen;
  }

  /// A real click at [x]/[y] device pixels of the active view. False when
  /// no view can take it.
  Future<bool> remotePageClick(double x, double y) async {
    final Future<bool> Function(double, double)? handler = _remotePageClick;
    if (handler == null) return false;
    return handler(x, y);
  }

  /// The screen's own page-fullscreen release, or — when no screen is
  /// mounted — the hand-off's plain `false`, which never strands the window.
  Future<void> remotePageExitFullscreen() async {
    final Future<void> Function()? handler = _remotePageExitFullscreen;
    if (handler != null) return handler();
    await setWebFullscreen(false);
  }

  /// Installed by the browser screen alongside [setRemoteHandlers]: the one
  /// write path for `web_tab_activate` / `web_tab_close` / `web_tab_new`.
  void setTabHandler(
    Future<String?> Function(String action, int? index, String? url)? handler,
  ) {
    _tabHandler = handler;
  }

  /// Refreshes the tab-strip mirror from the screen's live strip. Pure data
  /// in, one direction only (pc_part.md A4.2): the screen owns the tabs; the
  /// service just mirrors the fields the phone's sheet wants to paint. The
  /// per-tab `hasMedia` the screen passes in is what its own media-detection
  /// already knows (the active page's real state, `false` for the rest).
  ValueNotifier<List<WebTabMirror>> mirrorTabs(
    List<WebTabMirror> tabs,
    int activeIndex,
  ) {
    final List<WebTabMirror> marked = <WebTabMirror>[
      for (int i = 0; i < tabs.length; i++)
        WebTabMirror(
          title: tabs[i].title,
          url: tabs[i].url,
          active: i == activeIndex,
          loading: tabs[i].loading,
          hasMedia: tabs[i].hasMedia,
        ),
    ];
    webTabs.value = marked;
    webTabCount.value = tabs.length;
    return webTabs;
  }

  /// The screen's own tab method, one hop away for the remote handler
  /// (pc_part.md A4.3). Returns `'ok'` / `'tab_not_found'` / `'invalid'`
  /// from the strip, or `null` when no handler is registered (the command
  /// layer answers `no_web_tabs`).
  Future<String?> remoteTabAction(
    String action,
    int? index, {
    String? url,
  }) async {
    final Future<String?> Function(String, int?, String?)? handler =
        _tabHandler;
    if (handler == null) return null;
    if (!tabActions.contains(action)) return null;
    return handler(action, index, url);
  }

  /// The D-pad's script seam, registered by the active tab (pc_part.md A3):
  /// the same `executeScript` as the media bridge, so `web_key`/`web_focus_get`
  /// reach the identical document.
  void setRemoteFocusHandler(
    Future<Object?> Function(String script)? handler,
  ) {
    _remoteFocusHandler = handler;
  }

  /// Runs a focus script on the active tab (the D-pad's own current page),
  /// or null when the tab is gone.
  Future<Object?> remoteFocusScript(String script) async {
    final Future<Object?> Function(String)? handler = _remoteFocusHandler;
    if (handler == null) return null;
    return handler(script);
  }

  void setRemoteWebMirror({
    required String? title,
    required String? url,
    required bool canBack,
    required bool canForward,
    required bool loading,
    required int tabCount,
    int? tabId,
  }) {
    final String? shown =
        url == null ? null : (url.length > 256 ? url.substring(0, 256) : url);
    if (loading && !webLoading.value) {
      // Navigation or reload started — a script already in flight is about
      // the previous document.
      mediaGeneration++;
    }
    webTitle.value = title;
    webUrl.value = shown;
    webCanBack.value = canBack;
    webCanForward.value = canForward;
    webLoading.value = loading;
    webTabCount.value = tabCount;
    if (tabId != null) {
      // Identity uses the full URL. The mirror above is capped at 256
      // characters, which must not hide a navigation past that prefix.
      noteMediaSurface(tabId: tabId, url: url);
    }
  }

  void clearRemoteWebMirror() {
    setRemoteHandlers();
    setRemotePageHandlers();
    setTabHandler(null);
    setRemoteFocusHandler(null);
    webTabs.value = const <WebTabMirror>[];
    detachMediaSurface();
    setRemoteWebMirror(
      title: null,
      url: null,
      canBack: false,
      canForward: false,
      loading: false,
      tabCount: 0,
    );
  }

  /// The page-fullscreen hand-off: notify + drive the real window. Only
  /// the ACTIVE tab's request may set it (the browser screen forwards on
  /// activation); `false` is always accepted so a teardown can never
  /// strand the window fullscreen.
  Future<void> setWebFullscreen(bool on) async {
    if (!on && !pageFullscreen.value) return;
    pageFullscreen.value = on;
    try {
      await WindowStateService.instance.setFullscreen(on);
    } catch (_) {
      // The notifier stays the browser's truth; the window simply did not
      // answer this time (its own listeners keep it synced).
    }
  }

  Future<void> _releaseWebSurface() async {
    if (pageFullscreen.value) {
      pageFullscreen.value = false;
      try {
        await WindowStateService.instance.setFullscreen(false);
      } catch (_) {}
    }
    stripTitle.value = null;
  }

  /// `main()`'s startup tail — never awaited, never blocks the first
  /// frame: a stale purge + the open-timed auto-clear run before any
  /// browsing starts.
  void scheduleStartupWarmUp() {
    unawaited(warmUp());
  }

  /// The close guard's browser step (web.md · "on player closing"): the
  /// due-date sweep schedules itself, and both browser stores flush to
  /// disk. Never throws; bounded by the guard's timeout. SALU's own data
  /// (resume memory, saved streams) is a different store entirely and is
  /// never touched here (web.md · Clear lock).
  Future<void> prepareClose() async {
    try {
      await WebDataControlService.instance.runAutoClearOnClose();
    } catch (_) {}
    try {
      await WebHistoryService.instance.flush();
    } catch (_) {}
    try {
      await WebFavouritesService.instance.flush();
    } catch (_) {}
    try {
      await WebPopupService.instance.flush();
    } catch (_) {}
    try {
      await WebDownloadService.instance.flush();
    } catch (_) {}
  }

  /// Whether the browser's toggles are worth showing at all — the WebView2
  /// engine only exists on Windows; every other platform keeps SALU in
  /// Player mode.
  static bool get browserSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Shared guard for every entry point: Web mode only where a browser
  /// exists. From Web mode the way out is always allowed.
  Future<void> toggleFromTitleBar() async {
    if (!isWeb && !browserSupported) return;
    await toggleMode();
  }
}
