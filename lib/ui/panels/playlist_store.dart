import 'package:flutter/foundation.dart';

import '../../core/channel_service.dart';
import '../../core/favourites_service.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/playlist_window.dart';
import '../../core/queue_service.dart';
import '../../core/queue_undo.dart';

/// The playlist panel's data contract — ONE seam, two implementations
/// (playlist_imp.md §4.8 / M26):
///
///   · [LivePlaylistStore] — the docked panel, reading the app's real
///     singletons directly;
///   · MirrorPlaylistStore (playlist_bridge.dart) — the loose child
///     window, fed by bridge deltas and reporting every action back as an
///     intent.
///
/// When the framework's own windowing API reaches stable this interface
/// disappears and the loose window becomes a subtree reading the real
/// services — with no change to the panel's UI code. Until then the same
/// bridge shape serves Phase 8's Android remote over a WebSocket.
abstract class PlaylistStore extends ChangeNotifier {
  // ── Data (listenables the panel merges) ─────────────────────────────

  /// The real queue/channel order — the only order the list ever shows.
  ValueListenable<List<QueueItem>> get items;

  /// The playing (or parked) index, -1 while empty/parked-out.
  ValueListenable<int> get index;

  /// Player-side modes (mirrored; never authoritatively set by the UI).
  ValueListenable<RepeatMode> get repeatMode;
  ValueListenable<bool> get shuffleOn;

  /// The header's filter text (VIEW-only; never touches the queue).
  ValueListenable<String> get filter;

  /// Current grouping mode (channel lists) and its availability.
  ValueListenable<GroupMode> get groupMode;

  /// Favourites-only browse filter (channel lists).
  ValueListenable<bool> get favouritesOnly;

  /// Favourite keys of the current playlist (channel lists).
  ValueListenable<Set<String>> get favourites;

  /// The accordion's open group (null = all collapsed), channel lists.
  ValueListenable<String?> get openGroup;

  /// Whether a 5 s Undo is currently offered.
  ValueListenable<bool> get undoAvailable;

  /// Whether the playlist currently lives in its own window (slot 5). In
  /// the child window this is always true.
  ValueListenable<bool> get undocked;

  /// The current item's duration (rows show it for the playing row only).
  ValueListenable<Duration> get duration;

  /// Whether this playlist is an m3u channel list — read off the DATA.
  bool get isChannelList;

  /// Whether grouping mode [mode] has any tags in this playlist (un
  /// available modes are dimmed, never hidden — M7).
  bool groupModeAvailable(GroupMode mode);

  /// Whether the playlist carries any favourites at all (dim the
  /// favourites-only slot when there is nothing to browse).
  bool get hasAnyFavourites;

  /// The favourite key of a channel (M11) — null for local files.
  String? favouriteKeyOf(int queueIndex);

  // ── Actions (live: direct; mirror: bridge intents) ──────────────────

  /// Row click = play that index (no "select then load").
  void playRow(int queueIndex);

  /// 🗑 row action: instant removal + 5 s Undo.
  void removeRow(int queueIndex);

  /// `≡` drag reorder (local mode only — m3u rows have no grip).
  void moveRow(int from, int to);

  /// Slot 1 local: cycle repeat off → all → one.
  void cycleRepeat();

  /// Slot 2 local: shuffle on/off (playback order only).
  void toggleShuffle();

  /// Slot 1 channel: pick a grouping mode from the pill.
  void setGroupMode(GroupMode mode);

  /// Slot 2 channel: favourites-only on/off.
  void toggleFavouritesOnly();

  /// Row bookmark (channel lists): favourite toggle by queue index.
  void toggleFavourite(int queueIndex);

  /// Slot 4: clear playlist — absolute, instant, with a 5 s Undo.
  void clearPlaylist();

  /// The field's edit (live filtering as you type).
  void setFilter(String text);

  /// A group head was toggled (user action) or followed playback.
  void setOpenGroup(String? group, {required bool user});

  /// Slot 5: undock ↔ dock back (moves the panel, never copies it).
  void toggleDock();

  /// The toast action: restore the last removable/reorder/clear.
  void undo();
}

