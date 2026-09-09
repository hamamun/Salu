/// Channel grouping — the accordion's pure model (playlist_imp.md §10.2,
/// §10.2a, §10.5 · point 5 Final).
///
/// No widgets, no engine, no storage: given the queue's items and the
/// viewer's choices (mode, filter, open group) this builds the group
/// index and the flat descriptor list the panel paints. The approved
/// `design/iptv-channel-preview` semantics are the reference
/// (`model.mjs`): category keeps the provider's first-appearance order,
/// language/country sort alphabetically, `Unknown` is always last, and a
/// mode switch never touches anything but this view (M45).
library;

import 'queue_item.dart';

/// The four group-by modes (playlist_imp.md M4). Every fresh load starts
/// in [flat] (M6) — grouping changes only when the viewer chooses it.
enum ChannelGroupMode { flat, category, language, country }

/// The grouping value of [item] in [mode] (`null` = missing — shown
/// under `Unknown`, last). The mapper already applied the alias tables
/// and the same-file `group-title` → `#EXTGRP` fallback (§10.2a); this
/// only reads the record.
String? channelGroupValue(QueueItem item, ChannelGroupMode mode) =>
    switch (mode) {
      ChannelGroupMode.flat => null,
      ChannelGroupMode.category => item.group,
      ChannelGroupMode.language => item.language,
      ChannelGroupMode.country => item.country,
    };

/// One group head: its label, whether it is the missing-data bucket,
/// and the **real queue indexes** it holds, in list order (views hold
/// indexes over the one queue — never copies, §10.0).
class ChannelGroup {
  const ChannelGroup({
    required this.mode,
    required this.label,
    required this.unknown,
    required this.indexes,
  });

  final ChannelGroupMode mode;

  /// Display label — the shared value, or `Unknown` for the missing-data
  /// bucket (a label, not a stored fake category).
  final String label;

  /// Whether this is the missing-data bucket (always sorted last).
  final bool unknown;

  /// Real queue indexes of the group's channels, in list order.
  final List<int> indexes;

  /// Stable identity of the open group. A literal group *named*
  /// `Unknown` and the missing-data bucket are different keys — the
  /// key carries the null-ness, exactly like the preview's
  /// `JSON.stringify([mode, value])`.
  String get key => '${mode.name}\u0000${unknown ? '\u0000' : label}';

  @override
  String toString() => 'ChannelGroup($mode $label ×${indexes.length})';
}

/// One paintable row of the channel list: either a group head or one
/// channel. The panel builds this list and paints it with a fixed row
/// extent, so 50 000 channels stay a scroll offset, not 50 000 widgets.
sealed class ChannelDescriptor {
  const ChannelDescriptor();
}

/// A group head (`key` identifies it; `expanded` says whether its
/// channels follow it in the list).
class GroupHeadDescriptor extends ChannelDescriptor {
  const GroupHeadDescriptor(this.group, {required this.expanded});

  final ChannelGroup group;
  final bool expanded;

  String get key => group.key;

  @override
  String toString() =>
      'GroupHead(${group.label} expanded=$expanded ×${group.indexes.length})';
}

/// One channel row — [index] is the **real queue index** (a row click,
/// Prev/Next and the now-row all speak queue indexes, never view
/// positions). [groupKey] names the head it sits under, if any.
class ChannelRowDescriptor extends ChannelDescriptor {
  const ChannelRowDescriptor(this.index, {this.groupKey});

  final int index;
  final String? groupKey;

  @override
  String toString() => 'ChannelRow($index)';
}

/// Builds group indexes and descriptor lists. All methods are pure —
/// the panel caches the result per view state so a scroll tick never
/// rebuilds the index.
class ChannelGrouping {
  ChannelGrouping._();

  /// Which modes the **underlying playlist** offers (M7). Reads the full
  /// [items], never a search/favourites subset: filtering rows must not
  /// dim a mode. Flat is always available.
  static Map<ChannelGroupMode, bool> availability(List<QueueItem> items) {
    bool category = false, language = false, country = false;
    for (final QueueItem item in items) {
      if (item.group != null) category = true;
      if (item.language != null) language = true;
      if (item.country != null) country = true;
      if (category && language && country) break;
    }
    return <ChannelGroupMode, bool>{
      ChannelGroupMode.flat: true,
      ChannelGroupMode.category: category,
      ChannelGroupMode.language: language,
      ChannelGroupMode.country: country,
    };
  }

