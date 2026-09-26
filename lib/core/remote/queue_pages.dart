import 'dart:convert';
import 'dart:math' as math;

import '../channel_grouping.dart';
import '../queue_item.dart';
import 'remote_protocol.dart';

/// `queue_groups_page` — the paged membership read (pc_part.md Part F ·
/// remote.md §17.16). Protocol version stays 1.
const String queueGroupsPageVerb = 'queue_groups_page';

/// Remote starts at this fragment cap. The byte budget may return fewer.
const int queueGroupsPageDefaultCount = 20;

/// Existing `queue_get` maximum. Count is a maximum, never a promise.
const int queueRowPageMaxCount = 100;

/// Suggested fragment width. Smaller when the encoded fragment needs it.
const int queueFragmentMaxIndexes = 100;

/// Command-id width reserved while splitting fragments, so a later page
/// request — which does not know this id — still fits a fragment that was
/// split without it. Fragment boundaries must not depend on `count`.
const int queuePageWorstCaseId = 999999999999999999;

/// A yield point between preparing a group page and publishing it, so a
/// playlist that changed mid-read fails `stale_queue` instead of mixing
/// revisions. Production is a no-op; tests replace it.
abstract final class QueuePageHooks {
  static Future<void> Function() beforePublish = _noop;

  static Future<void> _noop() async {}

  static void reset() {
    beforePublish = _noop;
  }
}

/// One bounded membership fragment. [indexes] is exact membership, not a
/// consecutive range. Fragments of one group share [key], [name], [count]
/// and [start].
class QueueGroupFragment {
  const QueueGroupFragment({
    required this.key,
    required this.name,
    required this.count,
    required this.start,
    required this.indexes,
  });

  final String key;
  final String name;

  /// Total members of the group, not the length of [indexes].
  final int count;

  /// Absolute queue index of the group's first member. Descriptive only.
  final int start;

  final List<int> indexes;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'name': name,
        'count': count,
        'start': start,
        'indexes': indexes,
      };
}

/// Groups plus the deterministic fragment sequence for one revision and mode.
class QueueFragmentPayload {
  const QueueFragmentPayload({
    required this.groups,
    required this.fragments,
  });

  final List<ChannelGroup> groups;
  final List<QueueGroupFragment> fragments;
}

/// A packed `queue_groups_page` body. [tooLarge] means even one fragment
/// could not fit — the caller answers `too_large`, never `busy`.
class QueueGroupsPage {
  const QueueGroupsPage({
    required this.groups,
    required this.next,
    required this.tooLarge,
  });

  final List<Map<String, Object?>> groups;
  final int? next;
  final bool tooLarge;
}

/// A packed `queue_get` body.
class PackedQueueRows {
  const PackedQueueRows({
    required this.rows,
    required this.tooLarge,
  });

  final List<Map<String, Object?>> rows;
  final bool tooLarge;
}

/// One candidate row, already in ascending queue order.
class QueueRowCandidate {
  const QueueRowCandidate({
    required this.index,
    required this.title,
    required this.now,
    required this.includeDuration,
  });

  final int index;
  final String title;
  final bool now;
  final bool includeDuration;
}

int queueWireBytes(Map<String, Object?> message) =>
    utf8.encode(jsonEncode(message)).length;

/// Display text safe to leave the PC: no stream URL, no private path.
/// Truncates on rune boundaries so a long Unicode name cannot split a
/// surrogate. Playback identity is never derived from this string.
String remoteSafeTitle(String raw, {int maxRunes = 80}) {
  String value = raw.replaceAll('\u0000', '');
  if (value.contains('://') ||
      value.contains('\\') ||
      _windowsDrive.hasMatch(value)) {
    final String stem = value.replaceAll('\\', '/').split('/').last;
    final int query = stem.indexOf('?');
    final String noQuery = query >= 0 ? stem.substring(0, query) : stem;
    final int dot = noQuery.lastIndexOf('.');
    value = dot > 0 ? noQuery.substring(0, dot) : noQuery;
    if (value.isEmpty || value.contains('://')) value = 'Item';
  }
  return truncateRunes(value, maxRunes);
}

final RegExp _windowsDrive = RegExp(r'^[A-Za-z]:');

String truncateRunes(String value, int maxRunes) {
  if (maxRunes <= 0) return '';
  final List<int> runes = value.runes.toList(growable: false);
  if (runes.length <= maxRunes) return value;
  if (maxRunes == 1) return '…';
  return '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
}

/// Compact stable key. Ordinal in descriptor-head order, so a huge label
/// never has to ride in the key. Stable for one revision and mode.
String compactGroupKey(ChannelGroupMode mode, int ordinal) {
  final String prefix = switch (mode) {
    ChannelGroupMode.category => 'c',
    ChannelGroupMode.language => 'l',
    ChannelGroupMode.country => 'o',
    ChannelGroupMode.flat => 'f',
  };
  return '$prefix$ordinal';
}

