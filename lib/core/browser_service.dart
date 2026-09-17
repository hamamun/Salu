import 'dart:async';

import 'package:flutter/foundation.dart';

import 'player_service.dart';
import 'web/web_data_control.dart';
import 'web/web_favourites_service.dart';
import 'web/web_history_service.dart';
import 'web/web_popup_service.dart';
import 'window_state_service.dart';

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
/// The service holds NO tab state — tabs live and die inside
/// `BrowserScreen`'s tree, so leaving for Player mode tears the whole
/// surface down: every `WebviewController` is destroyed and each engine's
/// session cache is cleared before disposal (web.md · key function 8).
/// Coming back to Web mode starts clean.
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
