import 'dart:isolate';

import 'channel_grouping.dart';
import 'queue_item.dart';
import 'remote/queue_pages.dart';

/// Shared grouping cache for the playlist panel, Prev/Next and the remote
/// handler (pc_part.md Part F3).
///
/// Keyed by the published queue list and its content revision. A playback
/// tick does not publish a new list, so availability and membership are
/// not rebuilt on the 120/250 ms snapshot clocks. Heavy builds for large
/// lists run on a worker isolate; the result is stored only if that
/// revision is still current.
class QueueGroupingCache {
  QueueGroupingCache._();

  static final QueueGroupingCache instance = QueueGroupingCache._();

  /// Lists at least this long are built off the UI isolate. Smaller lists
  /// are cheaper to build in place than to copy into a worker.
  static const int isolateThreshold = 2500;

  /// Test seam: force the worker path even for a tiny list.
  static bool forceIsolateForTest = false;

  List<QueueItem>? _items;
  String? _revision;
  final Map<ChannelGroupMode, List<ChannelGroup>> _groups =
      <ChannelGroupMode, List<ChannelGroup>>{};
  final Map<ChannelGroupMode, List<QueueGroupFragment>> _fragments =
      <ChannelGroupMode, List<QueueGroupFragment>>{};
  final Map<ChannelGroupMode, Future<QueueFragmentPayload>> _inflight =
      <ChannelGroupMode, Future<QueueFragmentPayload>>{};

  List<QueueItem>? _channelItems;
  bool _channelFlag = false;
  List<QueueItem>? _availItems;
  Map<ChannelGroupMode, bool>? _avail;

  void clear() {
    _items = null;
    _revision = null;
    _groups.clear();
    _fragments.clear();
    _inflight.clear();
    _channelItems = null;
    _channelFlag = false;
    _availItems = null;
    _avail = null;
  }

  bool isChannelList(List<QueueItem> items) {
    if (identical(items, _channelItems)) return _channelFlag;
    _channelItems = items;
    _channelFlag = items.any((QueueItem item) => item.name != null);
    return _channelFlag;
  }

  /// One scan per published list. Snapshot flushes reuse the result.
  Map<ChannelGroupMode, bool> availability(List<QueueItem> items) {
    if (identical(items, _availItems) && _avail != null) return _avail!;
    _availItems = items;
    _avail = ChannelGrouping.availability(items);
    return _avail!;
  }

  void _bind(List<QueueItem> items, String revision) {
    if (identical(_items, items) && _revision == revision) return;
    _items = items;
    _revision = revision;
    _groups.clear();
    _fragments.clear();
  }

  List<ChannelGroup>? peekGroups(
    List<QueueItem> items,
    String revision,
    ChannelGroupMode mode,
  ) {
    if (!identical(_items, items) || _revision != revision) return null;
    return _groups[mode];
  }

  /// `null` when the cache is cold. An empty list means the cache is warm
  /// and the key is not a current group (stale accordion key).
  List<int>? peekMembers(
    List<QueueItem> items,
    String revision,
    ChannelGroupMode mode,
    String groupKey,
  ) {
    final List<ChannelGroup>? groups = peekGroups(items, revision, mode);
    if (groups == null) return null;
    for (final ChannelGroup group in groups) {
      if (group.key == groupKey) return group.indexes;
    }
    return const <int>[];
  }

  /// Synchronous fill for small lists and a warm cache. Do not call this
  /// from a widget build for a large cold list — use [payloadAsync].
  List<ChannelGroup> groupsSync(
    List<QueueItem> items,
    String revision,
    ChannelGroupMode mode, {
    String? by,
  }) {
    _bind(items, revision);
    final List<ChannelGroup>? cached = _groups[mode];
    if (cached != null) return cached;
    final QueueFragmentPayload payload = buildQueueFragments(
      items: items,
      mode: mode,
      revision: revision,
      by: by ?? mode.name,
    );
    _store(items, revision, mode, payload);
    return payload.groups;
  }

  /// Group index and fragments for [revision]. Concurrent callers share
  /// one in-flight build. A superseded revision is not stored.
  Future<QueueFragmentPayload> payloadAsync({
    required List<QueueItem> items,
    required String revision,
    required ChannelGroupMode mode,
    required String by,
  }) {
    _bind(items, revision);
    final List<QueueGroupFragment>? cached = _fragments[mode];
    final List<ChannelGroup>? groups = _groups[mode];
    if (cached != null && groups != null) {
      return Future<QueueFragmentPayload>.value(QueueFragmentPayload(
        groups: groups,
        fragments: cached,
      ));
    }
    final Future<QueueFragmentPayload>? inflight = _inflight[mode];
    if (inflight != null) return inflight;
    final Future<QueueFragmentPayload> future = _compute(
      items: items,
      mode: mode,
      revision: revision,
      by: by,
    );
    _inflight[mode] = future;
    return future.then((QueueFragmentPayload payload) {
      _store(items, revision, mode, payload);
      return payload;
    }).whenComplete(() {
      if (identical(_inflight[mode], future)) _inflight.remove(mode);
    });
  }

  void _store(
    List<QueueItem> items,
    String revision,
    ChannelGroupMode mode,
    QueueFragmentPayload payload,
  ) {
    if (!identical(_items, items) || _revision != revision) return;
    _groups[mode] = payload.groups;
    _fragments[mode] = payload.fragments;
  }

  Future<QueueFragmentPayload> _compute({
    required List<QueueItem> items,
    required ChannelGroupMode mode,
    required String revision,
    required String by,
  }) async {
    if (!forceIsolateForTest && items.length < isolateThreshold) {
      return buildQueueFragments(
        items: items,
        mode: mode,
        revision: revision,
        by: by,
      );
    }
    try {
      // Pure data only. UI and WebView calls stay on their own thread.
      return await Isolate.run(() => buildQueueFragments(
            items: items,
            mode: mode,
            revision: revision,
            by: by,
          ));
    } catch (_) {
      return buildQueueFragments(
        items: items,
        mode: mode,
        revision: revision,
        by: by,
      );
    }
  }
}