Map<String, Object?> queueResultWire({
  required int id,
  required int from,
  required int count,
  required int total,
  required String revision,
  required List<Map<String, Object?>> rows,
}) =>
    <String, Object?>{
      'id': id,
      'proto': protocolVersion,
      'type': 'queue_result',
      'ok': true,
      'from': from,
      'count': count,
      'total': total,
      'revision': revision,
      'rows': rows,
    };

Map<String, Object?> queueResultBody({
  required int from,
  required int total,
  required String revision,
  required List<Map<String, Object?>> rows,
}) =>
    <String, Object?>{
      'type': 'queue_result',
      'ok': true,
      'from': from,
      'count': rows.length,
      'total': total,
      'revision': revision,
      'rows': rows,
    };

Map<String, Object?> queueGroupsResultWire({
  required int id,
  required String revision,
  required String by,
  required List<Map<String, Object?>> groups,
  required int? next,
}) =>
    <String, Object?>{
      'id': id,
      'proto': protocolVersion,
      'type': 'queue_groups_result',
      'ok': true,
      'revision': revision,
      'by': by,
      'groups': groups,
      'next': next,
    };

Map<String, Object?> queueGroupsResultBody({
  required String revision,
  required String by,
  required List<Map<String, Object?>> groups,
  required int? next,
}) =>
    <String, Object?>{
      'type': 'queue_groups_result',
      'ok': true,
      'revision': revision,
      'by': by,
      'groups': groups,
      'next': next,
    };

/// Byte budget for one fragment object inside a worst-case single-fragment
/// page. Independent of the requested page size.
int maxFragmentJsonBytes({
  required String revision,
  required String by,
}) {
  const Map<String, Object?> empty = <String, Object?>{
    'key': '',
    'name': '',
    'count': 0,
    'start': 0,
    'indexes': <int>[],
  };
  final int skeleton = queueWireBytes(queueGroupsResultWire(
    id: queuePageWorstCaseId,
    revision: revision,
    by: by,
    groups: const <Map<String, Object?>>[empty],
    next: 9999999999,
  ));
  final int emptyBytes = utf8.encode(jsonEncode(empty)).length;
  final int budget = maxRemoteMessageBytes - (skeleton - emptyBytes);
  return budget < 64 ? 64 : budget;
}

int _fragmentBytes({
  required String key,
  required String name,
  required int count,
  required int start,
  required List<int> indexes,
}) =>
    utf8.encode(jsonEncode(<String, Object?>{
      'key': key,
      'name': name,
      'count': count,
      'start': start,
      'indexes': indexes,
    })).length;

String _shrinkName({
  required String key,
  required String name,
  required int count,
  required int start,
  required int sampleIndex,
  required int budget,
}) {
  String current = name;
  while (true) {
    final int bytes = _fragmentBytes(
      key: key,
      name: current,
      count: count,
      start: start,
      indexes: <int>[sampleIndex],
    );
    if (bytes <= budget) return current;
    final int runes = current.runes.length;
    if (runes <= 1) return current.isEmpty ? '' : '…';
    current = truncateRunes(current, math.max(1, runes ~/ 2));
  }
}

int _chunkSize({
  required String key,
  required String name,
  required int count,
  required int start,
  required int widest,
  required int indexCount,
  required int budget,
}) {
  int chunk = math.min(queueFragmentMaxIndexes, indexCount);
  if (chunk < 1) return 1;
  while (chunk > 1) {
    final int bytes = _fragmentBytes(
      key: key,
      name: name,
      count: count,
      start: start,
      indexes: List<int>.filled(chunk, widest),
    );
    if (bytes <= budget) return chunk;
    chunk = math.max(1, chunk ~/ 2);
  }
  return 1;
}

/// Flattens [groups] (already in descriptor-head order) into a deterministic
/// fragment sequence. Boundaries depend on the revision, mode and membership
/// only — never on a requested `count`.
List<QueueGroupFragment> splitGroupFragments({
  required List<ChannelGroup> groups,
  required ChannelGroupMode mode,
  required String revision,
  required String by,
}) {
  final int budget = maxFragmentJsonBytes(revision: revision, by: by);
  final List<QueueGroupFragment> out = <QueueGroupFragment>[];
  for (int ordinal = 0; ordinal < groups.length; ordinal++) {
    final ChannelGroup group = groups[ordinal];
    if (group.indexes.isEmpty) continue;
    final String key = compactGroupKey(mode, ordinal);
    final int start = group.indexes.first;
    final int widest = group.indexes.reduce(math.max);
    final String name = _shrinkName(
      key: key,
      name: remoteSafeTitle(group.label),
      count: group.indexes.length,
      start: start,
      sampleIndex: widest,
      budget: budget,
    );
    final int chunk = _chunkSize(
      key: key,
      name: name,
      count: group.indexes.length,
      start: start,
      widest: widest,
      indexCount: group.indexes.length,
      budget: budget,
    );
    for (int offset = 0; offset < group.indexes.length; offset += chunk) {
      final int end = math.min(offset + chunk, group.indexes.length);
      out.add(QueueGroupFragment(
        key: key,
        name: name,
        count: group.indexes.length,
        start: start,
        indexes: List<int>.unmodifiable(group.indexes.sublist(offset, end)),
      ));
    }
  }
  return List<QueueGroupFragment>.unmodifiable(out);
}

