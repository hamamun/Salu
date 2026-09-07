import 'package:flutter/foundation.dart';

import 'media_utils.dart';

/// One queue entry (playlist_imp.md §10.0 — the settled data model).
///
/// Local files fill [url] only; m3u channels fill the rest. There is ONE
/// list of objects — no parallel metadata table, no mode flag — so local
/// playback stays byte-identical to before and switching sources is just
/// `setQueue(...)` with a different list.
@immutable
class QueueItem {
  const QueueItem(
    this.url, {
    this.name,
    this.group,
    this.language,
    this.country,
    this.chno,
    this.tvgId,
    this.searchKey,
  });

  /// What mpv is handed — the only field local mode needs.
  final String url;

  /// m3u display name; null → derive from the path.
  final String? name;

  /// m3u attributes (null for local files).
  final String? group, language, country, chno, tvgId;

  /// Precomputed lowercase `name + group` search key (§10.10c — naive
  /// per-keystroke lowercasing is banned). Null for local files; local
  /// filtering lowercases the derived title.
  final String? searchKey;

  /// The row title — the playlist's own display name wins (it must never
  /// be overwritten by mpv's stream metadata), else derived from the path.
  String get title => name ?? MediaUtils.displayName(url);
}

/// Playlist row that carries the chevron: position in thirds, `-1` when
/// the queue is empty (playlist_imp.md §1, decision 3).
int playlistRowOf(int index, int count) => count <= 0 || index < 0
    ? -1
    : (index * 3 ~/ count).clamp(0, 2);

/// SALU's own play queue — the source of truth above the engine.
///
/// media_kit's `Player.stop()` clears mpv's internal playlist, so a queue
/// that survives Stop (Stop ≠ Start Over: the queue stays parked) has to
/// live here. `PlayerService` hands mpv the full playlist while an item is
/// loaded (native auto-advance and gapless audio stay; shuffle / repeat-one
/// / channel mode hand mpv ONE media and choose the next index themselves),
/// mirrors mpv's index into this service, and after a Stop re-opens the
/// queue at the target index.
class QueueService {
  QueueService._internal();

  /// The one and only queue for the whole app.
  static final QueueService instance = QueueService._internal();

  /// Ordered absolute paths / URLs / channel entries of every queued item.
  final ValueNotifier<List<QueueItem>> items =
      ValueNotifier<List<QueueItem>>(<QueueItem>[]);

  /// Index of the current item (`-1` while nothing is queued).
  final ValueNotifier<int> index = ValueNotifier<int>(-1);

  /// Transitional keeper (playlist_imp.md §10.0): URL strings for the few
  /// call sites that predate [QueueItem]. New code reads [items] and its
  /// `.value`.
  List<String> get paths =>
      items.value.map((QueueItem i) => i.url).toList(growable: false);

  bool get hasQueue => items.value.isNotEmpty;

  /// Whether this queue is an m3u channel list — read off the DATA, not a
  /// mode flag, so it can never disagree with the rows (§10.0).
  bool get isChannelList =>
      items.value.any((QueueItem i) => i.name != null);

  bool get hasCurrent {
    final int i = index.value;
    return i >= 0 && i < items.value.length;
  }

  /// Whether an item exists after the current one (Next's enable state).
  bool get hasNext {
    final int i = index.value;
    return i >= 0 && i < items.value.length - 1;
  }

  /// Replaces the whole queue and points [index] at the start item.
  void setQueue(List<QueueItem> list, int startIndex) {
    items.value = List<QueueItem>.unmodifiable(
      list.map(_canonical).toList(growable: false),
    );
    index.value = list.isEmpty ? -1 : startIndex.clamp(0, list.length - 1);
    // A fresh open starts a fresh shuffle pass and clears the heard-log.
    resetShufflePass(current: index.value < 0 ? null : index.value);
  }

  /// Convenience for local sources: raw paths/URLs in the same order (the
  /// paths arrive raw — [_canonical] is what makes them queue-shaped).
  void setPaths(List<String> list, int startIndex) {
    setQueue(
      list.map((String p) => QueueItem(p)).toList(growable: false),
      startIndex,
    );
  }

  /// THE SPELLING INVARIANT (playlist_imp.md §5): every entry that joins the
  /// queue passes through here, so `url` is always the canonical form. The
  /// queue's url is the string handed to mpv, the key the resume store is
  /// written under, and the value `stopMemory`/Undo compare against — three
  /// systems that can only agree if the queue owns one spelling. Streams
  /// come back untouched, so channel entries and the favourite keys built
  /// from them are unaffected.
  static QueueItem _canonical(QueueItem item) {
    final String url = MediaUtils.canonicalPath(item.url);
    if (url == item.url) return item; // the common case: no new object
    return QueueItem(
      url,
      name: item.name,
      group: item.group,
      language: item.language,
      country: item.country,
      chno: item.chno,
      tvgId: item.tvgId,
      searchKey: item.searchKey,
    );
  }

  /// Appends entries (the panel drop-target — playlist_imp.md §5; dedupe
  /// is not required this phase).
  void append(List<QueueItem> newItems) {
    if (newItems.isEmpty) return;
    items.value = List<QueueItem>.unmodifiable(<QueueItem>[
      ...items.value,
      ...newItems.map(_canonical),
    ]);
    if (index.value < 0) index.value = 0;
    // Structural change: the shuffle pass resets (§5).
    resetShufflePass(current: index.value < 0 ? null : index.value);
  }