/// The docked panel's store: every read is the real singleton; every
/// action is the real service call. Listening is folded into the one
/// [ChangeNotifier] so the panel can watch everything at once.
class LivePlaylistStore extends PlaylistStore {
  LivePlaylistStore() {
    final List<Listenable> listen = <Listenable>[
      QueueService.instance.items,
      QueueService.instance.index,
      PlayerService.instance.repeatMode,
      PlayerService.instance.shuffleOn,
      PlayerService.instance.duration,
      PanelService.instance.filterText,
      PanelService.instance.playlistUndocked,
      ChannelService.instance.groupMode,
      ChannelService.instance.favouritesOnly,
      ChannelService.instance.openGroup,
      FavouritesService.instance.currentKeys,
      QueueUndoService.instance.available,
    ];
    for (final Listenable l in listen) {
      l.removeListener(notifyListeners); // guard against double-attach
      l.addListener(notifyListeners);
    }
  }

  final QueueService _queue = QueueService.instance;

  @override
  ValueListenable<List<QueueItem>> get items => _queue.items;

  @override
  ValueListenable<int> get index => _queue.index;

  @override
  ValueListenable<RepeatMode> get repeatMode =>
      PlayerService.instance.repeatMode;

  @override
  ValueListenable<bool> get shuffleOn => PlayerService.instance.shuffleOn;

  @override
  ValueListenable<String> get filter => PanelService.instance.filterText;

  @override
  ValueListenable<GroupMode> get groupMode =>
      ChannelService.instance.groupMode;

  @override
  ValueListenable<bool> get favouritesOnly =>
      ChannelService.instance.favouritesOnly;

  @override
  ValueListenable<Set<String>> get favourites =>
      FavouritesService.instance.currentKeys;

  @override
  ValueListenable<String?> get openGroup => ChannelService.instance.openGroup;

  @override
  ValueListenable<bool> get undoAvailable => QueueUndoService.instance.available;

  @override
  ValueListenable<bool> get undocked => PanelService.instance.playlistUndocked;

  @override
  ValueListenable<Duration> get duration => PlayerService.instance.duration;

  @override
  bool get isChannelList => _queue.isChannelList;

  @override
  bool groupModeAvailable(GroupMode mode) =>
      ChannelService.instance.modeAvailable(mode, _queue.items.value);

  @override
  bool get hasAnyFavourites =>
      FavouritesService.instance.currentKeys.value.isNotEmpty;

  @override
  String? favouriteKeyOf(int queueIndex) =>
      FavouritesService.favouriteKeyOf(
          _queue.items.value.elementAtOrNull(queueIndex));

  @override
  void playRow(int queueIndex) {
    PlayerService.instance.playIndex(queueIndex);
  }

  @override
  void removeRow(int queueIndex) {
    QueueUndoService.instance.removeRow(queueIndex);
  }

  @override
  void moveRow(int from, int to) {
    QueueUndoService.instance.moveRow(from, to);
  }

  @override
  void cycleRepeat() => PlayerService.instance.cycleRepeatMode();

  @override
  void toggleShuffle() => PlayerService.instance.toggleShuffle();

  @override
  void setGroupMode(GroupMode mode) {
    ChannelService.instance.setGroupMode(mode, _queue.items.value);
  }

  @override
  void toggleFavouritesOnly() =>
      ChannelService.instance.toggleFavouritesOnly();

  @override
  void toggleFavourite(int queueIndex) {
    final QueueItem? item = _queue.items.value.elementAtOrNull(queueIndex);
    FavouritesService.instance.toggleItem(item);
  }

  @override
  void clearPlaylist() => QueueUndoService.instance.clearAll();

  @override
  void setFilter(String text) =>
      PanelService.instance.filterText.value = text;

  @override
  void setOpenGroup(String? group, {required bool user}) {
    ChannelService.instance.setOpenGroup(group, user: user);
  }

  @override
  void toggleDock() {
    if (PanelService.instance.playlistUndocked.value) {
      PlaylistWindow.instance.dock();
    } else {
      PlaylistWindow.instance.undock();
    }
  }

  @override
  void undo() => QueueUndoService.instance.undo();
}