/// Pure grouping + fragment build. Safe to run on a worker isolate: no
/// widgets, no sockets, no WebView.
QueueFragmentPayload buildQueueFragments({
  required List<QueueItem> items,
  required ChannelGroupMode mode,
  required String revision,
  required String by,
}) {
  final List<int> indexes = List<int>.generate(items.length, (int i) => i);
  final List<ChannelGroup> groups =
      ChannelGrouping.buildGroups(items, indexes, mode);
  return QueueFragmentPayload(
    groups: groups,
    fragments: splitGroupFragments(
      groups: groups,
      mode: mode,
      revision: revision,
      by: by,
    ),
  );
}

/// Packs a contiguous slice of the fragment sequence into one frame.
/// [from] is a fragment offset. [next] is `from + groups.length` when more
/// fragments remain, otherwise null. Never a nonterminal empty page.
QueueGroupsPage packGroupFragments({
  required int id,
  required String revision,
  required String by,
  required List<QueueGroupFragment> fragments,
  required int from,
  required int count,
}) {
  if (from < 0) from = 0;
  if (from >= fragments.length) {
    return const QueueGroupsPage(
      groups: <Map<String, Object?>>[],
      next: null,
      tooLarge: false,
    );
  }
  final int cap = count < 1 ? 1 : count;
  final List<Map<String, Object?>> included = <Map<String, Object?>>[];
  for (int i = from; i < fragments.length && included.length < cap; i++) {
    final Map<String, Object?> encoded = fragments[i].toJson();
    final List<Map<String, Object?>> trial = <Map<String, Object?>>[
      ...included,
      encoded,
    ];
    final int consumed = from + trial.length;
    final int? next = consumed < fragments.length ? consumed : null;
    final int bytes = queueWireBytes(queueGroupsResultWire(
      id: id,
      revision: revision,
      by: by,
      groups: trial,
      next: next,
    ));
    if (bytes > maxRemoteMessageBytes) break;
    included.add(encoded);
  }
  if (included.isEmpty) {
    return const QueueGroupsPage(
      groups: <Map<String, Object?>>[],
      next: null,
      tooLarge: true,
    );
  }
  final int consumed = from + included.length;
  return QueueGroupsPage(
    groups: included,
    next: consumed < fragments.length ? consumed : null,
    tooLarge: false,
  );
}

Map<String, Object?> _rowJson(QueueRowCandidate candidate, String title) =>
    <String, Object?>{
      'index': candidate.index,
      'title': title,
      if (candidate.includeDuration) 'durationMs': null,
      'now': candidate.now,
    };

String _shrinkTitle(String title, bool Function(String title) fits) {
  String current = title;
  if (fits(current)) return current;
  int runes = current.runes.length;
  while (runes > 1) {
    runes = math.max(1, runes ~/ 2);
    current = truncateRunes(title, runes);
    if (fits(current)) return current;
  }
  if (fits('…')) return '…';
  if (fits('')) return '';
  return current;
}

/// Byte-packs consecutive rows into one `queue_result`. Returns fewer rows
/// when the frame would exceed 8 KiB. Shortens a single oversized title
/// without changing its index. [tooLarge] only when even one shortened row
/// cannot fit.
PackedQueueRows packQueueRows({
  required int id,
  required int from,
  required int total,
  required String revision,
  required int count,
  required List<QueueRowCandidate> candidates,
}) {
  final int cap = count.clamp(1, queueRowPageMaxCount).toInt();
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (final QueueRowCandidate candidate in candidates) {
    if (rows.length >= cap) break;
    final String safe = remoteSafeTitle(candidate.title, maxRunes: 180);
    bool fits(String title) {
      final List<Map<String, Object?>> trial = <Map<String, Object?>>[
        ...rows,
        _rowJson(candidate, title),
      ];
      return queueWireBytes(queueResultWire(
            id: id,
            from: from,
            count: trial.length,
            total: total,
            revision: revision,
            rows: trial,
          )) <=
          maxRemoteMessageBytes;
    }

    if (!fits(safe)) {
      if (rows.isNotEmpty) break;
      final String shrunk = _shrinkTitle(safe, fits);
      if (!fits(shrunk)) {
        return const PackedQueueRows(
          rows: <Map<String, Object?>>[],
          tooLarge: true,
        );
      }
      rows.add(_rowJson(candidate, shrunk));
      continue;
    }
    rows.add(_rowJson(candidate, safe));
  }
  return PackedQueueRows(rows: rows, tooLarge: false);
}
