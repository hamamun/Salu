import 'package:flutter/foundation.dart';

import '../../core/channel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import 'playlist_store.dart';

/// The bridge between the player process and the loose playlist window
/// (playlist_imp.md §4.8 / §9.1) — and later Phase 8's Android remote
/// over a WebSocket: ONE message shape, two transports.
///
///   · OUT (host → child): a full snapshot once ('snapshot'), then
///     DELTAS ('delta') — a few keys per change, never a re-mount.
///   · IN (child → host): INTENTS ('intent') by name, carried back to
///     the real services; state never flows the wrong way.
///
/// Both sides speak over a `WindowMethodChannel` named [kPlaylistBridgeChannel]
/// (desktop_multi_window's per-name broadcast channel).

/// The one method-channel name both engines use for the bridge.
const String kPlaylistBridgeChannel = 'salu-playlist-bridge';

/// The channel the low-level window control methods ride (focus, pulse,
/// drag-root reporting).
const String kPlaylistWindowChannel = 'salu-playlist-window-ctl';

/// Bridge message methods.
const String kMsgSnapshot = 'snapshot';
const String kMsgDelta = 'delta';
const String kMsgIntent = 'intent';
const String kMsgReady = 'ready';

// ── QueueItem codec ────────────────────────────────────────────────────────

Map<String, String> queueItemToMap(QueueItem item) => <String, String>{
      'u': item.url,
      if (item.name != null) 'n': item.name!,
      if (item.group != null) 'g': item.group!,
      if (item.language != null) 'l': item.language!,
      if (item.country != null) 'c': item.country!,
      if (item.chno != null) 'no': item.chno!,
      if (item.tvgId != null) 't': item.tvgId!,
      if (item.searchKey != null) 's': item.searchKey!,
    };

QueueItem queueItemFromMap(Map<Object?, Object?> m) {
  String? s(Object? k) => m[k]?.toString();

  return QueueItem(
    s('u') ?? '',
    name: s('n'),
    group: s('g'),
    language: s('l'),
    country: s('c'),
    chno: s('no'),
    tvgId: s('t'),
    searchKey: s('s')?.isNotEmpty == true ? s('s') : null,
  );
}

// ── Snapshot / delta keys ──────────────────────────────────────────────────
//
//   'i' items (full replace, delta-shaped traffic only ever replaces the
//       whole items list — a compact list), 'x' index, 'R' repeat 0..2,
//   'S' shuffle, 'F' filter text, 'G' group mode 0..3, 'N' favourites only,
//   'k' favourite keys, 'g' open group (null = none), 'u' undo offered,
//   'D' duration ms of the current item.

/// Builds the full-state snapshot from the live services (host side).
Map<String, Object?> playlistSnapshot(
  List<QueueItem> items,
  int index, {
  required int repeatMode,
  required bool shuffle,
  required String filter,
  required int groupMode,
  required bool favouritesOnly,
  required Set<String> favouriteKeys,
  required String? openGroup,
  required bool undo,
  required int durationMs,
}) {
  return <String, Object?>{
    'i': <Map<String, String>>[for (final QueueItem it in items) queueItemToMap(it)],
    'x': index,
    'R': repeatMode,
    'S': shuffle,
    'F': filter,
    'G': groupMode,
    'N': favouritesOnly,
    'k': favouriteKeys.toList(growable: false),
    'g': openGroup,
    'u': undo,
    'D': durationMs,
  };
}

/// The intent names the child may raise (host side dispatches each to the
/// real service — the loose window never owns state).
enum PlaylistIntent {
  playRow,
  removeRow,
  moveRow,
  cycleRepeat,
  toggleShuffle,
  clearPlaylist,
  setFilter,
  setGroupMode,
  toggleFavouritesOnly,
  toggleFavourite,
  setOpenGroup,
  undo,
  dock,
}

/// The child window's view of the playlist: every read is an OWNED
/// notifier fed by bridge deltas; every action becomes an intent. The
/// same [PlaylistStore] surface, zero UI changes.
class MirrorPlaylistStore extends PlaylistStore {
  MirrorPlaylistStore({required this.sendIntent});

  /// Injected by the child-shell setup — forwards an intent map over the
  /// bridge (after the drop, set to no-op).
  final void Function(Map<String, Object?> intent) sendIntent;

  final ValueNotifier<List<QueueItem>> _items =
      ValueNotifier<List<QueueItem>>(const <QueueItem>[]);
  final ValueNotifier<int> _index = ValueNotifier<int>(-1);
  final ValueNotifier<RepeatMode> _repeatMode =
      ValueNotifier<RepeatMode>(RepeatMode.off);
  final ValueNotifier<bool> _shuffleOn = ValueNotifier<bool>(false);
  final ValueNotifier<String> _filter = ValueNotifier<String>('');
  final ValueNotifier<GroupMode> _groupMode =
      ValueNotifier<GroupMode>(GroupMode.flat);
  final ValueNotifier<bool> _favouritesOnly = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _favourites =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<String?> _openGroup = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _undoAvailable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _undocked = ValueNotifier<bool>(true);
  final ValueNotifier<Duration> _duration =
      ValueNotifier<Duration>(Duration.zero);

  // ── Data ──

  @override
  ValueListenable<List<QueueItem>> get items => _items;

