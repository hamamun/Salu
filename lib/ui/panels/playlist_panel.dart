import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/channel_service.dart';
import '../../core/clock_format.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart';
import '../widgets/glass_capsule.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import 'playlist_store.dart';

/// The one geometry of the playlist panel (playlist_imp.md §1.1 / §2.1).
const double kPlaylistPanelWidth = 322;

// ────────────────────────────────────────────────────────────────────────────
// Visible-list model — the REAL queue order is all the list ever shows.
// ────────────────────────────────────────────────────────────────────────────

const double _rowH = 38;
const double _headH = 28;

sealed class _VisRow {
  const _VisRow();
  double get height;
  Object get identity;
}

/// A group head in channel mode (§10.5): open state, count, and the
/// gold-row badge while the playing channel lives in a collapsed group.
final class _HeadRow extends _VisRow {
  const _HeadRow(this.key, this.count, this.open, this.hasNow);

  final String key;
  final int count;
  final bool open;
  final bool hasNow;

  @override
  double get height => _headH;

  @override
  Object get identity => 'head:$key';
}

/// One playlist row — always the true queue index beneath any view
/// transform (m3u M44).
final class _ItemRow extends _VisRow {
  const _ItemRow(this.queueIndex, this.item, this.isNow);

  final int queueIndex;
  final QueueItem item;
  final bool isNow;

  @override
  double get height => _rowH;

  @override
  Object get identity => 'item:$queueIndex';
}

// ────────────────────────────────────────────────────────────────────────────
// The dock, owned by the main window's HomeScreen stack.
// ────────────────────────────────────────────────────────────────────────────

/// The docked playlist shell: a fixed-width glass sheet sliding in from
/// the right over the video — the canvas never resizes (§1.2/§2.1).
/// While the playlist lives in its own window the slot empties entirely:
/// one surface, one view (§9.4).
class PlaylistDock extends StatefulWidget {
  const PlaylistDock({super.key, required this.open, required this.undocked});

  /// `PanelService.playlistOpen` — passed by the HomeScreen, which is the
  /// sole owner of chrome z-order.
  final bool open;
  final bool undocked;

  /// Jumps the rows so the playing row is on screen (§5 auto-scroll).
  static final GlobalKey<_PlaylistPanelState> panelKey =
      GlobalKey<_PlaylistPanelState>();

  @override
  State<PlaylistDock> createState() => _PlaylistDockState();
}

class _PlaylistDockState extends State<PlaylistDock> {
  late final PlaylistStore _store = LivePlaylistStore();

