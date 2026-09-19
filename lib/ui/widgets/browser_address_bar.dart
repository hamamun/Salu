import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/web/web_suggestions.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import '../screens/browser_screen.dart' show kWebRowHeight;
import 'download_badge.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The address bar — the browser's one omnibox (web.md · address bar):
/// navigation to its LEFT (Home · Back · Forward · Reload), the site
/// padlock + the favourite STAR inside its LEFT corner (the padlock names
/// the site, the star saves it), the held-back pop-up badge in its RIGHT
/// corner while a page has any, the download badge between the field and
/// the ⋮ while a download has anything to say, and the ⋮ menu beside it.
///
/// Typing NEVER loads a page (the lock): keystrokes debounce into the
/// suggestion dropdown — Google while-they-type merged with SALU's own
/// history + favourites — and only Enter (or picking a row) navigates.
/// The list's ↑/↓/Enter/Esc run through the screen-owned [onKeyEvent] so
/// bar and menu move as one unit.
class BrowserAddressBar extends StatefulWidget {
  const BrowserAddressBar({
    super.key,
    required this.tab,
    required this.address,
    required this.addressFocus,
    required this.suggestionsShown,
    required this.saved,
    required this.blockedCount,
    required this.onSubmit,
    required this.onQueryChanged,
    required this.onCancel,
    required this.onFavourite,
    required this.onSiteInfo,
    required this.onBlockedTap,
    required this.onMenu,
    this.downloadsOpen = false,
    required this.onDownloadsTap,
    this.onClearData,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
    required this.onHome,
    this.onKeyEvent,
  });

  /// The active tab — null when zero tabs; then Back/Forward/Reload are
  /// inert and the bar starts pages through the screen instead.
  final WebTab? tab;

  final TextEditingController address;
  final FocusNode addressFocus;
  final bool suggestionsShown;

  /// The star's two-state mirror (web.md's "the star knows"):
  /// true = this very page is a favourite.
  final ValueListenable<bool> saved;

  /// How many pop-ups the active page has had held back — the badge's
  /// count, kept by the screen from the active tab's list.
  final ValueListenable<int> blockedCount;

  final VoidCallback onSubmit;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onCancel;

  /// Star tap: the slide-out favourite panel — save flow when outline,
  /// edit flow when filled. One door, two states.
  final VoidCallback onFavourite;

  /// Padlock tap: the site panel (who this page is, pop-up rule).
  final VoidCallback onSiteInfo;

  /// Badge tap: the held-back pop-up list.
  final VoidCallback onBlockedTap;

  /// ⋮ tap: the browser menu (zoom, find, history, …).
  final VoidCallback onMenu;

  /// Whether the download shelf is up — the badge lights like the ♥.
  final bool downloadsOpen;

  /// Download badge tap: the download shelf.
  final VoidCallback onDownloadsTap;
  final VoidCallback? onClearData;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onHome;

  /// Bar and menu are one unit: the screen routes the field's arrow /
  /// Enter / Esc keys here so the highlighted row and the text agree.
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  State<BrowserAddressBar> createState() => _BrowserAddressBarState();
}

