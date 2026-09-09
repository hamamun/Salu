import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import '../../core/channel_favourites_service.dart';
import '../../core/channel_grouping.dart';
import '../../core/channel_load_service.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../osd/osd_controller.dart';
import '../widgets/channel_logo.dart';
import '../widgets/glass_capsule.dart';
import '../widgets/live_light.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// SALU's slide-out playlist panel (playlist_imp.md §4 · §10) — the *view*
/// over the queue that the control-row Playlist mark opens.
///
/// Mounted in `HomeScreen`'s Stack at `top: kChromeBlockHeight`, sliding
/// from the right edge (`Positioned top/right/bottom`, width 322) so it
/// never covers its own toggle and never moves the chrome (rule 5). It is
/// glass *over* the picture — the video never rescales and nothing shifts.
///
/// Open/close is owned by [PanelService.playlistOpen], exactly as the mark
/// reads it. One 220 ms controller drives forward/reverse (a mid-flight
/// toggle reverses instead of restarting); the panel stops hit-testing the
/// instant it starts closing. When closed it is pushed fully off-screen
/// and ignores the pointer, so video clicks pass straight through.
///
/// In channel mode (§10.2–§10.6) the same panel becomes the channel list —
/// same glass, same slide, same width; only the header and the rows change:
/// a group-by + favourites pair, a total-only search, 38 px rows with a
/// logo slot and hover bookmarks, grouped accordions with a sticky head,
/// and edge chevrons pointing at the playing channel hiding off-screen.
/// The local list below is untouched — every channel branch is additive.
class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({super.key});

  /// Panel width — matches the interactive study (322 px).
  static const double width = 322;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel>
    with TickerProviderStateMixin {
  final PanelService _panel = PanelService.instance;
  final QueueService _queue = QueueService.instance;
  final PlayerService _player = PlayerService.instance;
  final ChannelFavouritesService _favourites =
      ChannelFavouritesService.instance;
  final ChannelLoadService _loads = ChannelLoadService.instance;

  /// Fixed pitch of a playlist row (drag reorder needs exact extents).
  static const double _rowExtent = 40;

  /// Fixed pitch of a channel row and a group head — 50 000 channels stay
  /// a scroll offset, never 50 000 laid-out widgets (§10.10c).
  static const double _channelRowExtent = 38;

  late final AnimationController _open;
  late final Animation<double> _curve;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  final ScrollController _scroll = ScrollController();
  bool _programmatic = false;
  bool _userScrolled = false;
  Timer? _userScrollTimer;

  // ── Channel view state (playlist_imp.md §10.2–§10.6) ────────────────

  /// The grouping the viewer chose — Flat until they say otherwise (M6).
  /// A pure view choice: it never touches the queue (M45).
  ChannelGroupMode _groupMode = ChannelGroupMode.flat;

  /// Favourites-only filter (the header bookmark) — groups stay, rows
  /// thin to bookmarks; combined with a search, search wins (§10.3).
  bool _favOnly = false;

  /// The accordion's one open group (its stable key), or `null` while
  /// every group is collapsed. A stale key simply opens nothing.
  String? _openGroup;

  /// Whether the search field holds focus — while it does, the channel
  /// header's mode pair steps aside so the field can breathe (§10.3).
  bool _searchFocused = false;

  /// The group-by pill: an overlay under the header button (the Open
  /// pill's recipe — root overlay, 150 ms fade, Esc/outside to close).
  final OverlayPortalController _pill = OverlayPortalController();
  late final AnimationController _pillAnim;
  bool _pillOpen = false;
  Timer? _pillHideTimer;

  /// Cached channel view: the filtered indexes + the descriptor list the
  /// rows paint. Rebuilt only when its key changes — a scroll tick must
  /// never regroup 50 000 rows (§10.10c).
  List<QueueItem>? _cacheItems;
  String _cacheQuery = '';
  bool _cacheFavOnly = false;
  ChannelGroupMode _cacheMode = ChannelGroupMode.flat;
  String? _cacheOpen;
  Set<String>? _cacheFavs;
  List<int> _cachedFiltered = const <int>[];
  List<ChannelDescriptor> _cachedDescriptors = const <ChannelDescriptor>[];

  /// Cached reveal target (see [_revealTargetPos]) — the edge chevrons
  /// sample the scroll on every tick, and that sample must not scan the
  /// descriptor list again.
  List<ChannelDescriptor>? _targetDescs;
  int _targetCurrent = -2;
  int? _cachedTarget;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _curve = CurvedAnimation(
      parent: _open,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _pillAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _panel.playlistOpen.addListener(_onOpenChanged);
    _queue.index.addListener(_onIndexChanged);
    _scroll.addListener(_onScroll);
    // Keep the panel reflecting the freshly opened (or cleared) queue.
    _queue.items.addListener(_onItemsChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    _favourites.favourites.addListener(_onFavouritesChanged);
    _loads.loadGeneration.addListener(_onLoadGeneration);
    _loads.loading.addListener(_onLoadingChanged);
  }

  @override
  void dispose() {
    _panel.playlistOpen.removeListener(_onOpenChanged);
    _queue.index.removeListener(_onIndexChanged);
    _queue.items.removeListener(_onItemsChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _favourites.favourites.removeListener(_onFavouritesChanged);
    _loads.loadGeneration.removeListener(_onLoadGeneration);
    _loads.loading.removeListener(_onLoadingChanged);
    _scroll.removeListener(_onScroll);
    _userScrollTimer?.cancel();
    _pillHideTimer?.cancel();
    if (_pillOpen) ChromeLock.instance.release();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _open.dispose();
    _pillAnim.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (_panel.playlistOpen.value) {
      _open.forward();
      // Entrance jump — ignore any stale scroll suppression.
      final List<QueueItem> items = _queue.items.value;
      if (items.isNotEmpty && items.first.isChannel) {
        _revealChannel(items, animate: false, force: true);
      } else {
        _revealPlaying(animate: false, force: true);
      }
    } else {
      _hidePillNow();
      _open.reverse();
    }
    setState(() {});
  }

  void _onItemsChanged() {
    // The pill's availability snapshot belongs to the old list.
    if (_queue.items.value.isEmpty) _hidePillNow();
    setState(() {});
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() => _searchFocused = _searchFocus.hasFocus);
  }

  void _onFavouritesChanged() {
    if (!mounted) return;
    // A toggle repaints bookmarks (and the favourites-only view) — the
    // descriptor cache keys on the set's identity, so it rebuilds once.
    setState(() {});
  }

  void _onLoadingChanged() {
    if (!mounted) return;
    // The fetch light and the stale count tone answer the loading flag.
    setState(() {});
  }

  /// A new channel load: the view starts blank (M6/M-7) — Flat, no
  /// search, no favourites filter, accordion closed, scroll parked at
  /// the top. Undo restores rows WITHOUT bumping the generation, so the
  /// filters it preserves carry over untouched.
  void _onLoadGeneration() {
    _hidePillNow();
    _search.clear();
    _query = '';
    _favOnly = false;
    _groupMode = ChannelGroupMode.flat;
    _openGroup = null;
    _userScrollTimer?.cancel();
    _userScrolled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _programmatic = true;
      try {
        _scroll.jumpTo(0);
      } catch (_) {
        // No content yet — the jump is meaningless, not an error.
      }
      _programmatic = false;
    });
    if (mounted) setState(() {});
  }

  void _onIndexChanged() {
    setState(() {});
    if (!_panel.playlistOpen.value) return;
    final List<QueueItem> items = _queue.items.value;
    if (items.isNotEmpty && items.first.isChannel) {
      _revealOnChannelIndex(items);
      return;
    }
    // A deliberate index change (auto-advance, Next, Previous, row click)
    // must always reveal the playing row. Per §4.3 the "don't fight the
    // user" suppression is lifted on the next index change, so we clear
    // it here and force the reveal even if a recent scroll had armed it.
    _userScrollTimer?.cancel();
    _userScrolled = false;
    _revealPlaying(animate: true, force: true);
  }

  /// A manual scroll suppresses the reveal for ~3 s (never fight the
  /// user, §4.3). Programmatic reveals set [_programmatic] so their own
  /// motion is never misread as a user scroll.
  void _onScroll() {
    if (_programmatic) return;
    if (!_userScrolled) setState(() => _userScrolled = true);
    _userScrollTimer?.cancel();
    _userScrollTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _userScrolled) setState(() => _userScrolled = false);
    });
  }

  // ── Row / search helpers ─────────────────────────────────────────────

  /// Real queue indexes shown by the current filter (the view only —
  /// the queue itself is never reordered by a search, §4.5).
  List<int> _visibleRows(List<QueueItem> items) {
    if (_query.isEmpty) {
      return List<int>.generate(items.length, (int i) => i);
    }
    final String needle = _query.toLowerCase();
    final List<int> out = <int>[];
    for (int i = 0; i < items.length; i++) {
      if (items[i].searchText.contains(needle)) out.add(i);
    }
    return out;
  }

  /// Rebuilds the channel view cache when its key changed: the filtered
  /// real queue indexes, then the descriptor list the rows paint. The
  /// key covers the items' identity (every queue mutation publishes a
  /// new list), the query, the favourites filter + set, the mode and the
  /// open group — anything else reuses the cache untouched.
  void _ensureChannelCache(List<QueueItem> items) {
    final Set<String> favs = _favourites.favourites.value;
    if (identical(items, _cacheItems) &&
        _cacheQuery == _query &&
        _cacheFavOnly == _favOnly &&
        _cacheMode == _groupMode &&
        _cacheOpen == _openGroup &&
        identical(favs, _cacheFavs)) {
      return;
    }
    final String needle = _query.toLowerCase();
    final List<int> filtered = <int>[];
    for (int i = 0; i < items.length; i++) {
      final QueueItem item = items[i];
      if (_query.isNotEmpty && !item.searchText.contains(needle)) continue;
      if (_favOnly &&
          !favs.contains(ChannelFavouritesService.channelKey(item))) {
        continue;
      }
      filtered.add(i);
    }
    _cacheItems = items;
    _cacheQuery = _query;
    _cacheFavOnly = _favOnly;
    _cacheMode = _groupMode;
    _cacheOpen = _openGroup;
    _cacheFavs = favs;
    _cachedFiltered = filtered;
    // A search flattens the list whatever the mode is (§10.3) — the
    // grouping is suspended, not forgotten.
    _cachedDescriptors = ChannelGrouping.descriptors(
      items: items,
      filtered: filtered,
      mode: _groupMode,
      openGroupKey: _openGroup,
      flattened: _query.isNotEmpty,
    );
  }

  /// Descriptor position the reveal (and the edge chevrons) aim at: the
  /// playing channel's row when it is in the list, else its group head
  /// (`null` when a filter hides it entirely — there is nothing sane to
  /// scroll to). Cached per descriptor list + current index so the
  /// scroll-tick sampling stays O(1).
  int? _revealTargetPos(List<QueueItem> items) {
    _ensureChannelCache(items);
    final int current = _queue.index.value;
    if (current < 0 ||
        current >= items.length ||
        _cachedDescriptors.isEmpty) {
      return null;
    }
    if (identical(_cachedDescriptors, _targetDescs) &&
        current == _targetCurrent) {
      return _cachedTarget;
    }
    int? target;
    for (int i = 0; i < _cachedDescriptors.length; i++) {
      final ChannelDescriptor d = _cachedDescriptors[i];
      if (d is ChannelRowDescriptor && d.index == current) {
        target = i;
        break;
      }
    }
    if (target == null &&
        _query.isEmpty &&
        _groupMode != ChannelGroupMode.flat) {
      final String? dest =
          ChannelGrouping.keyFor(items, current, _groupMode);
      if (dest != null) {
        for (int i = 0; i < _cachedDescriptors.length; i++) {
          final ChannelDescriptor d = _cachedDescriptors[i];
          if (d is GroupHeadDescriptor && d.key == dest) {
            target = i;
            break;
          }
        }
      }
    }
    _targetDescs = _cachedDescriptors;
    _targetCurrent = current;
    _cachedTarget = target;
    return target;
  }

  /// Scrolls so the playing row is visible. A *deliberate* step (auto-advance,
  /// Next, Previous, row click, panel open) passes [force] to bypass the
  /// "never fight the user" scroll suppression; only a live/very-recent
  /// manual scroll should hold the reveal back (§4.3).
  void _revealPlaying({required bool animate, bool force = false}) {
    if (_userScrolled && !force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final int current = _queue.index.value;
      final int pos = _visibleRows(_queue.items.value).indexOf(current);
      if (pos < 0) return;
      final ScrollPosition p = _scroll.position;
      // Skip until content metrics exist — reading them earlier throws a
      // null check on the very frame a list is added to / resized.
      if (!p.hasPixels ||
          !p.hasViewportDimension ||
          !p.hasContentDimensions) {
        return;
      }
      final double target = (pos * _rowExtent)
          .clamp(0.0, p.maxScrollExtent)
          .toDouble();
      // Already comfortably on screen (6 px slack each side)?
      final double top = p.pixels;
      final double bottom = top + p.viewportDimension;
      if (target >= top + 6 && target + _rowExtent <= bottom - 6) return;
      _programmatic = true;
      if (animate) {
        _scroll
            .animateTo(target,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic)
            .whenComplete(() => _programmatic = false);
      } else {
        _scroll.jumpTo(target);
        _programmatic = false;
      }
    });
  }

  /// The channel reveal: scrolls the playing channel (or its group head)
  /// into view. A deliberate call passes [force] to bypass the scroll
  /// suppression; an automatic one respects it — and a filter that hides
  /// the channel hides the reveal too (there is nothing to scroll to).
  void _revealChannel(List<QueueItem> items,
      {required bool animate, bool force = false}) {
    if (_userScrolled && !force) return;
    final int? pos = _revealTargetPos(items);
    if (pos == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      if (!p.hasPixels ||
          !p.hasViewportDimension ||
          !p.hasContentDimensions) {
        return;
      }
      // The list pads its content by 2 px (see the builder below).
      final double target = (2 + pos * _channelRowExtent)
          .clamp(0.0, p.maxScrollExtent)
          .toDouble();
      final double top = p.pixels;
      final double bottom = top + p.viewportDimension;
      if (target >= top + 6 &&
          target + _channelRowExtent <= bottom - 6) {
        return;
      }
      _programmatic = true;
      if (animate) {
        _scroll
            .animateTo(target,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic)
            .whenComplete(() => _programmatic = false);
      } else {
        _scroll.jumpTo(target);
        _programmatic = false;
      }
    });
  }

  /// Answers a channel index change (playlist_imp.md §10.6 M54): a
  /// deliberate zap always reveals — opening a collapsed destination
  /// group — while an automatic failure skip into an unbrowsed group
  /// never steals the view. The toast, the title bar and the head/edge
  /// chevrons say where it landed instead.
  void _revealOnChannelIndex(List<QueueItem> items) {
    final int current = _queue.index.value;
    final bool auto = _player.lastOpenWasAuto;
    final bool grouped =
        _query.isEmpty && _groupMode != ChannelGroupMode.flat;
    if (grouped) {
      final String? dest =
          ChannelGrouping.keyFor(items, current, _groupMode);
      if (auto) {
        if (dest != null && dest == _openGroup) {
          _ensureChannelCache(items);
          if (_cachedFiltered.contains(current)) {
            _revealChannel(items, animate: true);
          }
        }
        return;
      }
      if (dest != null && dest != _openGroup) {
        setState(() => _openGroup = dest);
      }
      _userScrollTimer?.cancel();
      _userScrolled = false;
      _revealChannel(items, animate: true, force: true);
      return;
    }
    if (!auto) {
      _userScrollTimer?.cancel();
      _userScrolled = false;
    }
    _revealChannel(items, animate: true, force: !auto);
  }

  // ── Group-by pill ────────────────────────────────────────────────────

  void _togglePill() => _pillOpen ? _closePill() : _openPill();

  void _openPill() {
    if (_pillOpen) return;
    _pillHideTimer?.cancel();
    ChromeLock.instance.acquire();
    // Opening the pill blurs the search field (§10.5) — the pill owns
    // the keyboard until Esc or a choice closes it.
    _searchFocus.unfocus();
    setState(() => _pillOpen = true);
    _pillAnim.forward();
    _pill.show();
  }

  void _closePill() {
    if (!_pillOpen) return;
    setState(() => _pillOpen = false);
    _pillAnim.reverse();
    ChromeLock.instance.release();
    // Let the reverse fade play out before tearing the overlay down.
    _pillHideTimer?.cancel();
    _pillHideTimer = Timer(const Duration(milliseconds: 160), () {
      if (mounted) _pill.hide();
    });
  }

  /// Immediate teardown (panel close, emptied list, new load) — no exit
  /// fade; the surface the pill belongs to is already gone.
  void _hidePillNow() {
    if (!_pillOpen) return;
    _pillHideTimer?.cancel();
    _pillHideTimer = null;
    _pillOpen = false;
    _pillAnim.value = 0;
    ChromeLock.instance.release();
    _pill.hide();
  }

  /// Applies a pill choice: selecting a grouped mode opens the group
  /// holding the playing channel (§10.5); Flat closes the accordion.
  /// A pure view change — the queue is never touched (M45).
  void _chooseMode(ChannelGroupMode mode) {
    _closePill();
    if (mode == _groupMode) return;
    final List<QueueItem> items = _queue.items.value;
    setState(() {
      _groupMode = mode;
      _openGroup = mode == ChannelGroupMode.flat
          ? null
          : ChannelGrouping.keyFor(items, _queue.index.value, mode);
    });
    _userScrollTimer?.cancel();
    _userScrolled = false;
    _revealChannel(items, animate: true, force: true);
  }

  // ── Actions (each shows a 5 s Undo toast when it changed the queue) ──

  void _play(int index) {
    _wakeFocusRelease();
    unawaited(_player.playIndex(index));
  }

  void _toggleFavourite(QueueItem item) {
    _favourites.toggleFavourite(item);
  }

  Future<void> _removeRow(int index) async {
    final RemovedItemUndo? undo = await _player.removeFromQueue(index);
    if (!mounted || undo == null) return;
    OsdController.instance.show(OsdUndoCard(
      label: undo.text,
      onUndo: () => unawaited(_player.undoRemoveFromQueue(undo)),
    ));
  }

  Future<void> _clearAll() async {
    final ClearedQueueUndo? undo = await _player.clearQueue();
    if (!mounted || undo == null) return;
    _clearQuery();
    OsdController.instance.show(OsdUndoCard(
      label: undo.text,
      onUndo: () => unawaited(_player.undoClearQueue(undo)),
    ));
  }

  Future<void> _move(int from, int to) async {
    final MovedItemUndo? undo = await _player.moveInQueue(from, to);
    if (!mounted || undo == null) return;
    OsdController.instance.show(OsdUndoCard(
      label: undo.text,
      onUndo: () => unawaited(_player.undoMoveInQueue(undo)),
    ));
  }

  void _wakeFocusRelease() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    }
  }

  void _clearQuery() {
    if (_query.isEmpty) return;
    _search.clear();
    setState(() => _query = '');
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool open = _panel.playlistOpen.value;
    return Positioned(
      top: kChromeBlockHeight,
      right: 0,
      bottom: 0,
      width: PlaylistPanel.width,
      child: IgnorePointer(
        // Stops hit-testing the instant it starts closing (§4.0).
        ignoring: !open,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (BuildContext context, Widget? _) {
            final double v = _curve.value.clamp(0.0, 1.0).toDouble();
            return Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset((1 - v) * PlaylistPanel.width, 0),
                child: _glass(_body()),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The panel's frosted-glass body: `AppColors.glass` + blur 18, a
  /// top-left radius 14 and a hairline on the LEFT edge only — the
  /// `GlassCapsule` recipe, not a new one (§4.1).
  Widget _glass(Widget child) {
    return ClipPath(
      clipper: const _TopLeftRadius(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: AppColors.glass,
          child: Stack(
            children: <Widget>[
              Positioned(left: 0, top: 0, bottom: 0, width: 1,
                  child: const ColoredBox(color: AppColors.surfaceOutline)),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final List<QueueItem> items = _queue.items.value;
    if (items.isEmpty) {
      // A load still arriving shows the wordless fetch light (§10.10b);
      // a settled empty panel shows the quiet mark (§4.6).
      if (_loads.loading.value) return _fetchLight();
      return _emptyState();
    }
    final bool channel = items.first.isChannel;
    final int count = items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        channel ? _channelHeader(count) : _header(count),
        Expanded(child: channel ? _channelRowsArea(items) : _rowsArea(items)),
      ],
    );
  }

  Widget _emptyState() {
    // The mark itself, ~30 % ink, centred — no words, no hint (§4.6).
    return Center(
      child: IconTheme.merge(
        data: const IconThemeData(color: Color(0x4DE8E8E8)),
        child: const NowRowMark(size: 46, now: -1),
      ),
    );
  }

  /// The wordless fetch indicator (§10.10b): the still soft light,
  /// centred — the network-fetch state reuses the same light as live
  /// playback. No spinner, no words.
  Widget _fetchLight() {
    return const Center(
      child: SizedBox(
        width: 120,
        height: 23,
        child: StillSoftLight(visible: true),
      ),
    );
  }

  // ── Header (only while the queue is non-empty, §4.4) ────────────────

  Widget _header(int count) {
    final int shown = _visibleRows(_queue.items.value).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(
        height: 30,
        child: Row(
          children: <Widget>[
            _repeatButton(),
            const SizedBox(width: 4),
            _shuffleButton(),
            const SizedBox(width: 8),
            Expanded(child: _searchField(count, shown)),
            const SizedBox(width: 8),
            _headerButton(
              tooltip: 'Clear playlist',
              active: false,
              mark: const TrashMark(size: 16),
              onTap: () => unawaited(_clearAll()),
            ),
            const SizedBox(width: 4),
            _headerButton(
              tooltip: 'Close playlist',
              active: false,
              mark: Transform.rotate(
                angle: 0.7853981633974483,
                child: const PlusMark(size: 16),
              ),
              onTap: () => _panel.closePlaylist(),
            ),
          ],
        ),
      ),
    );
  }

  /// The channel header (§10.2 · point 5 Final): `[group-by · fav] 14
  /// [search] 14 [bin] 14 [close]` — 6 px inside the mode pair, 14 px
  /// between the header's four groups, exactly the approved preview.
  /// While the search field holds focus the mode pair steps aside so the
  /// field can breathe (channel only — the local header never does).
  Widget _channelHeader(int count) {
    final bool searching = _query.isNotEmpty;
    final bool hidePair = _searchFocused;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(
        height: 30,
        child: Row(
          children: <Widget>[
            if (!hidePair) ...<Widget>[
              _groupByButton(searching),
              const SizedBox(width: 6),
              _headerButton(
                tooltip: 'Favourites',
                active: _favOnly,
                mark: BookmarkMark(size: 18, filled: _favOnly),
                onTap: () => setState(() => _favOnly = !_favOnly),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(child: _searchField(count, count, channel: true)),
            const SizedBox(width: 14),
            _headerButton(
              tooltip: 'Clear playlist',
              active: false,
              mark: const TrashMark(size: 16),
              onTap: () => unawaited(_clearAll()),
            ),
            const SizedBox(width: 14),
            _headerButton(
              tooltip: 'Close playlist',
              active: false,
              mark: Transform.rotate(
                angle: 0.7853981633974483,
                child: const PlusMark(size: 16),
              ),
              onTap: () => _panel.closePlaylist(),
            ),
          ],
        ),
      ),
    );
  }

  /// The group-by button: ONE stable mark plus a four-option pill below
  /// it — the mark never morphs into four glyphs (§10.2). It stays
  /// active (glowing) while the pill is open and drops to quiet ink
  /// while a search suspends the grouping (§10.3).
  Widget _groupByButton(bool searching) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _pill,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder:
          (BuildContext context, OverlayChildLayoutInfo info) {
        return _GroupPillOverlay(
          childPaintTransform: info.childPaintTransform,
          childSize: info.childSize,
          animation: _pillAnim,
          mode: _groupMode,
          onDismiss: _closePill,
          onChoose: _chooseMode,
        );
      },
      child: SaluIconButton(
        tooltip: _pillOpen ? null : 'Group by',
        size: 30,
        active: _pillOpen,
        onTap: _togglePill,
        child: GroupByMark(size: 18, quiet: searching),
      ),
    );
  }

  Widget _repeatButton() {
    return ValueListenableBuilder<RepeatMode>(
      valueListenable: _player.repeatMode,
      builder: (BuildContext context, RepeatMode mode, Widget? _) {
        final bool off = mode == RepeatMode.off;
        final String tip = switch (mode) {
          RepeatMode.off => 'Repeat off',
          RepeatMode.all => 'Repeat all',
          RepeatMode.one => 'Repeat one',
        };
        return _headerButton(
          tooltip: tip,
          active: !off,
          mark: RepeatMark(size: 18, quiet: off, bead: mode == RepeatMode.one),
          onTap: () => unawaited(_player.cycleRepeat()),
        );
      },
    );
  }

  Widget _shuffleButton() {
    // Listens to BOTH notifiers: the suspend visual answers the repeat
    // mode as well as the shuffle state (§8 item 18 — cycling repeat to
    // one must dim this mark immediately, without waiting for a
    // shuffle toggle or a queue change to rebuild it).
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _player.shuffleOn,
        _player.repeatMode,
      ]),
      builder: (BuildContext context, Widget? _) {
        final bool on = _player.shuffleOn.value;
        // Repeat-one suspends shuffle: it keeps its *state* but drops to
        // quiet ink and loses its glow (§5's decision table).
        final bool suspended = on && _player.repeatMode.value == RepeatMode.one;
        return _headerButton(
          tooltip: 'Shuffle',
          active: on && !suspended,
          mark: ShuffleMark(size: 18, quiet: suspended || !on),
          onTap: () => unawaited(_player.toggleShuffle()),
        );
      },
    );
  }

  Widget _headerButton({
    required String tooltip,
    required bool active,
    required Widget mark,
    required VoidCallback onTap,
  }) {
    return SaluIconButton(
      tooltip: tooltip,
      size: 30,
      active: active,
      onTap: onTap,
      child: mark,
    );
  }

  Widget _searchField(int total, int shown, {bool channel = false}) {
    final bool noMatch = _query.isNotEmpty && shown == 0;
    // The count lives INSIDE the field (owner) — local: `14` or `9 /
    // 14`; channel: total-only, bright while the progressive load still
    // grows it (the stale-results flag — settled counts sit grey).
    final bool stale = channel && _loads.loading.value;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: noMatch
              ? AppColors.iconIdle.withAlpha(120)
              : Colors.transparent,
        ),
      ),
      child: Focus(
        onKeyEvent: _onFieldKey,
        child: Row(
          children: <Widget>[
            // The magnifier names the field — no placeholder text (rule 1).
            SizedBox(
              width: 18,
              child: IconTheme.merge(
                data: IconThemeData(
                  color: noMatch
                      ? AppColors.iconIdle.withAlpha(95)
                      : AppColors.iconIdle,
                ),
                child: const MagnifierMark(size: 14),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                ),
                cursorColor: AppColors.textPrimary,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (String value) =>
                    setState(() => _query = value.trim()),
              ),
            ),
            Text(
              channel
                  ? '$total'
                  : (_query.isEmpty ? '$total' : '$shown / $total'),
              style: TextStyle(
                color: stale
                    ? AppColors.textPrimary
                    : const Color(0xFF7C7C80),
                fontSize: 10,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures()
                ],
              ),
            ),
            // ✕ clears the text — only while there is some.
            if (_query.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              _clearX(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clearX() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _clearQuery,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: IconTheme.merge(
            data: const IconThemeData(color: AppColors.iconIdle),
            child: Transform.rotate(
              angle: 0.7853981633974483,
              child: const PlusMark(size: 12),
            ),
          ),
        ),
      ),
    );
  }

  /// Esc precedence, field-scoped (playlist_imp.md §6): field focused WITH
  /// text → clear it and keep focus; empty → release focus. Consumed both
  /// ways so Esc never bubbles up to close the panel while typing. §4.5.
  /// (The group-by pill owns Esc while it is open — see its overlay —
  /// so the full order is pill → field → panel.)
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_query.isNotEmpty) {
        _clearQuery();
      } else {
        _searchFocus.unfocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Rows ────────────────────────────────────────────────────────────

  Widget _rowsArea(List<QueueItem> items) {
    final List<int> visible = _visibleRows(items);
    if (visible.isEmpty) {
      // No match — the magnifier alone, ~30 % ink, centred (§4.5).
      return Center(
        child: IconTheme.merge(
          data: const IconThemeData(color: Color(0x4DE8E8E8)),
          child: const MagnifierMark(size: 40),
        ),
      );
    }
    final bool filterActive = _query.isNotEmpty;
    final Widget list;
    if (filterActive) {
      // A filter is a VIEW — drag reorder is disabled while it is active.
      list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: visible.length,
        itemBuilder: (BuildContext context, int i) =>
            _row(items, visible[i], canDrag: false),
      );
    } else {
      list = ReorderableListView.builder(
        scrollController: _scroll,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: visible.length,
        onReorderItem: (int oldIndex, int newIndex) {
          unawaited(_move(oldIndex, newIndex));
        },
        itemBuilder: (BuildContext context, int i) =>
            _row(items, visible[i], canDrag: true),
      );
    }

    // SALU's own thin scrollbar over a transparent track (§4.3) — never
    // the platform / Material one.
    return _SaluScrollView(controller: _scroll, child: list);
  }

  Widget _row(List<QueueItem> items, int index, {required bool canDrag}) {
    final QueueItem item = items[index];
    final bool isNow = index == _queue.index.value;
    final Widget grip = IconTheme.merge(
      data: const IconThemeData(color: AppColors.iconIdle),
      child: const GripMark(size: 16),
    );
    return _RowTile(
      key: ValueKey<String>('$index:${item.url}'),
      index: index,
      isNow: isNow,
      name: item.label,
      canDrag: canDrag,
      dragHandle: grip,
      onPlay: () => _play(index),
      onDelete: () => unawaited(_removeRow(index)),
    );
  }

  // ── Channel rows (§10.2–§10.6) ──────────────────────────────────────

  Widget _channelRowsArea(List<QueueItem> items) {
    _ensureChannelCache(items);
    final List<ChannelDescriptor> descs = _cachedDescriptors;
    if (descs.isEmpty) {
      // No match → the magnifier (§4.5); favourites-only with no
      // bookmarks → the empty bookmark (§10.3). Search wins the tie.
      final bool noMatch = _query.isNotEmpty;
      return Center(
        child: IconTheme.merge(
          data: const IconThemeData(color: Color(0x4DE8E8E8)),
          child: noMatch
              ? const MagnifierMark(size: 40)
              : const BookmarkMark(size: 40),
        ),
      );
    }
    final int now = _queue.index.value;
    final Set<String> favs = _favourites.favourites.value;
    final Widget list = ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: descs.length,
      itemExtent: _channelRowExtent,
      itemBuilder: (BuildContext context, int i) {
        final ChannelDescriptor d = descs[i];
        if (d is GroupHeadDescriptor) {
          return _ChannelGroupHead(
            key: ValueKey<String>('g:${d.key}'),
            label: d.group.label,
            count: d.group.indexes.length,
            expanded: d.expanded,
            onTap: () => setState(() {
              _openGroup = d.expanded ? null : d.key;
            }),
          );
        }
        final ChannelRowDescriptor row = d as ChannelRowDescriptor;
        final QueueItem item = items[row.index];
        return _ChannelRow(
          key: ValueKey<String>('c:${row.index}'),
          item: item,
          isNow: row.index == now,
          isFavourite: favs
              .contains(ChannelFavouritesService.channelKey(item)),
          onPlay: () => _play(row.index),
          onToggleFavourite: () => _toggleFavourite(item),
        );
      },
    );

    // The list + SALU's own thin scrollbar, the sticky group head while
    // one is pinned (§10.5), and the edge chevrons pointing at the
    // playing channel hiding off-screen (§10.6).
    //
    // `StackFit.expand` is load-bearing, not decoration: a loose Stack
    // hands its non-positioned children `constraints.loosen()`, and the
    // rows view under it would then be free to size itself to nothing.
    // The local list reaches its scroll view straight from `Expanded`
    // (tight constraints); this one must hand down the same tightness.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _SaluScrollView(controller: _scroll, child: list),
        _stickyHead(items),
        _edgeChevrons(items),
      ],
    );
  }

  /// The sticky group head (§10.5): once the open group's real head
  /// scrolls off the top, a pinned copy takes its place (same tap — it
  /// collapses the group) until the next head pushes it off, the
  /// approved preview's motion. Occludes with the panel's own glass.
  Widget _stickyHead(List<QueueItem> items) {
    if (_query.isNotEmpty ||
        _groupMode == ChannelGroupMode.flat ||
        _openGroup == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: _scroll,
      builder: (BuildContext context, Widget? _) {
        final _PinnedHead? pinned = _pinnedHead(items);
        if (pinned == null) return const SizedBox.shrink();
        return Positioned(
          top: pinned.dy,
          left: 0,
          right: 8,
          height: _channelRowExtent,
          child: _PinnedHeadTile(
            label: pinned.group.label,
            count: pinned.group.indexes.length,
            onTap: () => setState(() => _openGroup = null),
          ),
        );
      },
    );
  }

  /// The pinned head's geometry, or `null` while the real head is still
  /// visible (or the scroll metrics are not ready yet).
  _PinnedHead? _pinnedHead(List<QueueItem> items) {
    // Flat (and a search, which flattens) has no heads at all — answer
    // before the scan. The edge chevrons ask this on every scroll tick,
    // and a full sweep of 50 000 descriptors per frame is exactly the
    // budget §10.10c exists to protect.
    if (_query.isNotEmpty ||
        _groupMode == ChannelGroupMode.flat ||
        _openGroup == null) {
      return null;
    }
    _ensureChannelCache(items);
    int headPos = -1;
    ChannelGroup? group;
    for (int i = 0; i < _cachedDescriptors.length; i++) {
      final ChannelDescriptor d = _cachedDescriptors[i];
      if (d is GroupHeadDescriptor && d.key == _openGroup) {
        headPos = i;
        group = d.group;
        break;
      }
    }
    if (headPos < 0 || group == null) return null;
    if (!_scroll.hasClients) return null;
    final ScrollPosition p = _scroll.position;
    if (!p.hasPixels || !p.hasViewportDimension || !p.hasContentDimensions) {
      return null;
    }
    final double headTop = 2 + headPos * _channelRowExtent - p.pixels;
    if (headTop >= 2) return null; // the real head is still visible
    double dy = 2;
    final double nextTop =
        2 + (headPos + 1 + group.indexes.length) * _channelRowExtent - p.pixels;
    if (nextTop < 2 + _channelRowExtent) dy = nextTop - _channelRowExtent;
    return _PinnedHead(dy: dy, group: group);
  }

  /// The list-edge chevrons (§10.6): while the playing channel (or its
  /// group head) hides above or below the viewport, a small glass chip
  /// at that edge points at it. A press reveals — never touching the
  /// filters (the chevrons never clear anything).
  Widget _edgeChevrons(List<QueueItem> items) {
    return ListenableBuilder(
      listenable: _scroll,
      builder: (BuildContext context, Widget? _) {
        final int? target = _revealTargetPos(items);
        if (target == null) return const SizedBox.shrink();
        if (!_scroll.hasClients) return const SizedBox.shrink();
        final ScrollPosition p = _scroll.position;
        if (!p.hasPixels ||
            !p.hasViewportDimension ||
            !p.hasContentDimensions) {
          return const SizedBox.shrink();
        }
        final double rowTop = 2 + target * _channelRowExtent;
        final double top = p.pixels;
        final double bottom = top + p.viewportDimension;
        // On screen (the reveal's own 6 px slack)? No chevrons.
        if (rowTop >= top + 6 &&
            rowTop + _channelRowExtent <= bottom - 6) {
          return const SizedBox.shrink();
        }
        final bool above = rowTop < top + 6;
        // A pinned head owns the top edge — the chip drops below it.
        final bool pinned = _pinnedHead(items) != null;
        return Positioned(
          top: above ? (pinned ? 6 + _channelRowExtent + 2 : 6) : null,
          bottom: above ? null : 6,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.center,
            child: _RevealChip(
              up: above,
              onTap: () {
                _userScrollTimer?.cancel();
                _userScrolled = false;
                _revealChannel(items, animate: true, force: true);
              },
            ),
          ),
        );
      },
    );
  }
}