  @override
  void didUpdateWidget(PlaylistDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opening clears the term and reveals the playing row instantly —
    // "the list is scrolled so the playing row is on screen; this
    // entrance scroll does NOT animate" (§5).
    if (widget.open && !oldWidget.open) {
      _store.setFilter('');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PlaylistDock.panelKey.currentState?.revealPlaying(animate: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // While undocked the docked slot shows NOTHING — the panel lives
    // elsewhere (§9.4/m3u M3). Hidden state never animates (§2.1).
    final bool visible = widget.open && !widget.undocked;
    return Positioned(
      top: kChromeBlockHeight,
      right: 0,
      bottom: 0,
      width: kPlaylistPanelWidth,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(1, 0),
            duration: const Duration(milliseconds: 220),
            curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
              child: ClipRect(
                child: PlaylistPanel(
                  key: PlaylistDock.panelKey,
                  store: _store,
                  inOwnWindow: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// The panel content — identical in the dock and in the loose window.
// ────────────────────────────────────────────────────────────────────────────

class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({
    super.key,
    required this.store,
    required this.inOwnWindow,
    this.onDragStart,
  });

  final PlaylistStore store;

  /// Child-window mode: rounded glass all around, a 3 px drag strip on
  /// top; docked mode: top-left radius, left hairline (§1.2/§9.2).
  final bool inOwnWindow;

  /// Child window windows-drag hook (docked: null).
  final VoidCallback? onDragStart;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<_VisRow> _rows = const <_VisRow>[];

  /// Suppresses the auto-reveal for 3 s after the USER scrolls (§5).
  DateTime _userScrollQuietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Keeps the sticky-head overlay + edge hints on the scroll position.
  double _scrollOffset = 0;

  PlaylistStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _rebuild();
    store.addListener(_onStoreChanged);
    _scroll.addListener(_onScrolled);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScrolled() {
    setState(() => _scrollOffset = _scroll.offset);
  }

  void _onStoreChanged() {
    final String filter = store.filter.value;
    if (_search.text != filter) {
      // External resets (panel re-open, child window sync) reach the
      // field without moving the caret mid-typing.
      _search.value = TextEditingValue(
        text: filter,
        selection: TextSelection.collapsed(offset: filter.length),
      );
    }
    final int oldNowRow = _indexOfNowRow();
    _rebuild();
    setState(() {});
    final int newNowRow = _indexOfNowRow();
    // A playing-row change scrolls the row into view (never yanks mid
    // animation — animateTo cancels the previous one).
    if (newNowRow != oldNowRow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        revealPlaying(animate: true);
      });
    }
  }

  /// §5 auto-scroll: puts the playing row on screen with 6 px slack,
  /// shortest distance, 240 ms easeOutCubic — unless the user scrolled
  /// within the last 3 s or is already looking at the row.
  void revealPlaying({required bool animate}) {
    if (!_scroll.hasClients) return;
    if (DateTime.now().isBefore(_userScrollQuietUntil) && animate) return;
    final int row = _indexOfNowRow();
    if (row < 0) return;
    double top = 0;
    for (int i = 0; i < row; i++) {
      top += _rows[i].height;
    }
    final double bottom = top + _rowH;
    final double viewport = _scroll.position.viewportDimension;
    final double offset = _scroll.offset;
    if (top >= offset - 6 && bottom <= offset + viewport + 6) return;
    final double max = _scroll.position.maxScrollExtent;
    final double target = (top < offset ? top : bottom - viewport)
        .clamp(0.0, max);
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  int _indexOfNowRow() {
    for (int i = 0; i < _rows.length; i++) {
      final _VisRow r = _rows[i];
      if (r is _ItemRow && r.isNow) return i;
    }
    return -1;
  }

  // ── The visible-list build (search / grouping / favourites = VIEW) ───

  bool _matches(String term, QueueItem item) {
    if (term.isEmpty) return true;
    final String key = (item.searchKey ?? item.title).toLowerCase();
    return key.contains(term);
  }

  void _rebuild() {
    final List<QueueItem> items = store.items.value;
    final int now = store.index.value;
    final String term = store.filter.value.trim().toLowerCase();
    final List<_VisRow> out = <_VisRow>[];
    if (items.isEmpty) {
      _rows = out;
      return;
    }

    if (!store.isChannelList) {
      // Local mode: one flat list; search never reorders (M44).
      for (int i = 0; i < items.length; i++) {
        if (_matches(term, items[i])) {
          out.add(_ItemRow(i, items[i], i == now));
        }
      }
      _rows = out;
      return;
    }

    // Channel mode: search flattens; favourites-only keeps the heads.
    final Set<String> favs = store.favourites.value;
    final bool favOnly = store.favouritesOnly.value;
    final GroupMode mode = store.groupMode.value;

    final List<int> visibleIndexes = <int>[];
    for (int i = 0; i < items.length; i++) {
      final QueueItem item = items[i];
      if (favOnly &&
          !favs.contains(store.favouriteKeyOf(i) ?? '')) {
        continue;
      }
      if (_matches(term, item)) visibleIndexes.add(i);
    }

    if (term.isNotEmpty || mode == GroupMode.flat) {
      for (final int i in visibleIndexes) {
        out.add(_ItemRow(i, items[i], i == now));
      }
      _rows = out;
      return;
    }

    // Grouped: heads in playlist (or alphabetical) order; exactly one
    // group open; the playing group's members are the visible rows.
    final String? open = store.openGroup.value;
    final Map<String, List<int>> grouped = <String, List<int>>{};
    for (final int i in visibleIndexes) {
      final String key = ChannelService.groupKeyOf(items[i], mode);
      grouped.putIfAbsent(key, () => <int>[]).add(i);
    }
    final List<String> keys = ChannelService.orderGroupKeys(
      grouped.keys,
      mode,
    );
    for (final String key in keys) {
      final List<int> members = grouped[key]!;
      final bool isOpen = key == open;
      final bool hasNow = now >= 0 &&
          ChannelService.groupKeyOf(items[now.clamp(0, items.length - 1)], mode) == key;
      out.add(_HeadRow(key, members.length, isOpen, hasNow));
      if (isOpen) {
        for (final int i in members) {
          out.add(_ItemRow(i, items[i], i == now));
        }
      }
    }
    _rows = out;
  }

  /// Compensates the scroll offset when a head above the viewport
  /// changes height — rows under the cursor never yank (§10.5).
  void _toggleHead(_HeadRow head) {
    // Find the head's top in the CURRENT model.
    double headTop = 0;
    int membersBelow = 0;
    for (final _VisRow r in _rows) {
      if (r is _HeadRow && r.key == head.key) {
        break;
      }
      headTop += r.height;
    }
    if (head.open) {
      // Collapsing: count members directly after this head.
      bool after = false;
      for (final _VisRow r in _rows) {
        if (r is _HeadRow && r.key == head.key) {
          after = true;
          continue;
        }
        if (!after) continue;
        if (r is _HeadRow) break;
        membersBelow++;
      }
    } else {
      membersBelow = head.count; // expanding shows this many new rows
    }
    final double offset = _scroll.hasClients ? _scroll.offset : 0;
    // The change only yanks rows below when the head sits ABOVE the
    // viewport; compensate by exactly the member block's height.
    final double delta = (head.open ? -1 : 1) *
        (headTop + head.height <= offset ? membersBelow * _rowH : 0);
    store.setOpenGroup(head.open ? null : head.key, user: true);
    if (delta != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            (offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
          );
        }
      });
    }
  }

  // ── Esc in the field: clears (focus kept), then releases focus ───────

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_search.text.isNotEmpty) {
        _search.clear();
        store.setFilter('');
      } else {
        node.unfocus();
      }
      return KeyEventResult.handled; // the panel survives (rule E)
    }
    return KeyEventResult.ignored;
  }

  // ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.vertical(
      top: Radius.circular(widget.inOwnWindow ? 12 : 14),
      bottom: Radius.circular(widget.inOwnWindow ? 12 : 0),
    );

    Widget body = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: radius,
            border: Border(
              // The docked sheet carries a left hairline only (§1.2).
              left: widget.inOwnWindow
                  ? BorderSide.none
                  : const BorderSide(
                      color: AppColors.surfaceOutline,
                      width: 0.8,
                    ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Child window: the 3 px drag strip (§9.2).
              if (widget.inOwnWindow)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => widget.onDragStart?.call(),
                  child: const SizedBox(height: 3),
                ),
              if (store.items.value.isNotEmpty) _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );

    // A click anywhere but the field releases the field's focus.
    return Listener(
      onPointerDown: (PointerDownEvent e) {
        if (!_searchFocus.hasFocus) return;
        final RenderObject? field = _searchFocus.context?.findRenderObject();
        final RenderBox? box = field is RenderBox ? field : null;
        if (box == null) return;
        final Offset local = box.globalToLocal(e.position);
        if (!box.size.contains(local)) _searchFocus.unfocus();
      },
      child: body,
    );
  }

  // ── Header (§4): five slots, 6/14 px pitches, the field grows ────────

  Widget _buildHeader() {
    final bool channel = store.isChannelList;
    final RepeatMode repeat = store.repeatMode.value;
    final bool shuffle = store.shuffleOn.value;
    final bool undocked = store.undocked.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
      child: SizedBox(
        height: 30,
        child: Row(
          children: <Widget>[
            if (channel) ...<Widget>[
              _GroupByButton(store: store),
              const SizedBox(width: 6),
              _favouritesButton(),
            ] else ...<Widget>[
              SaluIconButton(
                size: 30,
                tooltip: switch (repeat) {
                  RepeatMode.off => 'Repeat off',
                  RepeatMode.all => 'Repeat all',
                  RepeatMode.one => 'Repeat one',
                },
                active: repeat != RepeatMode.off,
                onTap: store.cycleRepeat,
                child: RepeatMark(
                  size: 18,
                  quiet: repeat == RepeatMode.off,
                  bead: repeat == RepeatMode.one,
                ),
              ),
              const SizedBox(width: 6),
              SaluIconButton(
                size: 30,
                tooltip: 'Shuffle',
                // Repeat one suspends shuffle VISUALLY (quiet ink) — the
                // state itself survives (§4.4/C3).
                active: shuffle && repeat != RepeatMode.one,
                onTap: store.toggleShuffle,
                child: ShuffleMark(size: 18),
              ),
            ],
            const SizedBox(width: 14),
            Expanded(child: _buildSearchField()),
            const SizedBox(width: 14),
            SaluIconButton(
              size: 30,
              tooltip: 'Clear playlist',
              onTap: store.clearPlaylist,
              child: const TrashMark(size: 15),
            ),
            const SizedBox(width: 14),
            SaluIconButton(
              size: 30,
              tooltip: undocked ? 'Dock back' : 'Undock',
              onTap: store.toggleDock,
              child: undocked
                  ? const DockMark(size: 17)
                  : const UndockMark(size: 17),
            ),
          ],
        ),
      ),
    );
  }

  Widget _favouritesButton() {
    final bool favOnly = store.favouritesOnly.value;
    final bool any = store.hasAnyFavourites;
    return SaluIconButton(
      size: 30,
      tooltip: 'Favourites only',
      // A playlist with nothing favourited DIMS the slot — never hides
      // it (group-by house rule).
      enabled: any || favOnly,
      active: favOnly,
      onTap: store.toggleFavouritesOnly,
      child: BookmarkMark(size: 16, filled: favOnly),
    );
  }

  Widget _buildSearchField() {
    final String term = _search.text.trim();
    final int total = store.items.value.length;
    final int shown = _rows.whereType<_ItemRow>().length;

    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.surfaceOutline.withAlpha(60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          Builder(
            builder: (BuildContext context) => IconTheme.merge(
              data: IconTheme.of(context).copyWith(
                color: AppColors.textSecondary,
              ),
              child: const SearchMark(size: 13),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Focus(
              onKeyEvent: _onFieldKey,
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (String v) {
                  store.setFilter(v);
                  setState(() {});
                },
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                cursorColor: AppColors.textPrimary,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
          // The row count lives INSIDE the field: data, as numerals.
          if (term.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '$shown / $total',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          if (term.isNotEmpty)
            _FieldClear(
              onTap: () {
                _search.clear();
                store.setFilter('');
                setState(() {});
              },
            ),
        ],
      ),
    );
  }

  // ── Body: rows / heads / empty + no-match states / edge hints ────────

  Widget _buildBody() {
    final bool empty = store.items.value.isEmpty;
    final bool noMatch = !empty && _rows.whereType<_ItemRow>().isEmpty;
    final bool channel = store.isChannelList;
    final String term = store.filter.value.trim();
    final bool reorderable = !channel && term.isEmpty && !empty;

    final Widget list = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: _scroll,
        thickness: 5,
        thumbVisibility: false,
        radius: const Radius.circular(3),
        fadeDuration: const Duration(milliseconds: 120),
        // thumb .16 → .30 on hover (§4.1-function·m3u M16): transparent
        // track, fades away when idle — the SALU scrollbar.
        thumbColor: WidgetStateColor.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.hovered)
              ? const Color(0x4DFFFFFF)
              : const Color(0x29FFFFFF),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n is UserScrollNotification ||
                (n is ScrollUpdateNotification && n.dragDetails != null)) {
              _userScrollQuietUntil =
                  DateTime.now().add(const Duration(seconds: 3));
            }
            return false;
          },
          child: reorderable
              ? ReorderableListView.builder(
                  scrollController: _scroll,
                  padding: EdgeInsets.zero,
                  itemCount: _rows.length,
                  buildDefaultDragHandles: false,
                  onReorder: _onReorder,
                  itemBuilder: _buildRowAt,
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  itemCount: _rows.length,
                  itemBuilder: _buildRowAt,
                ),
        ),
      ),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: list),
        if (empty)
          const Center(
            // The placeholder is the mark itself, resting quiet — the
            // glyph that never lies (§4.3), not a coaching line.
            child: Opacity(
              opacity: 0.30,
              child: NowRowMark(size: 46, now: -1),
            ),
          )
        else if (noMatch)
          Center(
            child: Opacity(
              opacity: 0.30,
              child: store.favouritesOnly.value && term.isEmpty
                  ? const BookmarkMark(size: 40)
                  : const SearchMark(size: 40),
            ),
          ),
        _buildStickyHead(),
        _buildEdgeHint(top: true),
        _buildEdgeHint(top: false),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Local mode without a filter: visible index == queue index.
    if (newIndex > oldIndex) newIndex -= 1;
    store.moveRow(oldIndex, newIndex);
  }

  Widget _buildRowAt(BuildContext context, int visibleIndex) {
    final _VisRow row = _rows[visibleIndex];
    if (row is _HeadRow) {
      return SizedBox(
        key: ValueKey<Object>(row.identity),
        height: row.height,
        child: _GroupHead(
          head: row,
          onTap: () => _toggleHead(row),
        ),
      );
    }
    final _ItemRow item = row as _ItemRow;
    final bool channel = store.isChannelList;
    final String term = store.filter.value.trim();
    final bool reorderable = !channel && term.isEmpty;
    return SizedBox(
      key: ValueKey<Object>(row.identity),
      height: row.height,
      child: _PlaylistRow(
        item: item.item,
        isNow: item.isNow,
        isChannel: channel,
        duration: item.isNow ? store.duration.value : null,
        favouriteKey:
            channel ? store.favouriteKeyOf(item.queueIndex) : null,
        isFavourite: channel &&
            store.favourites.value
                .contains(store.favouriteKeyOf(item.queueIndex)),
        onTap: () => store.playRow(item.queueIndex),
        onRemove: channel ? null : () => store.removeRow(item.queueIndex),
        onToggleFavourite:
            channel ? () => store.toggleFavourite(item.queueIndex) : null,
        dragHandle: reorderable
            ? ReorderableDragStartListener(
                index: visibleIndex,
                child: const GripMark(size: 13),
              )
            : null,
      ),
    );
  }

  /// §10.5 sticky heads: while the open group's head is scrolled off but
  /// its rows are still visible, the head rides the top of the viewport.
  Widget _buildStickyHead() {
    if (!store.isChannelList) return const SizedBox.shrink();
    final String? open = store.openGroup.value;
    if (open == null) return const SizedBox.shrink();
    if (_rows.isEmpty || !_scroll.hasClients) return const SizedBox.shrink();

    double top = 0;
    int members = 0;
    _HeadRow? head;
    bool afterHead = false;
    for (final _VisRow r in _rows) {
      if (r is _HeadRow && r.key == open) {
        head = r;
        afterHead = true;
        continue;
      }
      if (!afterHead) {
        top += r.height;
      } else if (r is _HeadRow) {
        break;
      } else {
        members++;
      }
    }
    if (head == null) return const SizedBox.shrink();
    final double bodyBottom = top + head.height + members * _rowH;
    final double offset = _scrollOffset;
    if (top >= offset || bodyBottom <= offset) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 5,
      height: head.height,
      child: GlassCapsule(
        radius: 0,
        height: head.height,
        padding: EdgeInsets.zero,
        child: _GroupHead(
          head: head,
          onTap: () => _toggleHead(head),
        ),
      ),
    );
  }

  /// §10.6 edge hints: the playing row off-screen → a quiet chevron on
  /// the matching edge; click reveals (expanding a collapsed group
  /// first). At rest: nothing.
  Widget _buildEdgeHint({required bool top}) {
    final int row = _indexOfNowRow();
    if (row < 0 || !_scroll.hasClients || _rows.isEmpty) {
      return const SizedBox.shrink();
    }
    double rowTop = 0;
    for (int i = 0; i < row; i++) {
      rowTop += _rows[i].height;
    }
    final double rowBottom = rowTop + _rowH;
    final double offset = _scrollOffset;
    final double viewport = _scroll.position.viewportDimension;
    final bool offTop = rowBottom <= offset;
    final bool offBottom = rowTop >= offset + viewport;
    final bool show = top ? offTop : offBottom;
    if (!show) return const SizedBox.shrink();

    return Positioned(
      top: top ? 2 : null,
      bottom: top ? null : 2,
      right: 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // The playing channel may sit in a collapsed group (§10.6):
          // open it, then reveal.
          _ensurePlayingGroupOpen();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            revealPlaying(animate: true);
          });
        },
        child: Opacity(
          opacity: 0.55,
          child: Transform.rotate(
            angle: top ? -1.5707963 : 1.5707963,
            child: const NowRowMark(size: 18, now: 1),
          ),
        ),
      ),
    );
  }

  void _ensurePlayingGroupOpen() {
    if (!store.isChannelList) return;
    final List<QueueItem> items = store.items.value;
    final int now = store.index.value;
    final GroupMode mode = store.groupMode.value;
    if (mode == GroupMode.flat || now < 0 || now >= items.length) return;
    final String key = ChannelService.groupKeyOf(items[now], mode);
    if (store.openGroup.value != key) {
      store.setOpenGroup(key, user: false);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Header parts
// ────────────────────────────────────────────────────────────────────────────

/// Header slot 1 in channel mode (§10.2 / M5): ONE stable mark; the four
/// modes ride its pill as glyphs. The mark goes QUIET while a search is
/// flattening the list (M26) — the pill stays openable.
class _GroupByButton extends StatefulWidget {
  const _GroupByButton({required this.store});

  final PlaylistStore store;

  @override
  State<_GroupByButton> createState() => _GroupByButtonState();
}

class _GroupByButtonState extends State<_GroupByButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  static const Map<GroupModeKind, GroupMode> _modes =
      <GroupModeKind, GroupMode>{
    GroupModeKind.flat: GroupMode.flat,
    GroupModeKind.category: GroupMode.category,
    GroupModeKind.language: GroupMode.language,
    GroupModeKind.country: GroupMode.country,
  };

  void _toggle() {
    if (_portal.isShowing) {
      _hide();
    } else {
      _portal.show();
      setState(() {});
    }
  }

  void _hide() {
    _portal.hide();
    // The pill's Esc-holding Focus must release or the next key would
    // land on a hidden node.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool searching = widget.store.filter.value.trim().isNotEmpty;
    final bool open = _portal.isShowing;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (BuildContext context) {
          // The pill follows popup precedent: Esc closes and a click
          // outside closes — the translucent listener lets that click
          // pass through to whatever sits beneath (never swallowed).
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) {
                    if (_portal.isShowing) _hide();
                  },
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(-2, 6),
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      if (_portal.isShowing) _hide();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _GroupByPill(
                    store: widget.store,
                    onPick: (GroupMode mode) {
                      widget.store.setGroupMode(mode);
                      _hide();
                    },
                    onDismiss: _hide,
                  ),
                ),
              ),
            ],
          );
        },
        child: SaluIconButton(
          size: 30,
          tooltip: 'Group by',
          active: open,
          onTap: _toggle,
          child: GroupByMark(size: 18, quiet: searching && !open),
        ),
      ),
    );
  }
}

