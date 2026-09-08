import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../osd/osd_controller.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// SALU's slide-out playlist panel (playlist_imp.md §4) — the *view* over
/// the queue that the control-row Playlist mark opens.
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
class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({super.key});

  /// Panel width — matches the interactive study (322 px).
  static const double width = 322;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel>
    with SingleTickerProviderStateMixin {
  final PanelService _panel = PanelService.instance;
  final QueueService _queue = QueueService.instance;
  final PlayerService _player = PlayerService.instance;

  /// Fixed pitch of a playlist row (drag reorder needs exact extents).
  static const double _rowExtent = 40;

  late final AnimationController _open;
  late final Animation<double> _curve;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  final ScrollController _scroll = ScrollController();
  bool _programmatic = false;
  bool _userScrolled = false;
  Timer? _userScrollTimer;

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
    _panel.playlistOpen.addListener(_onOpenChanged);
    _queue.index.addListener(_onIndexChanged);
    _scroll.addListener(_onScroll);
    // Keep the panel reflecting the freshly opened (or cleared) queue.
    _queue.items.addListener(_onItemsChanged);
  }

  @override
  void dispose() {
    _panel.playlistOpen.removeListener(_onOpenChanged);
    _queue.index.removeListener(_onIndexChanged);
    _queue.items.removeListener(_onItemsChanged);
    _scroll.removeListener(_onScroll);
    _userScrollTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _open.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (_panel.playlistOpen.value) {
      _open.forward();
      // Entrance jump — ignore any stale scroll suppression.
      _revealPlaying(animate: false, force: true);
    } else {
      _open.reverse();
    }
    setState(() {});
  }

  void _onItemsChanged() => setState(() {});

  void _onIndexChanged() {
    setState(() {});
    // A deliberate index change (auto-advance, Next, Previous, row click)
    // must always reveal the playing row. Per §4.3 the "don't fight the
    // user" suppression is lifted on the next index change, so we clear
    // it here and force the reveal even if a recent scroll had armed it.
    if (_panel.playlistOpen.value) {
      _userScrollTimer?.cancel();
      _userScrolled = false;
      _revealPlaying(animate: true, force: true);
    }
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

  // ── Actions (each shows a 5 s Undo toast when it changed the queue) ──

  void _play(int index) {
    _wakeFocusRelease();
    unawaited(_player.playIndex(index));
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
    final bool hasQueue = items.isNotEmpty;
    if (!hasQueue) return _emptyState();

    final int count = items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(count),
        Expanded(child: _rowsArea(items)),
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
    return ValueListenableBuilder<bool>(
      valueListenable: _player.shuffleOn,
      builder: (BuildContext context, bool on, Widget? _) {
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

  Widget _searchField(int total, int shown) {
    final bool noMatch = _query.isNotEmpty && shown == 0;
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
            // The count lives INSIDE the field (owner) — `14` or `9 / 14`.
            Text(
              _query.isEmpty ? '$total' : '$shown / $total',
              style: const TextStyle(
                color: Color(0xFF7C7C80),
                fontSize: 10,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
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

// ── SALU's own scrollbar ────────────────────────────────────────────────

/// Wraps the rows scroll view and paints SALU's own thin rounded thumb
/// over a transparent track (§4.3) — never the Material / platform
/// scrollbar, which is suppressed via [_NoScrollbars].
///
/// The thumb is driven off [controller] ([ListenableBuilder]) so it only
/// repaints on real scroll/geometry changes — never on a scroll
/// notification during a layout pass.
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
              Positioned.fill(child: child),
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