class _BrowserAddressBarState extends State<BrowserAddressBar> {
  @override
  void initState() {
    super.initState();
    widget.address.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.address.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(BrowserAddressBar old) {
    super.didUpdateWidget(old);
    if (old.address != widget.address) {
      old.address.removeListener(_onTextChanged);
      widget.address.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() => widget.onQueryChanged(widget.address.text);

  @override
  Widget build(BuildContext context) {
    final WebTab? tab = widget.tab;
    return Container(
      height: kWebRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceOutline)),
      ),
      child: Row(
        children: <Widget>[
          // Navigation lives to the left of the URL bar (web.md). Home
          // takes the current website to its root page; a fresh tab stays
          // on SALU's start page. Back/Forward read the engine's own truth;
          // Reload swaps into Stop while a page travels — the player's
          // Play⇄Pause logic wearing another suit.
          SaluIconButton(
            size: 27,
            onTap: widget.onHome,
            tooltip: 'Home',
            child: const HomeMark(size: 17),
          ),
          const SizedBox(width: 2),
          _GoButton(
            tab: tab,
            forward: false,
            onTap: widget.onBack,
          ),
          _GoButton(
            tab: tab,
            forward: true,
            onTap: widget.onForward,
          ),
          const SizedBox(width: 2),
          _ReloadStopButton(
            tab: tab,
            onReload: widget.onReload,
            onStop: widget.onStop,
          ),
          const SizedBox(width: 7),
          Expanded(child: _buildField()),
          const SizedBox(width: 7),
          // The download badge — Chrome's own slot, immediately left of
          // the ⋮. It stands only while it has something to say, and the
          // omnibox absorbs the width, so the ⋮ never moves.
          DownloadBadge(
            onTap: widget.onDownloadsTap,
            active: widget.downloadsOpen,
          ),
          // ⋮ menu beside the omnibox (zoom, find, history, clear, settings).
          SaluIconButton(
            size: 27,
            onTap: widget.onMenu,
            tooltip: 'Menu',
            child: const MenuMark(size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildField() {
    return Focus(
      onKeyEvent: widget.onKeyEvent == null
          ? null
          : (FocusNode node, KeyEvent event) => widget.onKeyEvent!(node, event),
      child: ListenableBuilder(
        listenable: widget.addressFocus,
        builder: (BuildContext context, Widget? _) {
          final bool focused = widget.addressFocus.hasFocus;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? AppColors.accent : AppColors.surfaceOutline,
              ),
            ),
            padding: const EdgeInsets.only(left: 2, right: 6),
            child: Row(
              children: <Widget>[
                // The padlock names the site; the star saves it. The
                // badge at the far end counts held-back pop-ups.
                _SiteButton(tab: widget.tab, onTap: widget.onSiteInfo),
                SaluIconButton(
                  size: 26,
                  active: focused,
                  onTap: widget.onFavourite,
                  tooltip: 'Favourite',
                  child: _Star(saved: widget.saved),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.address,
                    focusNode: widget.addressFocus,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => widget.onSubmit(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                    ),
                    cursorColor: AppColors.accent,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Search or enter web address',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                _BlockedBadge(
                  count: widget.blockedCount,
                  onTap: widget.onBlockedTap,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The padlock in the bar's LEFT corner (Chrome's 🔒 slot): closed on
/// https, open anywhere else, quiet while no page is showing. Taps open
/// the site panel.
class _SiteButton extends StatefulWidget {
  const _SiteButton({required this.tab, required this.onTap});

  final WebTab? tab;
  final VoidCallback onTap;

  @override
  State<_SiteButton> createState() => _SiteButtonState();
}

class _SiteButtonState extends State<_SiteButton> {
  ValueNotifier<String?>? _url;
  ValueNotifier<bool>? _start;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(_SiteButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.tab, widget.tab)) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() {
    _url = widget.tab?.url;
    _start = widget.tab?.startMode;
    _url?.addListener(_onChange);
    _start?.addListener(_onChange);
  }

  void _detach() {
    _url?.removeListener(_onChange);
    _start?.removeListener(_onChange);
    _url = null;
    _start = null;
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final WebTab? tab = widget.tab;
    final bool alive = tab?.hasPage == true;
    final String u = tab?.url.value ?? '';
    final bool secure = u.toLowerCase().startsWith('https://');
    return SaluIconButton(
      size: 26,
      enabled: alive,
      onTap: widget.onTap,
      tooltip: 'Site information',
      child: PadlockMark(size: 13, open: !secure),
    );
  }
}

/// The held-back badge in the bar's RIGHT corner (Chrome's blocked-pop-up
/// icon + count): present only while the page has pop-ups SALU held back.
/// Taps open the held-back list.
class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge({required this.count, required this.onTap});

  final ValueListenable<int> count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (BuildContext context, int n, Widget? _) {
        if (n <= 0) return const SizedBox.shrink();
        // The badge is a mark + its count, lit by the one SALU recipe —
        // nothing is drawn behind it (follow.md · §2, no filled pill).
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: SaluIconButton(
            size: 26,
            onTap: onTap,
            tooltip: 'Pop-ups blocked',
            child: Builder(
              builder: (BuildContext context) {
                final Color ink =
                    IconTheme.of(context).color ?? AppColors.iconIdle;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const PopupMark(size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.saved});

  final ValueListenable<bool> saved;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: saved,
      builder: (BuildContext context, bool isSaved, Widget? _) =>
          StarMark(size: 15, filled: isSaved),
    );
  }
}

/// Back / Forward with the engine's own can-go state — enabled is the only
/// feedback (follow.md: an inert button dims, never explains).
class _GoButton extends StatefulWidget {
  const _GoButton({
    required this.tab,
    required this.forward,
    required this.onTap,
  });

  final WebTab? tab;
  final bool forward;
  final VoidCallback onTap;

  @override
  State<_GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<_GoButton> {
  ValueNotifier<bool>? _watched;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(_GoButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.tab, widget.tab)) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  ValueNotifier<bool>? get _gate => widget.tab == null
      ? null
      : (widget.forward ? widget.tab!.canGoForward : widget.tab!.canGoBack);

  void _attach() {
    _watched = _gate;
    _watched?.addListener(_onChange);
  }

  void _detach() {
    _watched?.removeListener(_onChange);
    _watched = null;
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SaluIconButton(
      size: 27,
      enabled: _watched?.value ?? false,
      onTap: widget.onTap,
      tooltip: widget.forward ? 'Forward' : 'Back',
      child: ArrowMark(size: 15, flipped: widget.forward),
    );
  }
}

class _ReloadStopButton extends StatefulWidget {
  const _ReloadStopButton({
    required this.tab,
    required this.onReload,
    required this.onStop,
  });

  final WebTab? tab;
  final VoidCallback onReload;
  final VoidCallback onStop;

  @override
  State<_ReloadStopButton> createState() => _ReloadStopButtonState();
}

class _ReloadStopButtonState extends State<_ReloadStopButton> {
  @override
  void initState() {
    super.initState();
    widget.tab?.loading.addListener(_onChange);
  }

  @override
  void didUpdateWidget(_ReloadStopButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.tab, widget.tab)) {
      old.tab?.loading.removeListener(_onChange);
      widget.tab?.loading.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.tab?.loading.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final WebTab? tab = widget.tab;
    if (tab != null && tab.loading.value) {
      return SaluIconButton(
        size: 27,
        onTap: widget.onStop,
        tooltip: 'Stop',
        child: const CloseMark(size: 11),
      );
    }
    return SaluIconButton(
      size: 27,
      enabled: tab != null && !tab.startMode.value,
      onTap: widget.onReload,
      tooltip: 'Reload',
      child: const ReloadMark(size: 16),
    );
  }
}

/// The suggestion dropdown's rows (web.md · address bar lock (1)): the
/// user's own data first — favourites, then history — Google after. The
/// leading mark says the kind; the row text is the query, the page title,
/// or the bookmark name.
class WebSuggestionMenu extends StatelessWidget {
  const WebSuggestionMenu({
    super.key,
    required this.items,
    required this.cursorIndex,
    required this.onPick,
    required this.onHover,
  });

  final List<WebSuggestion> items;
  final int cursorIndex;
  final ValueChanged<WebSuggestion> onPick;
  final ValueChanged<int> onHover;

  static const double rowHeight = 32;

  @override
  Widget build(BuildContext context) {
    return Material(
          elevation: 0,
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemExtent: rowHeight,
              itemBuilder: (BuildContext context, int i) {
                final WebSuggestion item = items[i];
                final bool hot = i == cursorIndex;
                final Widget row = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(item),
                  child: Container(
                    color: hot ? AppColors.surfaceHighlight : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 16,
                          child: Center(
                            child: switch (item.kind) {
                              WebSuggestionKind.favourite =>
                                const StarMark(size: 12, filled: true),
                              WebSuggestionKind.history =>
                                const ClockMark(size: 13),
                              WebSuggestionKind.search => const Text(
                                  '?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                // The pointer lights the row it rests on; ↑/↓ move the
                // very same cursor through [onHover].
                return MouseRegion(
                  onEnter: (_) => onHover(i),
                  child: row,
                );
              },
            ),
          ),
        );
  }
}