/// The group-by pill (§10.2/M5): four marks on a glass capsule, active
/// state glows, unavailable modes dim (never hide). open → act → gone
/// (§2.1), 130 ms fade+scale like the OSD (§10.2).
class _GroupByPill extends StatefulWidget {
  const _GroupByPill({
    required this.store,
    required this.onPick,
    required this.onDismiss,
  });

  final PlaylistStore store;
  final ValueChanged<GroupMode> onPick;
  final VoidCallback onDismiss;

  @override
  State<_GroupByPill> createState() => _GroupByPillState();
}

class _GroupByPillState extends State<_GroupByPill> {
  @override
  Widget build(BuildContext context) {
    final GroupMode current = widget.store.groupMode.value;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double scale, Widget? child) {
        return Opacity(
          opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: GlassCapsule(
          radius: 12,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final MapEntry<GroupModeKind, GroupMode> e
                  in _GroupByButtonState._modes.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: SaluIconButton(
                    size: 28,
                    tooltip: switch (e.value) {
                      GroupMode.flat => 'Flat list',
                      GroupMode.category => 'Group by category',
                      GroupMode.language => 'Group by language',
                      GroupMode.country => 'Group by country',
                    },
                    active: current == e.value,
                    enabled: widget.store.groupModeAvailable(e.value),
                    onTap: () => widget.onPick(e.value),
                    child: GroupModeMark(kind: e.key, size: 17),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The field-local ✕ — appears the instant text lands (§4.6).
class _FieldClear extends StatefulWidget {
  const _FieldClear({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_FieldClear> createState() => _FieldClearState();
}

class _FieldClearState extends State<_FieldClear> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: AnimatedScale(
              scale: _hovered ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: CustomPaint(
                size: const Size.square(12),
                painter: _CrossPainter(
                  _hovered
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  markStrokeFor(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Rows
// ────────────────────────────────────────────────────────────────────────────

/// A group head row (§10.5): h 28, chevron + name + count; the whole row
/// is the click target (§10.7).
class _GroupHead extends StatefulWidget {
  const _GroupHead({required this.head, required this.onTap});

  final _HeadRow head;
  final VoidCallback onTap;

  @override
  State<_GroupHead> createState() => _GroupHeadState();
}

class _GroupHeadState extends State<_GroupHead> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 14),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: 0.60,
                child: Transform.rotate(
                  // Open = rotated down, closed = plain chevron-right —
                  // the now-row chevron's own grammar.
                  angle: widget.head.open ? 1.5707963 : 0,
                  child: const NowRowMark(size: 11, now: 1),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  widget.head.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _hovered
                        ? AppColors.textPrimary
                        : AppColors.textPrimary.withAlpha(205),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${widget.head.count}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              // The playing channel lives in a collapsed group → the head
              // carries the accent chevron badge.
              if (widget.head.hasNow && !widget.head.open)
                Builder(
                  builder: (BuildContext context) => IconTheme.merge(
                    data: IconTheme.of(context)
                        .copyWith(color: AppColors.accent),
                    child: const NowRowMark(size: 10, now: 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One playlist row, fixed 38 px (§4.2):
///
///   local   — ≡ grip · › chevron · name · duration (current only) · 🗑
///   channel — › chevron · name · channel no. · bookmark
///
/// Everything crooked about a row lives WITHIN the row; everywhere else
/// stays straight rows.
class _PlaylistRow extends StatefulWidget {
  const _PlaylistRow({
    required this.item,
    required this.isNow,
    required this.isChannel,
    required this.onTap,
    this.duration,
    this.favouriteKey,
    this.isFavourite = false,
    this.onRemove,
    this.onToggleFavourite,
    this.dragHandle,
  });

  final QueueItem item;
  final bool isNow;
  final bool isChannel;
  final VoidCallback onTap;
  final Duration? duration;
  final String? favouriteKey;
  final bool isFavourite;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleFavourite;

  /// The local-mode grip (null in channel mode — m3u rows never reorder).
  final Widget? dragHandle;

  @override
  State<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends State<_PlaylistRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool now = widget.isNow;
    final Color nameColor = now
        ? AppColors.accent
        : (_hovered
            ? AppColors.textPrimary
            : AppColors.textPrimary.withAlpha(225));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 10),
          child: Row(
            children: <Widget>[
              // Grip (local only) — the drag verb, always shown.
              if (widget.dragHandle != null)
                SizedBox(
                  width: 22,
                  child: Center(
                    child: Opacity(opacity: 0.55, child: widget.dragHandle!),
                  ),
                )
              else
                const SizedBox(width: 22),
              // Chevron zone: the playing row carries the accent chevron;
              // every row shows a quiet one on hover.
              SizedBox(
                width: 22,
                child: now
                    ? Builder(
                        builder: (BuildContext context) => IconTheme.merge(
                          data: IconTheme.of(context)
                              .copyWith(color: AppColors.accent),
                          child: const NowRowMark(size: 20, now: 1),
                        ),
                      )
                    : AnimatedOpacity(
                        opacity: _hovered ? 0.55 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: const NowRowMark(size: 20, now: 1),
                      ),
              ),
              const SizedBox(width: 4),
              // The name — data, never instruction.
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: now ? FontWeight.w600 : FontWeight.w400,
                    color: nameColor,
                  ),
                ),
              ),
              // The right slot: duration (local, current row only) or the
              // channel number — numerals are data.
              if (widget.isChannel)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    widget.item.chno ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else if (now && widget.duration != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    formatClock(widget.duration!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              // 🗑 (local, hover-only — removal appears where needed).
              if (widget.onRemove != null)
                _RowAction(
                  visible: _hovered,
                  onTap: widget.onRemove!,
                  child: const TrashMark(size: 13),
                ),
              // Bookmark (channel; always visible while favourited).
              if (widget.onToggleFavourite != null &&
                  widget.favouriteKey != null)
                _RowAction(
                  visible: widget.isFavourite || _hovered,
                  onTap: widget.onToggleFavourite!,
                  child: BookmarkMark(
                    size: 13,
                    filled: widget.isFavourite,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hover-only row action (🗑 / flying bookmark): appears with the row,
/// follows the SaluIconButton grammar without taking slot space at rest.
class _RowAction extends StatefulWidget {
  const _RowAction({
    required this.visible,
    required this.onTap,
    required this.child,
  });

  final bool visible;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends State<_RowAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Opacity(
          opacity: widget.visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !widget.visible,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: AnimatedScale(
                  scale: _hovered ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: _hovered
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
