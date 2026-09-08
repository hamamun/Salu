import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'media_utils.dart';
import 'queue_item.dart';

export 'queue_item.dart';

/// SALU's own play queue — the source of truth above the engine.
///
/// media_kit's `Player.stop()` clears mpv's internal playlist, so a queue
/// that survives Stop (Stop ≠ Start Over: the queue stays parked) has to
/// live here. In local mode `PlayerService` hands mpv the full playlist
/// while an item is loaded and mirrors mpv's index into this service; in
/// channel mode the engine holds one media and this service alone knows
/// the list (playlist_imp.md §10.10a). After a Stop the queue is re-opened
/// at the target index.
///
/// The queue is ONE RAM-only list of immutable [QueueItem] records
/// (playlist_imp.md §10.0 — point 2 FINAL): local files carry a path only,
/// m3u channels add their details. There is no second stored URL list.
///
/// Every local path is held in ONE canonical spelling
/// (`MediaUtils.canonicalPath` — playlist_imp.md §5), applied on the way in,
/// so string comparisons with `PlayerService.currentPath` and the resume
/// store always agree.
class QueueService {
  QueueService._internal();

  /// The one and only queue for the whole app.
  static final QueueService instance = QueueService._internal();

  /// Ordered entries of the queue (canonical local paths or stream URLs,
  /// plus a channel's details). Always an unmodifiable list; every
  /// mutation publishes a new one exactly once.
  final ValueNotifier<List<QueueItem>> items =
      ValueNotifier<List<QueueItem>>(const <QueueItem>[]);

  /// Index of the current item (`-1` while nothing is queued).
  final ValueNotifier<int> index = ValueNotifier<int>(-1);

  /// Read-only URL view of [items], materialised lazily and cached per
  /// published list — a *compatibility view*, not a second stored list
  /// (§10.0). Local-mode code that genuinely needs the strings (the
  /// engine playlist, Undo snapshots, `indexOf` by path) reads this;
  /// channel-mode hot paths (zapping) never touch it.
  List<String> get paths {
    final List<QueueItem> list = items.value;
    if (!identical(list, _pathsSource)) {
      _pathsSource = list;
      _pathsView = List<String>.unmodifiable(
          list.map((QueueItem i) => i.url));
    }
    return _pathsView;
  }

  List<QueueItem>? _pathsSource;
  List<String> _pathsView = const <String>[];

  /// Number of queued entries.
  int get length => items.value.length;

  bool get hasQueue => items.value.isNotEmpty;

  bool get hasCurrent {
    final int i = index.value;
    return i >= 0 && i < items.value.length;
  }

  /// Whether an item exists after the current one (Next's enable state).
  bool get hasNext {
    final int i = index.value;
    return i >= 0 && i < items.value.length - 1;
  }

  /// The current entry, or `null` while nothing is queued.
  QueueItem? get current => hasCurrent ? items.value[index.value] : null;

  /// Entry at [i], or `null` when out of range.
  QueueItem? itemAt(int i) =>
      i >= 0 && i < items.value.length ? items.value[i] : null;

  /// Whether the loaded list is a channel list (playlist_imp.md §10.0).
  /// Derived from the data — a parsed channel always carries a label —
  /// so there is no mode flag to keep in step. Cached per published list
  /// (a 50 000-row scan must not run on every rebuild).
  bool get isChannelList {
    final List<QueueItem> list = items.value;
    if (!identical(list, _channelSource)) {
      _channelSource = list;
      _channelView = list.any((QueueItem i) => i.name != null);
    }
    return _channelView;
  }

  List<QueueItem>? _channelSource;
  bool _channelView = false;

  /// Position of the entry whose URL is [url] (`-1` when absent).
  int indexOfUrl(String url) {
    final List<QueueItem> list = items.value;
    for (int i = 0; i < list.length; i++) {
      if (list[i].url == url) return i;
    }
    return -1;
  }

  static QueueItem _canonicalItem(QueueItem item) =>
      item.withUrl(MediaUtils.canonicalPath(item.url));