/// A pinned sticky head: its top offset and the group it names.
class _PinnedHead {
  const _PinnedHead({required this.dy, required this.group});

  final double dy;
  final ChannelGroup group;
}

// ── Row tile ────────────────────────────────────────────────────────────

/// One 36-px queue row: `≡ grip · [now chevron] · name · (hover) 🗑`.
/// Click = play; hover washes; the 🗑 fades in on hover, playing row only
/// shows its head; other rows' names sit quiet (§4.3).
class _RowTile extends StatefulWidget {
  const _RowTile({
    super.key,
    required this.index,
    required this.isNow,
    required this.name,
    required this.canDrag,
    required this.dragHandle,
    required this.onPlay,
    required this.onDelete,
  });

  final int index;
  final bool isNow;
  final String name;
  final bool canDrag;
  final Widget dragHandle;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  State<_RowTile> createState() => _RowTileState();
}

class _RowTileState extends State<_RowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Widget leading = widget.canDrag
        ? ReorderableDragStartListener(
            index: widget.index, child: widget.dragHandle)
        : widget.dragHandle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPlay,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0x0EFFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: <Widget>[
                IconTheme.merge(
                  data: const IconThemeData(color: AppColors.iconIdle),
                  child: leading,
                ),
                const SizedBox(width: 8),
                // The solid chevron on the playing row only (§2's head).
                SizedBox(
                  width: 12,
                  child: widget.isNow
                      ? IconTheme.merge(
                          data:
                              const IconThemeData(color: AppColors.textPrimary),
                          child: const PlayMark(size: 12),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isNow
                          ? AppColors.textPrimary
                          : const Color(0xFFC9C9CC),
                      fontSize: 13,
                      fontWeight:
                          widget.isNow ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                // 🗑 — fades in on hover only (§4.3, URL rows' pattern).
                // IgnorePointer while hidden, so the invisible mark never
                // eats a click meant for the row (play).
                IgnorePointer(
                  ignoring: !_hovered,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IconTheme.merge(
                            data: const IconThemeData(color: AppColors.iconIdle),
                            child: const TrashMark(size: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Channel rows (§10.2–§10.6) ──────────────────────────────────────────

/// One 38-px channel row: `[now chevron] · 24-px logo · name · bookmark`.
///
/// Click = zap; hover washes; the bookmark is solid and always visible
/// when saved, an outline fading in on hover otherwise (§10.3). The logo
/// slot keeps the row's pitch whether the artwork arrives or not (§10.4) —
/// and a missing image is simply an empty slot, never a spinner or an
/// error mark. No grip, no trash: channel rows have neither drag nor
/// delete (M-4 · §10.4).
class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    super.key,
    required this.item,
    required this.isNow,
    required this.isFavourite,
    required this.onPlay,
    required this.onToggleFavourite,
  });

  final QueueItem item;
  final bool isNow;
  final bool isFavourite;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavourite;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final QueueItem item = widget.item;
    // Saved = solid, always visible; unsaved = outline on hover only.
    final bool showBookmark = widget.isFavourite || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPlay,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x0EFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: <Widget>[
              // The solid chevron on the playing row only (§2's head).
              SizedBox(
                width: 12,
                child: widget.isNow
                    ? IconTheme.merge(
                        data:
                            const IconThemeData(color: AppColors.textPrimary),
                        child: const PlayMark(size: 12),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              // The logo binds to its ADDRESS, never the recycled row —
              // fast scrolling cannot mis-attach an image (§10.4).
              ChannelLogo(
                key: ValueKey<String>(item.logoUrl ?? ''),
                logoUrl: item.logoUrl,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isNow
                        ? AppColors.textPrimary
                        : const Color(0xFFC9C9CC),
                    fontSize: 13,
                    fontWeight:
                        widget.isNow ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              // Bookmark — IgnorePointer while hidden, so the invisible
              // mark never eats a click meant for the row (zap).
              IgnorePointer(
                ignoring: !showBookmark,
                child: AnimatedOpacity(
                  opacity: showBookmark ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleFavourite,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconTheme.merge(
                          data: const IconThemeData(
                              color: AppColors.textPrimary),
                          child: BookmarkMark(
                            size: 15,
                            filled: widget.isFavourite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 38-px group head (§10.5): `twist · name · count`. Click toggles
/// the accordion (at most one group opens); the twist rotates 90° down
/// as the group opens.
class _ChannelGroupHead extends StatefulWidget {
  const _ChannelGroupHead({
    super.key,
    required this.label,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ChannelGroupHead> createState() => _ChannelGroupHeadState();
}

class _ChannelGroupHeadState extends State<_ChannelGroupHead> {
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
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x0EFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: <Widget>[
              GroupTwistMark(size: 14, expanded: widget.expanded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${widget.count}',
                style: const TextStyle(
                  color: Color(0xFF7C7C80),
                  fontSize: 11,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned sticky head: the head's content over the panel's own glass
/// (blur 18 + glass colour), so the rows scrolling underneath never ghost
/// through (§10.5).
class _PinnedHeadTile extends StatelessWidget {
  const _PinnedHeadTile({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: ColoredBox(
          color: AppColors.glass,
          child: _ChannelGroupHead(
            label: label,
            count: count,
            expanded: true,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// A list-edge reveal chip (§10.6): a small glass chip with the chevron
/// pointing at the playing channel hiding above ([up]) or below it.
class _RevealChip extends StatelessWidget {
  const _RevealChip({required this.up, required this.onTap});

  final bool up;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassCapsule(
          radius: 10,
          padding: const EdgeInsets.all(6),
          child: RevealChevronMark(size: 15, up: up),
        ),
      ),
    );
  }
}

// ── Group-by pill (§10.2) ───────────────────────────────────────────────

/// The floating pill: a full-screen dismiss layer + the option list
/// anchored below the group-by button — the Open pill's recipe
/// ([OverlayPortal.overlayChildLayoutBuilder] on the root overlay, so
/// the pill tracks the button without a [CompositedTransformFollower]).
class _GroupPillOverlay extends StatelessWidget {
  const _GroupPillOverlay({
    required this.childPaintTransform,
    required this.childSize,
    required this.animation,
    required this.mode,
    required this.onDismiss,
    required this.onChoose,
  });

  final Matrix4 childPaintTransform;
  final Size childSize;
  final Animation<double> animation;

  /// The panel's mode when the pill opened — a snapshot is correct: a
  /// choice closes the pill, so the selection cannot drift while it is
  /// up. (The overlay builds outside the panel's subtree, so the mode
  /// arrives as a plain value, not an inherited lookup.)
  final ChannelGroupMode mode;
  final VoidCallback onDismiss;
  final ValueChanged<ChannelGroupMode> onChoose;

  @override
  Widget build(BuildContext context) {
    // Mirrors RawAutocomplete's own guard: a zero determinant means the
    // button isn't currently visible/laid out (e.g. mid-transition), so
    // there is nothing sane to anchor the pill to yet.
    if (childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final CurvedAnimation curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Focus(
      // Esc closes (the pill owns Esc while it is open — the full order
      // is pill → field → panel). Every other key is left alone.
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: <Widget>[
          // Click-outside-to-close. Opaque: the closing click must never
          // fall through and zap a channel underneath.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onSecondaryTap: onDismiss,
            ),
          ),
          // Re-anchors this subtree to the button's on-screen box —
          // (0, 0) here is the button's top-left corner — then drops the
          // pill 6px below it.
          Transform(
            transform: childPaintTransform,
            child: Padding(
              padding: EdgeInsets.only(top: childSize.height + 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                    alignment: Alignment.topLeft,
                    child: _GroupPillBody(mode: mode, onChoose: onChoose),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill's four options — Flat, Category, Language, Country (§10.2).
/// The selected mode sits bright (never a checkmark — the family's
/// grammar is *one mark, modified*); a mode the playlist cannot offer is
/// dimmed and dead. Availability answers the live queue, so a mode can
/// light up mid-load if a late batch brings the metadata.
class _GroupPillBody extends StatelessWidget {
  const _GroupPillBody({required this.mode, required this.onChoose});

  final ChannelGroupMode mode;
  final ValueChanged<ChannelGroupMode> onChoose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<QueueItem>>(
      valueListenable: QueueService.instance.items,
      builder: (BuildContext context, List<QueueItem> items, Widget? _) {
        final Map<ChannelGroupMode, bool> available =
            ChannelGrouping.availability(items);
        return GlassCapsule(
          radius: 12,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 172,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <ChannelGroupMode>[
                ChannelGroupMode.flat,
                ChannelGroupMode.category,
                ChannelGroupMode.language,
                ChannelGroupMode.country,
              ]
                  .map((ChannelGroupMode m) => _GroupPillOption(
                        mode: m,
                        selected: m == mode,
                        available: available[m] ?? false,
                        onChoose: onChoose,
                      ))
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}

/// One pill option: the mode's mark + its name. Selected sits bright;
/// unavailable sits dimmed and dead.
class _GroupPillOption extends StatefulWidget {
  const _GroupPillOption({
    required this.mode,
    required this.selected,
    required this.available,
    required this.onChoose,
  });

  final ChannelGroupMode mode;
  final bool selected;
  final bool available;
  final ValueChanged<ChannelGroupMode> onChoose;

  @override
  State<_GroupPillOption> createState() => _GroupPillOptionState();
}

class _GroupPillOptionState extends State<_GroupPillOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.available;
    final bool bright = widget.selected;
    final Widget mark = switch (widget.mode) {
      ChannelGroupMode.flat => const FlatMark(size: 18),
      ChannelGroupMode.category => const CategoryMark(size: 18),
      ChannelGroupMode.language => const LanguageMark(size: 18),
      ChannelGroupMode.country => const CountryMark(size: 18),
    };
    final String label = switch (widget.mode) {
      ChannelGroupMode.flat => 'Flat',
      ChannelGroupMode.category => 'Category',
      ChannelGroupMode.language => 'Language',
      ChannelGroupMode.country => 'Country',
    };
    return IgnorePointer(
      ignoring: !enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChoose(widget.mode) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: (bright || (enabled && _hovered)) && enabled
                    ? const Color(0x0EFFFFFF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  IconTheme.merge(
                    data: IconThemeData(
                      color: bright
                          ? AppColors.textPrimary
                          : AppColors.iconIdle,
                    ),
                    child: mark,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: bright
                          ? AppColors.textPrimary
                          : const Color(0xFFC9C9CC),
                      fontSize: 12.5,
                      fontWeight:
                          bright ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── SALU's own scrollbar ────────────────────────────────────────────────

/// Wraps the rows scroll view and paints SALU's own thin rounded thumb
/// over a transparent track (§4.3) — never the Material / platform
/// scrollbar, which is suppressed via [_NoScrollbars].
///
/// The thumb is driven off [controller] ([ListenableBuilder]) so it only
/// repaints on real scroll/geometry changes — never on a scroll
/// notification during a layout pass.
///
/// The scroll view is the Stack's ONE non-positioned child, so it — not
/// the thumb's zero-sized placeholder — decides this widget's size.
/// `RenderStack` measures itself over its non-positioned children only,
/// so with the list positioned instead, a caller that passes loose
/// constraints (any `Stack` above us) leaves `minHeight == 0` and the
/// whole rows area measures 0 × 0; `Positioned.fill` then lays the list
/// out at `tightFor(0, 0)` and it paints nothing at all. That was the
/// empty channel list §10.2's rows area showed. A viewport is
/// `sizedByParent` with `size == constraints.biggest`, so as the
/// non-positioned child it fills any bounded box, loose or tight — the
/// local (tight) caller measures exactly as it did before.
class _SaluScrollView extends StatelessWidget {
  const _SaluScrollView({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _NoScrollbars(),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double h = constraints.maxHeight;
          return Stack(
            children: <Widget>[
              child,
              // The thumb — a thin rounded rule on a transparent track.
              ListenableBuilder(
                listenable: controller,
                builder: (BuildContext context, Widget? _) {
                  // A freshly attached (or mid-layout) scroll position can
                  // report clients before its pixels/content dimensions
                  // exist — sampling them then throws a null check. So wait
                  // until every metric is present before drawing the thumb.
                  if (!controller.hasClients) return const SizedBox.shrink();
                  final ScrollPosition p = controller.position;
                  if (!p.hasPixels ||
                      !p.hasViewportDimension ||
                      !p.hasContentDimensions) {
                    return const SizedBox.shrink();
                  }
                  final double viewport = p.viewportDimension;
                  final double max = p.maxScrollExtent;
                  if (max <= 0 || viewport <= 0) {
                    return const SizedBox.shrink();
                  }
                  double thumbH = h * (viewport / (viewport + max));
                  if (thumbH < 24) thumbH = 24;
                  final double travel = h - thumbH;
                  double y = travel > 0 ? travel * (p.pixels / max) : 0;
                  if (y < 0) y = 0;
                  if (y > travel) y = travel;
                  return Positioned(
                    right: 2,
                    top: y,
                    height: thumbH,
                    child: Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: const Color(0x29FFFFFF), // ~ .16
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A [ScrollBehavior] that adds no automatic scrollbar — SALU's own thin
/// thumb is painted by [_SaluScrollView] instead (§4.3).
class _NoScrollbars extends ScrollBehavior {
  const _NoScrollbars();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// Clips a surface with a single rounded top-left corner (the rest square).
class _TopLeftRadius extends CustomClipper<Path> {
  const _TopLeftRadius(this.radius);

  final double radius;

  @override
  Path getClip(Size size) {
    final double r = radius;
    return Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_TopLeftRadius oldClipper) => oldClipper.radius != radius;
}