  @override
  ValueListenable<int> get index => _index;

  @override
  ValueListenable<RepeatMode> get repeatMode => _repeatMode;

  @override
  ValueListenable<bool> get shuffleOn => _shuffleOn;

  @override
  ValueListenable<String> get filter => _filter;

  @override
  ValueListenable<GroupMode> get groupMode => _groupMode;

  @override
  ValueListenable<bool> get favouritesOnly => _favouritesOnly;

  @override
  ValueListenable<Set<String>> get favourites => _favourites;

  @override
  ValueListenable<String?> get openGroup => _openGroup;

  @override
  ValueListenable<bool> get undoAvailable => _undoAvailable;

  @override
  ValueListenable<bool> get undocked => _undocked;

  @override
  ValueListenable<Duration> get duration => _duration;

  @override
  bool get isChannelList =>
      _items.value.any((QueueItem i) => i.name != null);

  @override
  bool groupModeAvailable(GroupMode mode) =>
      ChannelService.modeAvailableStatic(mode, _items.value);

  @override
  bool get hasAnyFavourites => _favourites.value.isNotEmpty;

  @override
  String? favouriteKeyOf(int queueIndex) {
    final List<QueueItem> list = _items.value;
    if (queueIndex < 0 || queueIndex >= list.length) return null;
    final QueueItem item = list[queueIndex];
    if (item.name == null) return null;
    final String? id = item.tvgId;
    if (id != null && id.trim().isNotEmpty) return id.trim();
    return item.name;
  }

  // ── Deltas in ──

  /// Applies one snapshot or delta map from the host, then notifies.
  void apply(Map<Object?, Object?> msg) {
    int i(String k, int fallback) {
      final Object? v = msg[k];
      return v is int ? v : (v is num ? v.toInt() : fallback);
    }

    bool b(String k, bool fallback) {
      final Object? v = msg[k];
      return v is bool ? v : fallback;
    }

    if (msg['i'] != null) {
      final Object? raw = msg['i'];
      if (raw is List) {
        _items.value = List<QueueItem>.unmodifiable(<QueueItem>[
          for (final Object? e in raw)
            if (e is Map) queueItemFromMap(e.cast<Object?, Object?>()),
        ]);
      }
    }
    if (msg['x'] != null) _index.value = i('x', _index.value);
    if (msg['R'] != null) {
      _repeatMode.value = RepeatMode.values[i('R', 0).clamp(0, 2)];
    }
    if (msg['S'] != null) _shuffleOn.value = b('S', _shuffleOn.value);
    if (msg['F'] != null) {
      final Object? v = msg['F'];
      if (v != null) _filter.value = v.toString();
    }
    if (msg['G'] != null) {
      _groupMode.value = GroupMode.values[i('G', 0).clamp(0, 3)];
    }
    if (msg['N'] != null) _favouritesOnly.value = b('N', _favouritesOnly.value);
    if (msg['k'] != null) {
      final Object? raw = msg['k'];
      if (raw is List) {
        _favourites.value = Set<String>.unmodifiable(
          raw.map((Object? e) => e.toString()),
        );
      }
    }
    if (msg.containsKey('g')) {
      final Object? v = msg['g'];
      _openGroup.value = v?.toString();
    }
    if (msg['u'] != null) _undoAvailable.value = b('u', _undoAvailable.value);
    if (msg['D'] != null) {
      _duration.value = Duration(milliseconds: i('D', 0));
    }
    notifyListeners();
  }

  // ── Intents out ──

  void _send(PlaylistIntent intent, [Map<String, Object?> args = const {}]) {
    sendIntent(<String, Object?>{'t': intent.name, ...args});
  }

  @override
  void playRow(int queueIndex) =>
      _send(PlaylistIntent.playRow, <String, Object?>{'i': queueIndex});

  @override
  void removeRow(int queueIndex) =>
      _send(PlaylistIntent.removeRow, <String, Object?>{'i': queueIndex});

  @override
  void moveRow(int from, int to) =>
      _send(PlaylistIntent.moveRow, <String, Object?>{'f': from, 't': to});

  @override
  void cycleRepeat() => _send(PlaylistIntent.cycleRepeat);

  @override
  void toggleShuffle() => _send(PlaylistIntent.toggleShuffle);

  @override
  void setGroupMode(GroupMode mode) =>
      _send(PlaylistIntent.setGroupMode, <String, Object?>{'m': mode.index});

  @override
  void toggleFavouritesOnly() => _send(PlaylistIntent.toggleFavouritesOnly);

  @override
  void toggleFavourite(int queueIndex) =>
      _send(PlaylistIntent.toggleFavourite, <String, Object?>{'i': queueIndex});

  @override
  void clearPlaylist() => _send(PlaylistIntent.clearPlaylist);

  @override
  void setFilter(String text) =>
      _send(PlaylistIntent.setFilter, <String, Object?>{'f': text});

  @override
  void setOpenGroup(String? group, {required bool user}) =>
      _send(PlaylistIntent.setOpenGroup, <String, Object?>{
        'g': group,
        'u': user,
      });

  @override
  void toggleDock() => _send(PlaylistIntent.dock);

  @override
  void undo() => _send(PlaylistIntent.undo);
}