  static List<QueueItem> _canonicalize(List<QueueItem> list) =>
      list.map(_canonicalItem).toList(growable: false);

  static List<QueueItem> _fromPaths(List<String> list) => list
      .map((String p) => QueueItem.local(MediaUtils.canonicalPath(p)))
      .toList(growable: false);

  /// Replaces the whole queue with local rows and points [index] at the
  /// start item (Phase A entry point — every path becomes a local
  /// [QueueItem]). A fresh queue resets the shuffle pass (§5).
  void setQueue(List<String> list, int startIndex) =>
      setItems(_fromPaths(list), startIndex);

  /// Replaces the whole queue with [list] (local rows or channels — the
  /// switch between sources is just this call with a different list,
  /// §10.0) and points [index] at the start item.
  void setItems(List<QueueItem> list, int startIndex) {
    final List<QueueItem> next = _canonicalize(list);
    items.value = List<QueueItem>.unmodifiable(next);
    index.value =
        next.isEmpty ? -1 : startIndex.clamp(0, next.length - 1).toInt();
    _resetPass();
  }

  /// Mirrors mpv's index while an item is loaded (auto-advance etc.).
  void setIndex(int i) {
    if (i >= 0 && i < items.value.length && index.value != i) {
      index.value = i;
    }
  }

  /// Empties the queue (a fresh open replaces it; nothing calls this on
  /// Stop — Stop parks the queue, it never clears it).
  void clear() {
    items.value = const <QueueItem>[];
    index.value = -1;
    _resetPass();
  }

  // ── Phase A mutations (each fires items.value once) ───────────────────

  /// Appends local rows at the end, in the order given (blocks are
  /// already sorted at the boundary). Never disturbs the current item.
  void append(List<String> paths) {
    if (paths.isEmpty) return;
    final List<QueueItem> next =
        List<QueueItem>.of(items.value)..addAll(_fromPaths(paths));
    items.value = List<QueueItem>.unmodifiable(next);
    _resetPass();
  }

  /// Inserts one entry at [index] (0-based final position, clamped).
  /// The current index shifts up when the insert lands at or before it.
  void insert(int index, QueueItem item) {
    final List<QueueItem> next = List<QueueItem>.of(items.value);
    final int at = index.clamp(0, next.length).toInt();
    next.insert(at, _canonicalItem(item));
    items.value = List<QueueItem>.unmodifiable(next);
    final int cur = this.index.value;
    if (cur >= 0) {
      if (at <= cur) this.index.value = cur + 1;
    }
    _resetPass();
  }

  /// Removes the entry at [index]; returns it, or `null` when the index
  /// is out of range.
  ///
  /// Keeps [index] honest: deleting an item *before* the current one shifts
  /// it down one; deleting the current row leaves the pointer on the item
  /// that slid into its place (`-1` when nothing is left) — the engine's
  /// follow-up (next → previous → initial state) is `PlayerService`'s job.
  QueueItem? removeAt(int index) {
    final List<QueueItem> current = items.value;
    if (index < 0 || index >= current.length) return null;
    final int cur = this.index.value;
    final QueueItem removed = current[index];
    final List<QueueItem> next = List<QueueItem>.of(current)
      ..removeAt(index);
    items.value = List<QueueItem>.unmodifiable(next);
    if (cur == index) {
      this.index.value = index < next.length ? index : -1;
    } else if (index < cur) {
      this.index.value = cur - 1;
    }
    _resetPass();
    return removed;
  }

  /// Moves the entry at [from] so it takes the place of [to] (final
  /// position semantics, matching the engine's `player.move`). The current
  /// pointer follows the *same entry* through the move.
  bool move(int from, int to) {
    final List<QueueItem> current = items.value;
    if (from < 0 || from >= current.length) return false;
    final int cur = index.value;
    final QueueItem? currentItem = (cur >= 0 && cur < current.length)
        ? current[cur]
        : null;
    final QueueItem item = current[from];
    final List<QueueItem> next = List<QueueItem>.of(current)
      ..removeAt(from);
    final int at = to.clamp(0, next.length).toInt();
    next.insert(at, item);
    items.value = List<QueueItem>.unmodifiable(next);
    index.value = currentItem == null
        ? -1
        : next.indexWhere((QueueItem i) => identical(i, currentItem));
    _resetPass();
    return true;
  }