  /// Groups [indexes] (real queue indexes, usually the filtered view)
  /// under [mode]. Empty in Flat — Flat has no heads.
  ///
  /// Order: category keeps first-appearance order; language/country are
  /// alphabetical (case-insensitive); the missing-data group is last.
  /// Empty groups vanish — only values present in [indexes] appear.
  static List<ChannelGroup> buildGroups(
    List<QueueItem> items,
    List<int> indexes,
    ChannelGroupMode mode,
  ) {
    if (mode == ChannelGroupMode.flat) return const <ChannelGroup>[];
    final Map<String, ChannelGroup> byKey = <String, ChannelGroup>{};
    final List<String> firstAppearance = <String>[];
    for (final int i in indexes) {
      if (i < 0 || i >= items.length) continue;
      final String? value = channelGroupValue(items[i], mode);
      final bool unknown = value == null;
      final String key =
          '${mode.name}\u0000${unknown ? '\u0000' : value}';
      ChannelGroup? group = byKey[key];
      if (group == null) {
        group = ChannelGroup(
          mode: mode,
          label: value ?? 'Unknown',
          unknown: unknown,
          indexes: <int>[],
        );
        byKey[key] = group;
        firstAppearance.add(key);
      }
      group.indexes.add(i);
    }
    final List<ChannelGroup> groups = byKey.values.toList(growable: false);
    final Map<String, int> order = <String, int>{
      for (int i = 0; i < firstAppearance.length; i++)
        firstAppearance[i]: i,
    };
    int compare(ChannelGroup a, ChannelGroup b) {
      if (a.unknown != b.unknown) return a.unknown ? 1 : -1;
      if (mode == ChannelGroupMode.category) {
        return order[a.key]!.compareTo(order[b.key]!);
      }
      final int alpha = a.label
          .toLowerCase()
          .compareTo(b.label.toLowerCase());
      if (alpha != 0) return alpha;
      return a.label.compareTo(b.label);
    }

    groups.sort(compare);
    return groups;
  }

  /// The full paint list for the current view: in Flat (or while a
  /// search flattens the list) one row per filtered index; otherwise one
  /// head per group plus the open group's rows. [openGroupKey] opens at
  /// most one group (the accordion, M17) — a stale key simply opens
  /// nothing.
  static List<ChannelDescriptor> descriptors({
    required List<QueueItem> items,
    required List<int> filtered,
    required ChannelGroupMode mode,
    required String? openGroupKey,
    required bool flattened,
  }) {
    if (flattened || mode == ChannelGroupMode.flat) {
      return List<ChannelDescriptor>.unmodifiable(
        filtered.map((int i) => ChannelRowDescriptor(i)),
      );
    }
    final List<ChannelGroup> groups = buildGroups(items, filtered, mode);
    final List<ChannelDescriptor> out = <ChannelDescriptor>[];
    for (final ChannelGroup group in groups) {
      final bool open = group.key == openGroupKey;
      out.add(GroupHeadDescriptor(group, expanded: open));
      if (open) {
        for (final int i in group.indexes) {
          out.add(ChannelRowDescriptor(i, groupKey: group.key));
        }
      }
    }
    return List<ChannelDescriptor>.unmodifiable(out);
  }

  /// The group key of the channel at [index] in [mode] (`null` in Flat
  /// or out of range) — what selecting a grouped mode opens (§10.5).
  static String? keyFor(
    List<QueueItem> items,
    int index,
    ChannelGroupMode mode,
  ) {
    if (mode == ChannelGroupMode.flat) return null;
    if (index < 0 || index >= items.length) return null;
    final String? value = channelGroupValue(items[index], mode);
    final bool unknown = value == null;
    return '${mode.name}\u0000${unknown ? '\u0000' : value}';
  }

  /// Real queue indexes of the group [groupKey] in [mode], in list order
  /// — what Prev/Next walk while a group is open. Empty in Flat and for
  /// a stale/unknown key (a key whose group vanished simply steps raw
  /// list order again).
  static List<int> membersOf(
    List<QueueItem> items,
    ChannelGroupMode mode,
    String groupKey,
  ) {
    if (mode == ChannelGroupMode.flat) return const <int>[];
    final List<int> out = <int>[];
    for (int i = 0; i < items.length; i++) {
      if (keyFor(items, i, mode) == groupKey) out.add(i);
    }
    return out;
  }

  /// The Prev/Next landing index for a channel list.
  ///
  /// [members] is the open group's channels ([membersOf]) — empty in
  /// Flat, while the accordion is collapsed, while a search flattens the
  /// list, or for a stale key, in which case stepping is plain raw list
  /// order. [direction] is +1 for Next, −1 for Previous. `null` parks
  /// (edges never wrap):
  ///
  /// - inside the open group, steps to the neighbouring member; at the
  ///   group's edges it parks instead of leaving the group;
  /// - from OUTSIDE the open group (the viewer is browsing a group that
  ///   is not the playing one), steps INTO it — Next takes its first
  ///   channel, Previous its last.
  ///
  /// The favourites filter never affects stepping — only the open group
  /// does.
  static int? stepTarget({
    required List<int> members,
    required int from,
    required int direction,
    required int count,
  }) {
    if (members.isEmpty) {
      if (direction > 0) {
        return (from >= 0 && from < count - 1) ? from + 1 : null;
      }
      final int to = from - 1;
      return (from > 0 && to < count) ? to : null;
    }
    final int pos = members.indexOf(from);
    if (pos < 0) return direction > 0 ? members.first : members.last;
    final int at = pos + direction;
    return (at >= 0 && at < members.length) ? members[at] : null;
  }
}
