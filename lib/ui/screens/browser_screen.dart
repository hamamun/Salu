import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../core/browser_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/settings_service.dart';
import '../../core/web/web_address.dart';
import '../../core/web/web_download_service.dart';
import '../../core/web/web_favourites_service.dart';
import '../../core/web/web_find.dart';
import '../../core/web/web_history_service.dart';
import '../../core/web/web_popup_service.dart';
import '../../core/web/web_suggestions.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import '../../ui/osd/osd_controller.dart';
import '../widgets/browser_address_bar.dart';
import '../widgets/browser_clear_dialog.dart';
import '../widgets/browser_downloads_panel.dart';
import '../widgets/browser_favourite_sheet.dart';
import '../widgets/browser_favourites_hub.dart';
import '../widgets/browser_find_bar.dart';
import '../widgets/browser_history_panel.dart';
import '../widgets/browser_menu.dart';
import '../widgets/browser_site_panel.dart';
import '../widgets/browser_tab_strip.dart';
import '../widgets/browser_views.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/web_marks.dart';

/// Chrome geometry shared with the widget files (one ruler, two users).
const double kWebStripHeight = 36;
const double kWebRowHeight = 44;

/// web.md · tabs are capped; ten is where the strip still breathes at a
/// 960-px window (the `+` simply goes quiet at the cap — felt, not told).
const int kWebMaxTabs = 10;