  // ── Shuffle-pass bookkeeping (playlist_imp.md §5) ────────────────────
  //
  // SALU owns the shuffle: mpv's playlist order is never touched, so the
  // visible list order never changes. A *pass* = every item heard once, in
  // random order; `_heard` keeps the play-order history that makes |<<
  // honest while shuffling.
  //
  // Adding, removing, moving, clearing or a fresh open resets the pass
  // (any mutation invalidates the remaining set).

  final math.Random _rng = math.Random();

  /// Not-yet-heard indexes of the current pass, in play order.
  final List<int> _pass = <int>[];

  /// Whether [_pass] was seeded since the last reset.
  bool _passSeeded = false;

  /// The index a fresh pass must not *lead* with (the one just heard).
  int? _excludeIndex;

  /// Play-order history — the last element is what is playing now.
  final List<int> _heard = <int>[];

  /// Whether shuffle semantics apply at all (on AND more than one item).
  bool get shuffleActive =>
      items.value.length > 1;

  void _resetPass() {
    _pass.clear();
    _passSeeded = false;
    _excludeIndex = null;
    _heard.clear();
  }

  /// Records that [index] was heard (removes it from the remaining pass,
  /// pushes it onto the history). Consecutive duplicates are collapsed —
  /// recording the same row twice in a row is the same play instance.
  void recordPlayed(int index) {
    if (index < 0 || index >= items.value.length) return;
    _pass.remove(index);
    _excludeIndex = index;
    if (_heard.isEmpty || _heard.last != index) _heard.add(index);
  }

  /// The index heard just before the current one (`null` when nothing was
  /// heard before) — what `|<<` should return to during shuffle. Read
  /// through [PlayerService.previousRestartsThisItem] so the action and
  /// the OSD card can never disagree.
  int? get peekPreviousHeard =>
      _heard.length >= 2 ? _heard[_heard.length - 2] : null;

  /// Seeds the remaining pass with every index except [exclude] — a fresh
  /// pass never leads with the item that just ended. Call before the first
  /// draw after a reset.
  void seedShufflePass() {
    final int count = items.value.length;
    if (count <= 0) return;
    final int exclude = _excludeIndex ??
        (index.value >= 0 && index.value < count ? index.value : -1);
    _pass
      ..clear()
      ..addAll(List<int>.generate(count, (int i) => i));
    if (exclude >= 0 && _pass.length > 1) _pass.remove(exclude);
    _pass.shuffle(_rng);
    _passSeeded = true;
  }

  /// The next shuffled pick, or `null` when the current pass is exhausted
  /// (repeat off → the caller parks the queue; repeat all → the caller
  /// seeds a fresh pass).
  int? takeNextShuffle() {
    if (!_passSeeded) seedShufflePass();
    if (_pass.isEmpty) return null;
    final int pick = _pass.removeAt(0);
    recordPlayed(pick);
    return pick;
  }

  /// Starts a brand-new pass (used when the pass is exhausted and the user
  /// or repeat-all asks for more).
  void startNewShufflePass() {
    _passSeeded = false;
    seedShufflePass();
  }

  /// Resets the whole shuffle bookkeeping (a fresh open, a clear).
  void resetShuffleState() => _resetPass();
}

/// Playlist row that carries the chevron: position in thirds, `-1` when
/// the queue is empty (playlist_imp.md §1, decision 3). Lives next to
/// the queue so the control-row mark and the panel can never disagree.
///
/// `count = 5` → rows `0,0,1,1,2` · `count = 3` → rows `0,1,2` ·
/// `count = 1` → row `0`.
int playlistRowOf(int index, int count) => count <= 0 || index < 0
    ? -1
    : (index * 3 ~/ count).clamp(0, 2).toInt();
