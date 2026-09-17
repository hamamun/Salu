import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../core/browser_service.dart';
import '../../core/settings_service.dart';
import '../../core/web/web_address.dart';
import '../../core/web/web_favourites_service.dart';
import '../../core/web/web_history_service.dart';
import '../../core/web/web_suggestions.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import '../../ui/osd/osd_controller.dart';
import '../widgets/browser_address_bar.dart';
import '../widgets/browser_clear_dialog.dart';
import '../widgets/browser_favourite_sheet.dart';
import '../widgets/browser_favourites_hub.dart';
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
/// Tabs live and die inside this widget (service comment): leaving for
/// Player mode tears the whole thing down — controllers disposed, session
/// caches cleared — so "coming back is a clean start" holds without a
/// single bookkeeping thread (web.md · key function 8).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.chromeVisible = true});

  final bool chromeVisible;

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

  /// The star's two-state mirror (web.md · "the star knows").
  final ValueNotifier<bool> _saved = ValueNotifier<bool>(false);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabs.isNotEmpty) return;
      final WebOpenRequest? pending = _service.takePendingRequest();
      if (pending != null) {
        _newTab(url: pending.url, title: pending.title);
      } else {
        _newTab();
      }
    });
  }

  late final StreamSubscription<WebOpenRequest> _openSub;

  @override
  void dispose() {
    _service.browserMounted = false;
    _favourites.favourites.removeListener(_updateStar);
    unawaited(_openSub.cancel());
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
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _onAddressFocusChanged() {
    if (!_addressFocus.hasFocus && _suggestionsShown) {
      setState(_hideSuggestions);
    }
  }

  // ── Tabs ───────────────────────────────────────────────────────────────

  void _newTab({String? url, String? title}) {
    final WebTab tab = WebTab(initialUrl: url, initialTitle: title);
    setState(() {
      _tabs.add(tab);
      _selectLocked(tab);
    });
    tab.activate();
  }

  void _select(WebTab tab) {
    if (identical(tab, _tab)) return;
    _tab?.deactivate();
    _unbindActive();
    setState(() {
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
    setState(() {
      _hideSuggestions();
      if (_tabs.isEmpty) {
        // Last tab closed — Web mode STAYS (web.md lock): the strip keeps
        // its `+`, the content is the start page.
        _active = -1;
        _syncAddressTo('');
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
    if (tab.loading.value && _suggestionsShown) _hideSuggestions();
    if (!_addressFocus.hasFocus) {
      final bool start = tab.startMode.value;
      _syncAddressTo(start ? '' : (tab.url.value ?? ''));
    }
    _updateStar();
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
      if (_suggestionsShown || _hubOpen || _sheetOpen) {
        setState(() {
          _hideSuggestions();
          _hubOpen = false;
          _sheetOpen = false;
          _sheetIndex = null;
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
    });
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
    if (_hubOpen || _sheetOpen || _suggestionsShown) {
      setState(() {
        _hubOpen = false;
        _sheetOpen = false;
        _sheetIndex = null;
        _hideSuggestions();
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool supported = BrowserService.browserSupported;
    final WebTab? tab = _tab;
    final Widget content = !supported || tab == null
        ? const WebStartPage()
        : Stack(
            fit: StackFit.expand,
            children: <Widget>[
              WebTabView(tab: tab),
              // Home parks over a live page — the engine keeps its place
              // (suspended), the start page wears the stage.
              ValueListenableBuilder<bool>(
                valueListenable: tab.startMode,
                builder: (BuildContext context, bool start, Widget? _) {
                  if (!start) return const SizedBox.shrink();
                  return const ColoredBox(
                    color: AppColors.videoBackdrop,
                    child: WebStartPage(),
                  );
                },
              ),
            ],
          );

    return Focus(
      // While the page owns the screen, this focus owns its Esc:
      // the first Esc RELEASES the hand-off (browser convention) —
      // the window only goes back to SALU's strip on the second, and only
      // because the page itself let go.
      autofocus: !_chrome,
      canRequestFocus: !_chrome,
      onKeyEvent: _chrome
          ? null
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
                      onNewTab: () => _newTab(),
                      hub: _HubButton(
                        open: _hubOpen,
                        onTap: () => setState(() {
                          _sheetOpen = false;
                          _sheetIndex = null;
                          _hideSuggestions();
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
                      onSubmit: _submitAddress,
                      onQueryChanged: _onQueryChanged,
                      onCancel: _closePopups,
                      onFavourite: _toggleFavouritePanel,
                      onClearData: () => showWebClearDialog(context),
                      onBack: () => tab?.goBack(),
                      onForward: () => tab?.goForward(),
                      onReload: () => tab?.reload(),
                      onStop: () => tab?.controller?.stop(),
                      onHome: () {
                        tab?.showStartPage();
                        _closePopups();
                      },
                      onKeyEvent: _onAddressKey,
                    ),
                  ],
                  Expanded(child: content),
                ],
              ),
              // One translucent sheet over everything for outside-taps —
              // menus die with the next click anywhere, like Chrome's.
              if (_chrome && (_hubOpen || _sheetOpen || _suggestionsShown))
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