  /// Convenience: append raw paths/URLs.
  void appendPaths(List<String> urls) {
    append(urls.map((String p) => QueueItem(p)).toList(growable: false));
  }

  /// Removes the entry at [i] and keeps [index] honest
  /// (playlist_imp.md §5 — the owner's remove rule):
  ///
  ///   · before the playing one → `index` shifts down one
  ///   · after the playing one  → nothing changes
  ///   · the playing one        → `index` lands on the follow-up *candidate*
  ///     (what was next — minimum distance — or the last entry); the
  ///     follow-up PLAY is PlayerService.removeFromQueue's job
  ///
  /// QueueService changes first, the engine second, the follow-up play
  /// third — so the row that disappears and the row that lights up change
  /// in the same frame the audio changes.
  void removeAt(int i) {
    final List<QueueItem> list = List<QueueItem>.of(items.value);
    if (i < 0 || i >= list.length) return;
    list.removeAt(i);
    items.value = List<QueueItem>.unmodifiable(list);
    if (list.isEmpty) {
      index.value = -1;
    } else if (i < index.value) {
      index.value = index.value - 1;
    } else if (i == index.value) {
      index.value = i >= list.length ? list.length - 1 : i;
    }
    resetShufflePass(current: index.value < 0 ? null : index.value);
  }

  /// Inserts a previously removed entry back at [index] (Undo).
  void insertAt(int i, QueueItem item) {
    final List<QueueItem> list = List<QueueItem>.of(items.value);
    final int at = i.clamp(0, list.length).toInt();
    list.insert(at, _canonical(item));
    items.value = List<QueueItem>.unmodifiable(list);
    if (at <= index.value) index.value = index.value + 1;
    resetShufflePass(current: index.value < 0 ? null : index.value);
  }

  /// Drag-reorder (the `≡` grip) — playback never restarts.
  void move(int from, int to) {
    final List<QueueItem> list = List<QueueItem>.of(items.value);
    if (from < 0 || from >= list.length) return;
    final int target = to.clamp(0, list.length - 1).toInt();
    if (from == target) return;
    final QueueItem item = list.removeAt(from);
    list.insert(target, item);
    items.value = List<QueueItem>.unmodifiable(list);
    // Keep the now-row honest: follow the playing item through the move.
    final int cur = index.value;
    if (cur == from) {
      index.value = target;
    } else if (from < target) {
      if (cur > from && cur <= target) index.value = cur - 1;
    } else {
      if (cur >= target && cur < from) index.value = cur + 1;
    }
    _remapShuffle(from, target);
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
    resetShufflePass();
  }

  // ── Shuffle pass & play-order history (playlist_imp.md §5) ───────────
  //
  // A shuffle pass = every item played once, in random order. [_pass] holds
  // the not-yet-played indexes; [_history] is the stack of visited indexes
  // ("what you heard") that makes Previous honest while shuffle is on.
  // Adding, removing or clearing items resets the pass; a drag-reorder
  // remaps it instead (same pass, new indexes) — see [_remapShuffle].

  final Set<int> _pass = <int>{};
  final List<int> _history = <int>[];

  /// The not-yet-played indexes of the current pass.
  Set<int> get unplayedInPass => Set<int>.unmodifiable(_pass);

  /// The play-order history (visited indexes, oldest first).
  List<int> get playHistory => List<int>.unmodifiable(_history);

  /// (Re)starts a pass: everything unplayed apart from a currently
  /// sounding [current], which counts as played and roots the history.
  void resetShufflePass({int? current}) {
    _pass
      ..clear()
      ..addAll(List<int>.generate(items.value.length, (int i) => i));
    _history.clear();
    if (current != null && current >= 0 && current < items.value.length) {
      _pass.remove(current);
      _history.add(current);
    }
  }

  /// Marks index [i] as played this pass (start of any playback, a manual
  /// row click counts too) and appends it to the heard-log.
  void notePlayed(int i) {
    if (i < 0 || i >= items.value.length) return;
    _pass.remove(i);
    if (_history.isEmpty || _history.last != i) _history.add(i);
  }

  /// The item actually heard before [current]: drops the current top and
  /// peeks one deeper (the top stays, so the follow-up `notePlayed` of the
  /// stepped-to item does not duplicate it). `null` = nothing heard before.
  ///
  /// This CONSUMES history — only the step itself may call it. Anything
  /// that merely wants to know where `|<<` would land (the restart
  /// predicate, the OSD card) asks [peekPreviousHeard].
  int? previousHeard(int current) {
    final int? target = peekPreviousHeard(current);
    if (_history.isNotEmpty && _history.last == current) {
      _history.removeLast();
    }
    return target;
  }

  /// The non-mutating twin of [previousHeard]: the same answer, with the
  /// heard-log left untouched — so asking the question can never change
  /// the answer to it.
  int? peekPreviousHeard(int current) {
    final int top = _history.length - 1;
    final int at = top >= 0 && _history[top] == current ? top - 1 : top;
    return at < 0 ? null : _history[at];
  }

  /// A drag-reorder remaps pass/history indexes WITHOUT resetting the pass.
  void _remapShuffle(int from, int to) {
    int remap(int i) {
      if (i == from) return to;
      if (from < to) {
        return (i > from && i <= to) ? i - 1 : i;
      }
      return (i >= to && i < from) ? i + 1 : i;
    }

    final Set<int> p = _pass.map(remap).toSet();
    _pass
      ..clear()
      ..addAll(p);
    for (int j = 0; j < _history.length; j++) {
      _history[j] = remap(_history[j]);
    }
  }
}