/// The built-in browser — the Web mode's whole surface below the title
/// strip (web.md). The tab strip, the address bar, the favourites
/// machinery, and the WebView2 view filling everything that is left.
///
/// [chromeVisible] false is the page-fullscreen hand-off: the web view
/// keeps the entire window and every SALU row hides with it.
///
/// Tabs live and die inside this widget — but the widget itself now
/// outlives the mode switch (web.md · mode keep-alive): leaving for
/// Player mode HIDES the surface (the home screen Offstages it), parking
/// every running page, and coming back finds every tab exactly where it
/// was, media paused like the player's. Only an app close tears it down:
/// controllers disposed, session caches cleared (web.md · key function 8).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    this.chromeVisible = true,
    this.onOpenSettings,
  });

  final bool chromeVisible;

  /// Opens SALU's Settings window (the ⋮ menu's "Settings" row) — owned
  /// by the home screen, which is where the window lives.
  final VoidCallback? onOpenSettings;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final BrowserService _service = BrowserService.instance;
  final WebFavouritesService _favourites = WebFavouritesService.instance;
  final WebSuggestClient _suggestClient = WebSuggestClient();

  final List<WebTab> _tabs = <WebTab>[];
  int _active = -1;

  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();

  List<WebSuggestion> _suggestions = const <WebSuggestion>[];
  bool _suggestionsShown = false;
  int _cursor = -1;
  Timer? _suggestTimer;
  int _suggestSeq = 0;
  bool _syncingAddress = false;

  bool _hubOpen = false;
  bool _sheetOpen = false;
  int? _sheetIndex;
  bool _siteOpen = false;
  bool _blockedOpen = false;
  bool _menuOpen = false;
  bool _historyOpen = false;

  /// The download shelf (the badge's answer). [_playInFlight] is the
  /// race guard on its Play mark: the mode switch and the engine load
  /// both await, and a second tap in that gap must never land the same
  /// file twice.
  bool _downloadsOpen = false;
  bool _playInFlight = false;

  /// Find-in-page (the ⋮ menu's "Find in page…"): the bar, the query, and
  /// the {total, index} count the script answers with. [_findSeq] drops
  /// late answers when keystrokes outrun the engine.
  bool _findOpen = false;
  final TextEditingController _findQuery = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  final ValueNotifier<int> _findTotal = ValueNotifier<int>(0);
  final ValueNotifier<int> _findIndex = ValueNotifier<int>(0);
  Timer? _findTimer;
  int _findSeq = 0;

  /// The star's two-state mirror (web.md · "the star knows").
  final ValueNotifier<bool> _saved = ValueNotifier<bool>(false);

  /// The badge's count — the active tab's held-back list, mirrored so the
  /// address bar never has to chase tab switches itself.
  final ValueNotifier<int> _blockedCount = ValueNotifier<int>(0);

  WebTab? get _tab =>
      _active >= 0 && _active < _tabs.length ? _tabs[_active] : null;

  bool get _chrome => widget.chromeVisible;

  @override
  void initState() {
    super.initState();
    _service.browserMounted = true;
    _addressFocus.addListener(_onAddressFocusChanged);
    _favourites.favourites.addListener(_updateStar);
    _openSub = _service.openRequests.listen(_onOpenRequest);
    _service.mode.addListener(_onModeChanged);
    // The title bar's badge stands outside this tree — it has to, a
    // download outlives Web mode — so it rings the service's doorbell.
    _service.downloadsRequest.addListener(_onDownloadsRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabs.isNotEmpty) return;
      final WebOpenRequest? pending = _service.takePendingRequest();
      if (pending != null) {
        _newTab(url: pending.url, title: pending.title);
      } else {
        _newTab(focusAddress: true);
      }
    });
  }

  late final StreamSubscription<WebOpenRequest> _openSub;

  @override
  void dispose() {
    _service.browserMounted = false;
    _favourites.favourites.removeListener(_updateStar);
    unawaited(_openSub.cancel());
    _service.mode.removeListener(_onModeChanged);
    _service.downloadsRequest.removeListener(_onDownloadsRequest);
    _suggestTimer?.cancel();
    _addressFocus.removeListener(_onAddressFocusChanged);
    _unbindActive();
    unawaited(_service.setWebFullscreen(false));
    _service.setStripTitle(null);
    for (final WebTab t in _tabs) {
      unawaited(t.destroy());
    }
    _tabs.clear();
    _saved.dispose();
    _blockedCount.dispose();
    _findTimer?.cancel();
    _findQuery.dispose();
    _findFocus.dispose();
    _findTotal.dispose();
    _findIndex.dispose();
    // The surface is gone — the visit-only pop-up memories go with it.
    WebPopupService.instance.endSession();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _onAddressFocusChanged() {
    if (!_addressFocus.hasFocus && _suggestionsShown) {
      setState(_hideSuggestions);
    }
  }

  // ── Player · Web (the mode swap, web.md · mode keep-alive) ────────────

  /// The mode flip no longer tears this surface down — the home screen
  /// keeps it mounted and just Offstages it. So the swap is a matter of
  /// PARKING, not closing: leaving, every running page pauses its own
  /// media and suspends its renderer; returning, the active tab takes the
  /// stage back and every page is intact, and paused — like the player.
  void _onModeChanged() {
    if (_service.isWeb) {
      _tab?.activate();
      return;
    }
    unawaited(_parkSurface());
  }

  /// The leaving leg, in the order the pages need it: the active tab's
  /// page may still own the screen (the fullscreen hand-off releases
  /// first — the mode swap itself already took the window back), then
  /// every running tab parks in turn. A tab that already gave up its
  /// renderer (an off-stage one) stays exactly as it is.
  Future<void> _parkSurface() async {
    final WebTab? tab = _tab;
    if (tab != null && tab.wantsFullscreen.value) {
      _releasePageFullscreen();
    }
    // The parks await between tabs — a teardown in that gap must not
    // clear the list out from under the iteration.
    for (final WebTab t in <WebTab>[..._tabs]) {
      if (!t.started) continue;
      await t.park();
    }
  }

  // ── Tabs ───────────────────────────────────────────────────────────────

  void _newTab({
    String? url,
    String? title,
    bool focusAddress = false,
  }) {
    final WebTab tab = WebTab(initialUrl: url, initialTitle: title);
    tab.onPopupAllowed = (String popupUrl) => _openPopupTab(tab, popupUrl);
    setState(() {
      _tabs.add(tab);
      _selectLocked(tab);
    });
    // A fresh tab always starts with an empty omnibox, even when the old
    // tab's address field already had focus (the active-tab sync deliberately
    // leaves user-entered text alone while that field is focused).
    if (url == null) _syncAddressTo('');
    tab.activate();
    if (focusAddress) _focusAddressBar();
  }

  /// Put the caret in the omnibox after a blank tab has been added. The
  /// address field is rebuilt as part of [_newTab]'s setState, so waiting for
  /// that frame makes the focus request reliable even when the new tab is
  /// created by the strip's `+` button.
  void _focusAddressBar() {
    if (!_chrome) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chrome) return;
      _addressFocus.requestFocus();
      _address.selection = TextSelection.collapsed(
        offset: _address.text.length,
      );
    });
  }

  void _select(WebTab tab) {
    if (identical(tab, _tab)) return;
    if (_findOpen) _dropFind();
    _tab?.deactivate();
    _unbindActive();
    setState(() {
      _menuOpen = false;
      _historyOpen = false;
      _selectLocked(tab);
    });
    tab.activate();
    // The fullscreen hand-off follows the stage: only the active tab may
    // own the screen (web.md · "Fullscreen is handled by the web page").
    unawaited(_service.setWebFullscreen(tab.wantsFullscreen.value));
  }

  void _selectLocked(WebTab tab) {
    _active = _tabs.indexOf(tab);
    _bindActive(tab);
    _onActiveChanged();
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final WebTab tab = _tabs.removeAt(index);
    final bool wasActive = index == _active;
    if (wasActive) _unbindActive();
    if (index < _active) _active -= 1;
    unawaited(tab.destroy());
    if (wasActive && _findOpen) {
      // The marks die with the engine — only the state needs dropping.
      _findTimer?.cancel();
      _findOpen = false;
      _findTotal.value = 0;
      _findIndex.value = 0;
    }
    setState(() {
      _hideSuggestions();
      _menuOpen = false;
      _historyOpen = false;
      if (_tabs.isEmpty) {
        // Last tab closed — Web mode STAYS (web.md lock): the strip keeps
        // its `+`, the content is the start page.
        _active = -1;
        _syncAddressTo('');
        _blockedCount.value = 0;
        unawaited(_service.setWebFullscreen(false));
        _service.setStripTitle(null);
        _updateStar();
      } else if (wasActive) {
        _selectLocked(_tabs[index.clamp(0, _tabs.length - 1).toInt()]);
        _tab?.activate();
      }
      // A tab before the stage died: the active tab is untouched, only its
      // index shifted — it keeps its bindings and its page.
    });
  }

  // ── Active-tab plumbing ────────────────────────────────────────────────

  final List<(ValueNotifier<Object?>, VoidCallback)> _bound =
      <(ValueNotifier<Object?>, VoidCallback)>[];

  void _bindActive(WebTab tab) {
    for (final ValueNotifier<Object?> n in <ValueNotifier<Object?>>[
      tab.url,
      tab.title,
      tab.startMode,
      tab.failed,
      tab.loading,
      tab.blocked,
    ]) {
      n.addListener(_onActiveChanged);
      _bound.add((n, _onActiveChanged));
    }
    tab.wantsFullscreen.addListener(_onFullscreenWanted);
    _bound.add((tab.wantsFullscreen, _onFullscreenWanted));
  }

  void _unbindActive() {
    for (final (ValueNotifier<Object?> n, VoidCallback cb) in _bound) {
      n.removeListener(cb);
    }
    _bound.clear();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    final WebTab? tab = _tab;
    if (tab == null) return;
    if (_findOpen && tab.loading.value) {
      // A navigation replaced the document mid-find — the marks died
      // with it, so the session ends silently (no script left to run).
      _findTimer?.cancel();
      _findOpen = false;
      _findTotal.value = 0;
      _findIndex.value = 0;
    }
    if (tab.loading.value && _suggestionsShown) _hideSuggestions();
    if (!_addressFocus.hasFocus) {
      final bool start = tab.startMode.value;
      _syncAddressTo(start ? '' : (tab.url.value ?? ''));
    }
    _updateStar();
    _blockedCount.value =
        tab.startMode.value ? 0 : tab.blocked.value.length;
    _service.setStripTitle(tab.displayTitle);
    setState(() {});
  }

  void _onFullscreenWanted() {
    final WebTab? tab = _tab;
    unawaited(_service.setWebFullscreen(tab?.wantsFullscreen.value ?? false));
  }

  void _syncAddressTo(String text) {
    if (_address.text == text) return;
    _syncingAddress = true;
    _address.text = text;
    _syncingAddress = false;
  }

  void _updateStar() {
    final WebTab? tab = _tab;
    final String? url = tab?.hasPage == true ? tab!.url.value : null;
    final bool now =
        url != null && _favourites.findFor(url) != null;
    if (_saved.value != now) _saved.value = now;
  }

  // ── Address bar / suggestions ──────────────────────────────────────────

  void _onQueryChanged(String text) {
    if (_syncingAddress) return;
    _suggestTimer?.cancel();
    final String q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _hideSuggestions();
      });
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(_runSuggestions(q));
    });
  }

  Future<void> _runSuggestions(String query) async {
    final int seq = ++_suggestSeq;
    final List<WebSuggestion> favs =
        _favourites.suggest(query, limit: 4);
    final List<WebSuggestion> hist =
        WebHistoryService.instance.suggest(query, limit: 4);
    final List<String> google = SettingsService.instance
            .webSearchSuggestions.value
        ? await _suggestClient.fetch(query)
        : const <String>[];
    if (!mounted || seq != _suggestSeq) return;
    // Only answer while the user is still talking to the bar.
    if (!_addressFocus.hasFocus || _address.text.trim() != query) return;
    setState(() {
      _suggestions = mergeWebSuggestions(
        query,
        favourites: favs,
        history: hist,
        google: google,
      );
      _cursor = -1;
      _suggestionsShown = _suggestions.isNotEmpty;
      // The dropdown owns the stage — every panel steps aside for it
      // (the one-popup world).
      _siteOpen = false;
      _blockedOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _dropFind();
    });
  }

  void _hideSuggestions() {
    _suggestTimer?.cancel();
    _suggestSeq++;
    _suggestionsShown = false;
    _cursor = -1;
  }

  void _submitAddress() {
    // Enter with a highlighted row picks it — the field consumes the key
    // before any wrapper can, so this is where that rule lives.
    if (_suggestionsShown && _cursor >= 0) {
      setState(() => _pickSuggestion(_suggestions[_cursor]));
      return;
    }
    final String text = _address.text.trim();
    _hideSuggestions();
    if (text.isEmpty) return;
    final String target = WebAddress.navigateTarget(text);
    final WebTab? tab = _tab;
    if (tab == null) {
      _newTab(url: target);
    } else {
      unawaited(tab.navigate(target));
    }
  }

  void _pickSuggestion(WebSuggestion item) {
    _hideSuggestions();
    if (item.kind == WebSuggestionKind.search) {
      // Search rows fill the bar (web.md · address bar lock (1)) — Enter
      // is still the sentence's period.
      _address.text = item.text;
      _addressFocus.requestFocus();
      return;
    }
    final WebTab? tab = _tab;
    if (tab == null) {
      _newTab(url: item.url);
    } else {
      unawaited(tab.navigate(item.url));
    }
  }

  KeyEventResult _onAddressKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (!_suggestionsShown || _suggestions.isEmpty) {
        return KeyEventResult.ignored;
      }
      final int n = _suggestions.length;
      setState(() {
        _cursor = key == LogicalKeyboardKey.arrowDown
            ? (_cursor + 1) % n
            : (n == 0 ? 0 : (_cursor - 1 + n) % n);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_suggestionsShown && _cursor >= 0) {
        // A highlighted row outranks the plain "go" — consume the key so
        // the field's onSubmitted can't double-fire.
        setState(() => _pickSuggestion(_suggestions[_cursor]));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // onSubmitted navigates the bar
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_suggestionsShown ||
          _hubOpen ||
          _sheetOpen ||
          _siteOpen ||
          _blockedOpen ||
          _menuOpen ||
          _historyOpen) {
        setState(() {
          _hideSuggestions();
          _hubOpen = false;
          _sheetOpen = false;
          _sheetIndex = null;
          _siteOpen = false;
          _blockedOpen = false;
          _menuOpen = false;
          _historyOpen = false;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // the window owns the next Esc
    }
    return KeyEventResult.ignored;
  }

  // ── Popups (hub · favourite sheet) ─────────────────────────────────────

  void _onOpenRequest(WebOpenRequest req) {
    if (_tabs.length >= kWebMaxTabs) {
      // Capped: the bookmark still opens — in the tab you were looking at.
      final WebTab? tab = _tab;
      if (tab != null) {
        unawaited(tab.navigate(req.url));
      }
      return;
    }
    _newTab(url: req.url, title: req.title);
  }

  void _openFavourite(WebFavourite f) {
    setState(() => _hubOpen = false);
    final WebTab? tab = _tab;
    if (tab == null) {
      _newTab(url: f.url, title: f.name);
    } else {
      unawaited(tab.navigate(f.url));
    }
  }

  void _editFavourite(int index) {
    setState(() {
      _hubOpen = false;
      _sheetOpen = true;
      _sheetIndex = index;
    });
  }

  void _removeFavourite(int index) {
    final WebFavourite? removed = _favourites.removeAt(index);
    if (removed == null) return;
    setState(() {
      if (_sheetIndex == index) {
        _sheetOpen = false;
        _sheetIndex = null;
      } else if (_sheetIndex != null && _sheetIndex! > index) {
        _sheetIndex = _sheetIndex! - 1;
      }
    });
    _updateStar();
    // Instant removal, five seconds of regret, no dialog (follow.md rule).
    OsdController.instance.show(OsdUndoCard(
      label: 'Removed “${removed.name}”',
      onUndo: () {
        _favourites.insertAt(index, removed);
        _updateStar();
      },
    ));
  }

  void _toggleFavouritePanel() {
    final WebTab? tab = _tab;
    if (tab?.hasPage != true) return; // no page, nothing to save
    final String url = tab!.url.value!;
    final WebFavourite? existing = _favourites.findFor(url);
    setState(() {
      _hubOpen = false;
      _sheetOpen = true;
      _sheetIndex = existing == null
          ? null
          : _favourites.favourites.value.indexOf(existing);
      _siteOpen = false;
      _blockedOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _dropFind();
    });
  }

  void _toggleSitePanel() {
    if (_tab?.hasPage != true) return; // no page, no site to name
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _blockedOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _dropFind();
      _siteOpen = !_siteOpen;
    });
  }

  void _toggleBlockedList() {
    final WebTab? tab = _tab;
    if (tab == null || tab.blocked.value.isEmpty) return;
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _siteOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _dropFind();
      _blockedOpen = !_blockedOpen;
    });
  }

  /// An allowed pop-up asked to exist — it gets a new foreground tab
  /// (Chrome parity). At the tab cap it parks in the held-back list
  /// instead: a pop-up must never take over the tab being looked at.
  void _openPopupTab(WebTab from, String url) {
    if (!mounted) return;
    if (_tabs.length >= kWebMaxTabs) {
      if (_tabs.contains(from)) from.noteBlocked(url);
      return;
    }
    _newTab(url: url);
  }

  /// One held-back row's "Open" — the pop-up becomes a real tab, and only
  /// then leaves the list.
  void _openBlockedUrl(String url) {
    final WebTab? tab = _tab;
    if (tab == null || _tabs.length >= kWebMaxTabs) return;
    tab.dropBlocked(url);
    setState(() => _blockedOpen = false);
    _newTab(url: url);
  }

  /// The site panel's Allow/Block rows — a permanent rule for this site.
  void _setSitePopups(bool allow) {
    final String? url = _tab?.url.value;
    if (url == null) return;
    WebPopupService.instance.setFor(url, allow);
    setState(() {}); // the panel reads the effective state at build
  }

  /// "Allow just for this visit" — no permanent rule for a disposable
  /// domain; the memory evaporates with the browsing session.
  void _visitAllowSite() {
    final String? url = _tab?.url.value;
    if (url == null) return;
    WebPopupService.instance.allowVisit(url);
    setState(() {});
  }

  // ── Menu · history · find (the ⋮ shelf) ────────────────────────────────

  void _toggleMenu() {
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _siteOpen = false;
      _blockedOpen = false;
      _historyOpen = false;
      _dropFind();
      _menuOpen = !_menuOpen;
    });
  }

  void _openHistory() {
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _siteOpen = false;
      _blockedOpen = false;
      _menuOpen = false;
      _dropFind();
      _historyOpen = true;
    });
  }

  void _openHistoryEntry(WebHistoryEntry entry) {
    setState(() => _historyOpen = false);
    final WebTab? tab = _tab;
    if (tab == null) {
      _newTab(url: entry.url);
    } else {
      unawaited(tab.navigate(entry.url));
    }
  }

  /// The ⋮ menu's "Open in Edge" — the escape door for pages that will
  /// never run inside SALU (bank logins, heavy portals): the URL rides
  /// the OS's `microsoft-edge:` protocol, quoted so cmd never reads
  /// its `&`s.
  Future<void> _openInEdge() async {
    final String? url = _tab?.url.value;
    setState(() => _menuOpen = false);
    if (url == null || url.isEmpty) return;
    try {
      await Process.start(
          'cmd', <String>['/c', 'start', '', '"microsoft-edge:$url"']);
    } catch (_) {}
  }

  // ── Downloads (the badge's answer) ─────────────────────────────────────

  /// The badge's tap, from either of its two homes: the shelf opens in
  /// place of whatever else was up (one popup at a time, follow.md §3),
  /// and tells the service it is being watched — finishes from here on
  /// are seen as they land, so the badge needs no reason to linger.
  void _toggleDownloads() {
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _siteOpen = false;
      _blockedOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _dropFind();
      _downloadsOpen = !_downloadsOpen;
    });
    WebDownloadService.instance.setShelfOpen(_downloadsOpen);
  }

  /// The title bar's badge rang the doorbell ([BrowserService
  /// .openDownloads], from Player mode): a ring is a request, not a
  /// flip, so an already-open shelf stays open.
  void _onDownloadsRequest() {
    if (!mounted || _downloadsOpen) return;
    _toggleDownloads();
  }

  /// The shelf's Play — the one thing a browser that is not also a
  /// player cannot offer: the file just downloaded IS media, and SALU
  /// plays it.
  ///
  /// The queue decides the shape (owner, 2026-09-19):
  ///   · a queue is already there → the file joins its end and Web mode
  ///     keeps the screen — you stay where you were;
  ///   · nothing queued and nothing playing → the file becomes the
  ///     queue, Player mode takes the window and playback starts.
  ///
  /// A channel list is the one populated queue a local file never joins
  /// (`PlayerService.appendToQueue` refuses it by design), so it takes
  /// the fresh-load branch — exactly what dropping the same file on the
  /// window has always done.
  Future<void> _playDownload(WebDownloadItem item) async {
    if (_playInFlight) return;
    final String path = item.path;
    if (path.isEmpty) return;
    _playInFlight = true;
    try {
      final QueueService queue = QueueService.instance;
      if (queue.hasQueue && !queue.isChannelList) {
        setState(() => _downloadsOpen = false);
        WebDownloadService.instance.setShelfOpen(false);
        await PlayerService.instance.appendToQueue(<String>[path]);
        return;
      }
      // Nothing to join: the file becomes the queue, and the window
      // follows it. The mode flip first — it parks the pages, and the
      // engine load must not race a browser still holding the screen.
      setState(() => _downloadsOpen = false);
      WebDownloadService.instance.setShelfOpen(false);
      await _service.setMode(SaluMode.player);
      await PlayerService.instance.openPaths(<String>[path]);
    } catch (_) {
      // A file that will not open leaves the row where it is.
    } finally {
      _playInFlight = false;
    }
  }

  /// "Show in folder" — Explorer opens the Downloads folder with this
  /// very file selected, not merely somewhere near it.
  Future<void> _revealDownload(WebDownloadItem item) async {
    setState(() => _downloadsOpen = false);
    WebDownloadService.instance.setShelfOpen(false);
    await WebDownloadService.instance.reveal(item.path);
  }

  /// The shelf's footer: the Downloads folder itself — the one answer
  /// that still works with an empty log.
  Future<void> _openDownloadsFolder() async {
    setState(() => _downloadsOpen = false);
    WebDownloadService.instance.setShelfOpen(false);
    await WebDownloadService.instance.openFolder(null);
  }

  void _openFind() {
    if (_tab?.hasPage != true) return;
    setState(() {
      _hubOpen = false;
      _sheetOpen = false;
      _sheetIndex = null;
      _hideSuggestions();
      _siteOpen = false;
      _blockedOpen = false;
      _menuOpen = false;
      _historyOpen = false;
      _findOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_findOpen) return;
      _findFocus.requestFocus();
      _findQuery.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findQuery.text.length,
      );
    });
    if (_findQuery.text.trim().isNotEmpty) {
      unawaited(_runFind(_findQuery.text, 1));
    }
  }

  void _onFindQueryChanged(String text) {
    _findTimer?.cancel();
    if (text.trim().isEmpty) {
      _findTotal.value = 0;
      _findIndex.value = 0;
      _clearFindMarks(_tab); // highlights lift live as the query empties
      return;
    }
    _findTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runFind(text, 1)),
    );
  }

  /// Runs one find pass: highlight every match, make [want] current.
  /// Late answers (keystrokes outran the engine, tab moved on) fall out
  /// by sequence — the bar never shows another query's count.
  Future<void> _runFind(String query, int want) async {
    final int seq = ++_findSeq;
    final WebTab? tab = _tab;
    final WebviewController? c = tab?.controller;
    if (tab == null || c == null || !_findOpen) return;
    final String q = query.trim();
    if (q.isEmpty) return;
    try {
      final Object? raw = await c
          .executeScript(WebFind.buildScript(q, want))
          .timeout(const Duration(seconds: 3));
      if (!mounted || seq != _findSeq || !_findOpen || !identical(_tab, tab)) {
        return;
      }
      final WebFindResult r = WebFindResult.parse(raw);
      _findTotal.value = r.total;
      _findIndex.value = r.index;
    } catch (_) {}
  }

  void _findNext() {
    final String q = _findQuery.text.trim();
    if (q.isEmpty) return;
    final int t = _findTotal.value;
    if (t == 0) {
      unawaited(_runFind(q, 1));
      return;
    }
    unawaited(_runFind(q, _findIndex.value >= t ? 1 : _findIndex.value + 1));
  }

  void _findPrev() {
    final String q = _findQuery.text.trim();
    if (q.isEmpty) return;
    final int t = _findTotal.value;
    if (t == 0) {
      unawaited(_runFind(q, 1));
      return;
    }
    unawaited(_runFind(q, _findIndex.value <= 1 ? t : _findIndex.value - 1));
  }

  void _closeFind() {
    _findTimer?.cancel();
    _clearFindMarks(_tab);
    setState(() {
      _findOpen = false;
      _findTotal.value = 0;
      _findIndex.value = 0;
    });
  }

  /// Drops the find session (marks lifted, counts zeroed) — the caller
  /// owns the setState. Every menu opener calls it: the one-popup world
  /// has no room for a second focused face.
  void _dropFind() {
    if (!_findOpen) return;
    _findTimer?.cancel();
    _findOpen = false;
    _findTotal.value = 0;
    _findIndex.value = 0;
    _clearFindMarks(_tab);
  }

  void _clearFindMarks(WebTab? tab) {
    final WebviewController? c = tab?.controller;
    if (c == null) return;
    unawaited(() async {
      try {
        await c
            .executeScript(WebFind.clearScript)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }());
  }

  /// Browser keyboard (Chrome's shelf): new / close / reload tab, jump to
  /// the bar, find, zoom. It answers while Flutter holds the focus — a
  /// page with native focus eats keystrokes before Flutter ever sees
  /// them (the plugin exposes no accelerator hook), so these are the
  /// chrome's keys, not the page's.
  KeyEventResult _onBrowserKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyT) {
      if (_tabs.length < kWebMaxTabs) {
        _closePopups();
        _newTab(focusAddress: true);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyW) {
      if (_active >= 0) {
        _closePopups();
        _closeTab(_active);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(_tab?.reload() ?? Future<void>.value());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _addressFocus.requestFocus();
      _address.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _address.text.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _openFind();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      unawaited(_tab?.zoomIn() ?? Future<void>.value());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      unawaited(_tab?.zoomOut() ?? Future<void>.value());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      unawaited(_tab?.resetZoom() ?? Future<void>.value());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _saveFavourite(String name, String folder) {
    final WebTab? tab = _tab;
    final String? url = tab?.hasPage == true ? tab!.url.value : null;
    if (url == null) return;
    _favourites.add(url: url, name: name.isEmpty ? null : name,
        folder: folder);
    setState(() {
      _sheetOpen = false;
      _sheetIndex = null;
    });
    _updateStar();
  }

  void _updateFavourite(int index, String name, String folder) {
    _favourites.update(index, name: name, folder: folder);
    setState(() {
      _sheetOpen = false;
      _sheetIndex = null;
    });
    _updateStar();
  }

  void _closePopups() {
    if (_hubOpen ||
        _sheetOpen ||
        _suggestionsShown ||
        _siteOpen ||
        _blockedOpen ||
        _menuOpen ||
        _historyOpen ||
        _downloadsOpen ||
        _findOpen) {
      setState(() {
        _hubOpen = false;
        _sheetOpen = false;
        _sheetIndex = null;
        _siteOpen = false;
        _blockedOpen = false;
        _menuOpen = false;
        _historyOpen = false;
        _downloadsOpen = false;
        _dropFind();
        _hideSuggestions();
      });
      WebDownloadService.instance.setShelfOpen(false);
    }
  }

  /// Navigate the active website to its own home page without leaving Web
  /// mode. For example, YouTube's `/watch?...` page becomes YouTube's root
  /// page in the same tab. A fresh tab has no website home, so it remains on
  /// SALU Web's own start page.
  void _goHome() {
    final WebTab? tab = _tab;
    if (tab?.hasPage == true) {
      unawaited(tab!.goHome());
    } else if (tab != null) {
      tab.showStartPage();
      _syncAddressTo('');
    }
    _closePopups();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool supported = BrowserService.browserSupported;
    final WebTab? tab = _tab;
    final Widget content = !supported || tab == null
        ? const WebStartPage()
        : ValueListenableBuilder<bool>(
            valueListenable: tab.startMode,
            builder: (BuildContext context, bool start, Widget? _) {
              // Home is a browser page, not a player-mode switch. Select the
              // Flutter start page itself instead of stacking it over a live
              // native WebView, so the WebView can never cover the home page.
              if (start) {
                return const ColoredBox(
                  color: AppColors.videoBackdrop,
                  child: WebStartPage(),
                );
              }
              return WebTabView(tab: tab);
            },
          );

    return Focus(
      // While the page owns the screen, this focus owns its Esc:
      // the first Esc RELEASES the hand-off (browser convention) —
      // the window only goes back to SALU's strip on the second, and only
      // because the page itself let go. While the chrome shows, the same
      // root answers the browser keyboard (Ctrl+T/W/R/L/F, zoom).
      autofocus: !_chrome,
      canRequestFocus: !_chrome,
      onKeyEvent: _chrome
          ? _onBrowserKey
          : (FocusNode n, KeyEvent e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.escape) {
                _releasePageFullscreen();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      child: DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.videoBackdrop),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints cons) {
          final double width = cons.maxWidth;
          final double menuWidth =
              (width - 184 - 52).clamp(240.0, 720.0).toDouble();
          return Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  if (_chrome) ...<Widget>[
                    BrowserTabStrip(
                      tabs: _tabs,
                      activeIndex: _active,
                      maxTabs: kWebMaxTabs,
                      onSelect: (int i) => _select(_tabs[i]),
                      onClose: _closeTab,
                      onNewTab: () => _newTab(focusAddress: true),
                      hub: _HubButton(
                        open: _hubOpen,
                        onTap: () => setState(() {
                          _sheetOpen = false;
                          _sheetIndex = null;
                          _hideSuggestions();
                          _siteOpen = false;
                          _blockedOpen = false;
                          _menuOpen = false;
                          _historyOpen = false;
                          _dropFind();
                          _hubOpen = !_hubOpen;
                        }),
                      ),
                    ),
                    BrowserAddressBar(
                      tab: tab,
                      address: _address,
                      addressFocus: _addressFocus,
                      suggestionsShown: _suggestionsShown,
                      saved: _saved,
                      blockedCount: _blockedCount,
                      onSubmit: _submitAddress,
                      onQueryChanged: _onQueryChanged,
                      onCancel: _closePopups,
                      onFavourite: _toggleFavouritePanel,
                      onSiteInfo: _toggleSitePanel,
                      onBlockedTap: _toggleBlockedList,
                      onMenu: _toggleMenu,
                      downloadsOpen: _downloadsOpen,
                      onDownloadsTap: _toggleDownloads,
                      onBack: () => tab?.goBack(),
                      onForward: () => tab?.goForward(),
                      onReload: () => tab?.reload(),
                      onStop: () => tab?.controller?.stop(),
                      onHome: _goHome,
                      onKeyEvent: _onAddressKey,
                    ),
                  ],
                  Expanded(child: content),
                ],
              ),
              // One translucent sheet over everything for outside-taps —
              // menus die with the next click anywhere, like Chrome's.
              // Find is not a menu (Chrome keeps it while the page is
              // clicked), so it stays out of the sheet.
              if (_chrome &&
                  (_hubOpen ||
                      _sheetOpen ||
                      _suggestionsShown ||
                      _siteOpen ||
                      _blockedOpen ||
                      _menuOpen ||
                      _historyOpen ||
                      _downloadsOpen))
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _closePopups(),
                  ),
                ),
              if (_chrome && _suggestionsShown && _suggestions.isNotEmpty)
                Positioned(
                  left: 184,
                  top: kWebStripHeight + kWebRowHeight - 4,
                  width: menuWidth,
                  child: _PopGrow(
                    child: WebSuggestionMenu(
                      items: _suggestions,
                      cursorIndex: _cursor,
                      onPick: (WebSuggestion s) {
                        _pickSuggestion(s);
                        setState(() {});
                      },
                      onHover: (int i) {
                        if (i != _cursor) setState(() => _cursor = i);
                      },
                    ),
                  ),
                ),
              if (_chrome && _hubOpen)
                Positioned(
                  left: 8,
                  top: kWebStripHeight + 4,
                  child: _PopGrow(
                    child: BrowserFavouritesHub(
                      onOpen: _openFavourite,
                      onEdit: _editFavourite,
                      onRemove: _removeFavourite,
                      onClose: () => setState(() => _hubOpen = false),
                    ),
                  ),
                ),
              if (_chrome && _sheetOpen)
                Positioned(
                  left: 158,
                  top: kWebStripHeight + kWebRowHeight + 2,
                  child: _PopGrow(
                    child: Focus(
                      onKeyEvent: (FocusNode n, KeyEvent e) {
                        if (e is KeyDownEvent &&
                            e.logicalKey == LogicalKeyboardKey.escape) {
                          setState(() {
                            _sheetOpen = false;
                            _sheetIndex = null;
                          });
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: _buildSheet(),
                    ),
                  ),
                ),
              if (_chrome && _siteOpen && _tab?.hasPage == true)
                Positioned(
                  left: 150,
                  top: kWebStripHeight + kWebRowHeight + 2,
                  child: _PopGrow(
                    child: BrowserSitePanel(
                      pageUrl: _tab!.url.value!,
                      secure: _tab!.url.value!
                          .toLowerCase()
                          .startsWith('https://'),
                      popupsAllowed: WebPopupService.instance
                          .resolve(_tab!.url.value),
                      blockedCount: _tab!.blocked.value.length,
                      onPopupsChanged: _setSitePopups,
                      onVisitAllow: _visitAllowSite,
                      onShowBlocked: () => setState(() {
                        _siteOpen = false;
                        _blockedOpen = true;
                      }),
                      onClose: () =>
                          setState(() => _siteOpen = false),
                    ),
                  ),
                ),
              if (_chrome &&
                  _blockedOpen &&
                  _tab != null &&
                  _tab!.blocked.value.isNotEmpty)
                Positioned(
                  right: 48,
                  top: kWebStripHeight + kWebRowHeight - 4,
                  width: 380,
                  child: _PopGrow(
                    child: BlockedPopupList(
                      items: _tab!.blocked.value,
                      host: WebAddress.hostOf(_tab!.url.value ?? ''),
                      canOpen: _tabs.length < kWebMaxTabs,
                      onOpen: _openBlockedUrl,
                      onAllowSite: () {
                        final String? url = _tab?.url.value;
                        if (url != null) {
                          WebPopupService.instance.setFor(url, true);
                        }
                        setState(() => _blockedOpen = false);
                      },
                      onClose: () =>
                          setState(() => _blockedOpen = false),
                    ),
                  ),
                ),
              if (_chrome && _downloadsOpen)
                Positioned(
                  right: 48,
                  top: kWebStripHeight + kWebRowHeight - 4,
                  child: _PopGrow(
                    child: BrowserDownloadsPanel(
                      onPlay: (WebDownloadItem i) =>
                          unawaited(_playDownload(i)),
                      onReveal: (WebDownloadItem i) =>
                          unawaited(_revealDownload(i)),
                      onRemove: WebDownloadService.instance.remove,
                      onOpenFolder: () =>
                          unawaited(_openDownloadsFolder()),
                      onClearFinished:
                          WebDownloadService.instance.clearFinished,
                      onClose: () {
                        setState(() => _downloadsOpen = false);
                        WebDownloadService.instance.setShelfOpen(false);
                      },
                    ),
                  ),
                ),
              if (_chrome && _menuOpen)
                Positioned(
                  right: 8,
                  top: kWebStripHeight + kWebRowHeight + 2,
                  child: _PopGrow(
                    child: BrowserMenu(
                      tab: _tab,
                      onNewTab: () {
                        setState(() => _menuOpen = false);
                        if (_tabs.length < kWebMaxTabs) {
                          _newTab(focusAddress: true);
                        }
                      },
                      onFind: _openFind,
                      onHistory: _openHistory,
                      onClearData: () {
                        setState(() => _menuOpen = false);
                        showWebClearDialog(context);
                      },
                      onOpenInEdge: () => unawaited(_openInEdge()),
                      onSettings: () {
                        setState(() => _menuOpen = false);
                        widget.onOpenSettings?.call();
                      },
                      onDownloads: _toggleDownloads,
                      onClose: () =>
                          setState(() => _menuOpen = false),
                    ),
                  ),
                ),
              if (_chrome && _historyOpen)
                Positioned(
                  right: 8,
                  top: kWebStripHeight + kWebRowHeight + 2,
                  child: _PopGrow(
                    child: BrowserHistoryPanel(
                      onOpen: _openHistoryEntry,
                      onRemove: (int i) =>
                          WebHistoryService.instance.removeAt(i),
                      onClearAll: () =>
                          WebHistoryService.instance.clear(),
                      onClose: () =>
                          setState(() => _historyOpen = false),
                    ),
                  ),
                ),
              if (_chrome && _findOpen && _tab?.hasPage == true)
                Positioned(
                  right: 8,
                  top: kWebStripHeight + kWebRowHeight + 2,
                  child: _PopGrow(
                    child: BrowserFindBar(
                      query: _findQuery,
                      queryFocus: _findFocus,
                      total: _findTotal,
                      index: _findIndex,
                      onQueryChanged: _onFindQueryChanged,
                      onNext: _findNext,
                      onPrev: _findPrev,
                      onClose: _closeFind,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  /// Releases the fullscreen hand-off. The JS courtesy asks the document
  /// to leave its own fullscreen (so an `<video>` drops its chrome too);
  /// the notifier flip back-fires [WebTab.wantsFullscreen]'s listener even
  /// if a page ignores the script — SALU never strands its own window.
  void _releasePageFullscreen() {
    final WebTab? tab = _tab;
    final WebviewController? c = tab?.controller;
    if (c != null) {
      unawaited(() async {
        try {
          await c
              .executeScript('if (document.exitFullscreen) {'
                  ' document.exitFullscreen(); }');
        } catch (_) {}
      }());
    }
    if (tab != null && tab.wantsFullscreen.value) {
      tab.wantsFullscreen.value = false;
    } else {
      unawaited(_service.setWebFullscreen(false));
    }
  }

  Widget _buildSheet() {
    final List<WebFavourite> list = _favourites.favourites.value;
    final int? idx = _sheetIndex;
    final WebFavourite? entry =
        (idx == null || idx < 0 || idx >= list.length) ? null : list[idx];
    final WebTab? tab = _tab;
    final String url = entry?.url ?? tab?.url.value ?? '';
    return BrowserFavouriteSheet(
      entryIndex: _sheetIndex,
      entry: entry,
      defaultName: tab?.title.value ??
          (url.isEmpty ? '' : WebAddress.labelFor(url)),
      defaultUrl: url,
      full: _favourites.isFull,
      onSave: _saveFavourite,
      onUpdate: _updateFavourite,
      onRemove: _removeFavourite,
      onClose: () => setState(() {
        _sheetOpen = false;
        _sheetIndex = null;
      }),
    );
  }
}

/// The tab bar's ♥ — the favourites hub's door (web.md · left of the tab
/// row). Lit while the list is open.
class _HubButton extends StatelessWidget {
  const _HubButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SaluIconButton(
      size: 27,
      active: open,
      onTap: onTap,
      tooltip: 'Favourites',
      child: HeartMark(size: 15, filled: open),
    );
  }
}

/// Menus grow from their anchor (follow.md · motion): fade + a small rise.
class _PopGrow extends StatelessWidget {
  const _PopGrow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(0, -0.12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
