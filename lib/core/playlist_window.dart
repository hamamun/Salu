import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../ui/panels/playlist_bridge.dart';
import 'channel_service.dart';
import 'favourites_service.dart';
import 'panel_service.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'queue_undo.dart';

/// The main-window side of the undocked playlist (playlist_imp.md §4.8 and
/// §7 step 13). Owns the child window's lifecycle: create (hidden, so no
/// engine-start stutter ever shows), configure, raise on summon, close on
/// dock-back. All state traffic goes through the `PlaylistBridge` seam —
/// see `playlist_bridge.dart`.
///
/// While the window is loose the docked slot stays empty and the control
/// row's mark (and Ctrl+L) SUMMON AND RAISE it instead of opening a second
/// docked panel — one queue, one truth.
class PlaylistWindow {
  PlaylistWindow._();

  static final PlaylistWindow instance = PlaylistWindow._();

  /// The loose window's controller (null while docked or unsupported).
  WindowController? _child;

  /// True between create() and the child having said goodbye.
  bool get isUndocked => _child != null;

  /// Set by the bridge host once the child signals 'ready'.
  final ValueNotifier<bool> childReady = ValueNotifier<bool>(false);

  // ── Bridge publishing ──

  /// The broadcast channel both engines share (desktop_multi_window's
  /// per-name message channel).
  WindowMethodChannel? _bridge;

  /// Live listeners fanning service changes into deltas; detached on
  /// dock so a closed window never costs a rebuild.
  final List<VoidCallback> _detach = <VoidCallback>[];

  /// Polls for the child window's disappearance (its engine ended).
  Timer? _goneWatch;

  /// Multi-window is only attempted on desktop platforms.
  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// Undock: move the playlist into its own borderless glass window. The
  /// docked panel closes; the state restore travels in the bridge snapshot.
  Future<void> undock() async {
    if (_child != null || !supported) return;
    // The bridge answers BEFORE the child exists — its first handshake
    // ('ready') must never fall into the void.
    _ensureBridge();
    try {
      _child = await WindowController.create(
        const WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: PanelService.kPlaylistWindowArguments,
        ),
      );
      PanelService.instance.playlistOpen.value = false;
      PanelService.instance.playlistUndocked.value = true;
    } catch (e) {
      // The frameless-child-window spike failed at runtime: undock drops
      // out — the header keeps four marks and the docked panel remains the
      // only surface (playlist_imp.md §4.8, the §13a abort gate).
      debugPrint('[SALU] undock unavailable: $e');
      _child = null;
      PanelService.instance.playlistUndocked.value = false;
      PanelService.instance.playlistOpen.value = true;
    }
  }

  /// Dock back: close the loose window; the docked slot reopens with the
  /// mirrored state. Closing the window's own caption ✕ routes here too —
  /// closing = docking, never "delete the playlist".
  Future<void> dock() async {
    final WindowController? child = _child;
    if (child == null) return;
    PanelService.instance.playlistUndocked.value = false;
    PanelService.instance.playlistOpen.value = true;
    _goneWatch?.cancel();
    _goneWatch = null;
    _detachBridge();
    _child = null;
    childReady.value = false;
    try {
      await child.invokeMethod<void>('close');
    } catch (e) {
      debugPrint('[SALU] dock/close: $e');
    }
  }

  /// Summon and raise the loose window (the mark / Ctrl+L while undocked),
  /// with a brief outline pulse so it is found again among other windows.
  Future<void> summon() async {
    final WindowController? child = _child;
    if (child == null) return;
    try {
      await child.show();
      await child.invokeMethod<void>('focus');
      await child.invokeMethod<void>('pulse');
    } catch (e) {
      debugPrint('[SALU] summon: $e');
    }
  }

  /// The child said 'ready' — publish the snapshot, hook the deltas and
  /// bring it on screen (fully formed: frameless, glass, right size —
  /// never a native title bar flash).
  Future<void> onChildReady() async {
    final WindowController? child = _child;
    if (child == null) return;
    childReady.value = true;
    _attachBridge(child);
    _publishSnapshot();
    try {
      await child.show();
    } catch (e) {
      debugPrint('[SALU] show loose window: $e');
    }
    _goneWatch ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_checkChildAlive());
    });
  }

  Future<void> _checkChildAlive() async {
    final WindowController? child = _child;
    if (child == null) {
      _goneWatch?.cancel();
      _goneWatch = null;
      return;
    }
    try {
      final List<WindowController> all =
          await WindowController.getAll();
      if (!all.any((WindowController w) => w.windowId == child.windowId)) {
        onChildGone();
      }
    } catch (_) {
      // A failed probe is not a death certificate.
    }
  }

  /// Points a method-call invoke at the child (window control channel).
  Future<T?> invokeControl<T>(String method, [Object? args]) async {
    try {
      return await _child?.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  // ── Bridge publishing ────────────────────────────────────────────────

  /// Installs the shared bridge channel + the decode routes: the child's
  /// 'ready' handshake and every intent it raises.
  void _ensureBridge() {
    _bridge ??= const WindowMethodChannel(kPlaylistBridgeChannel);
    _bridge!.setMethodCallHandler((call) async {
      switch (call.method) {
        case kMsgReady:
          await onChildReady();
          break;
        case kMsgIntent:
          _dispatchIntent(call.arguments);
          break;
      }
      return null;
    });
  }

  void _attachBridge(WindowController child) {
    void sub<T>(ValueListenable<T> src, void Function() fire) {
      void listener() => fire();
      src.addListener(listener);
      _detach.add(() => src.removeListener(listener));
    }

    final QueueService queue = QueueService.instance;
    final PlayerService player = PlayerService.instance;
    final PanelService panel = PanelService.instance;
    final ChannelService channel = ChannelService.instance;
    final FavouritesService favs = FavouritesService.instance;
    final QueueUndoService undo = QueueUndoService.instance;

    sub<List<QueueItem>>(queue.items,
        () => _sendDelta(<String, Object?>{
              'i': <Map<String, String>>[
                for (final QueueItem it in queue.items.value) queueItemToMap(it)
              ],
            }));
    sub<int>(queue.index,
        () => _sendDelta(<String, Object?>{'x': queue.index.value}));
    sub<RepeatMode>(player.repeatMode,
        () => _sendDelta(<String, Object?>{'R': player.repeatMode.value.index}));
    sub<bool>(player.shuffleOn,
        () => _sendDelta(<String, Object?>{'S': player.shuffleOn.value}));
    sub<Duration>(player.duration,
        () => _sendDelta(<String, Object?>{
              'D': player.duration.value.inMilliseconds,
            }));
    sub<String>(panel.filterText,
        () => _sendDelta(<String, Object?>{'F': panel.filterText.value}));
    sub<GroupMode>(channel.groupMode,
        () => _sendDelta(<String, Object?>{'G': channel.groupMode.value.index}));
    sub<bool>(channel.favouritesOnly,
        () => _sendDelta(<String, Object?>{'N': channel.favouritesOnly.value}));
    sub<String?>(channel.openGroup,
        () => _sendDelta(<String, Object?>{'g': channel.openGroup.value}));
    sub<Set<String>>(favs.currentKeys,
        () => _sendDelta(<String, Object?>{
              'k': favs.currentKeys.value.toList(growable: false),
            }));
    sub<bool>(undo.available,
        () => _sendDelta(<String, Object?>{'u': undo.available.value}));
  }

  void _detachBridge() {
    for (final VoidCallback f in _detach) {
      f();
    }
    _detach.clear();
  }

  void _publishSnapshot() {
    final QueueService queue = QueueService.instance;
    final PlayerService player = PlayerService.instance;
    final PanelService panel = PanelService.instance;
    final ChannelService channel = ChannelService.instance;
    final FavouritesService favs = FavouritesService.instance;
    _send(kMsgSnapshot, playlistSnapshot(
      queue.items.value,
      queue.index.value,
      repeatMode: player.repeatMode.value.index,
      shuffle: player.shuffleOn.value,
      filter: panel.filterText.value,
      groupMode: channel.groupMode.value.index,
      favouritesOnly: channel.favouritesOnly.value,
      favouriteKeys: favs.currentKeys.value,
      openGroup: channel.openGroup.value,
      undo: QueueUndoService.instance.available.value,
      durationMs: player.duration.value.inMilliseconds,
    ));
  }

  void _sendDelta(Map<String, Object?> delta) => _send(kMsgDelta, delta);

  void _send(String method, Object? args) {
    try {
      unawaited(_bridge?.invokeMethod<void>(method, args));
    } catch (_) {
      // A window mid-death may drop sends; deltas are re-synced on the
      // next state change anyway.
    }
  }

  /// An intent arrives from the loose window — dispatch to the real
  /// services. State never mutates off the player process.
  void _dispatchIntent(Object? raw) {
    if (raw is! Map) return;
    final Object? type = raw['t'];
    final PanelService panel = PanelService.instance;
    final PlayerService player = PlayerService.instance;
    final ChannelService channel = ChannelService.instance;
    final FavouritesService favs = FavouritesService.instance;
    final QueueUndoService undo = QueueUndoService.instance;
    final QueueService queue = QueueService.instance;

    int argI(String k) {
      final Object? v = raw[k];
      return v is int ? v : (v is num ? v.toInt() : 0);
    }

    switch (type?.toString()) {
      case 'playRow':
        player.playIndex(argI('i'));
        break;
      case 'removeRow':
        undo.removeRow(argI('i'));
        break;
      case 'moveRow':
        undo.moveRow(argI('f'), argI('t'));
        break;
      case 'cycleRepeat':
        player.cycleRepeatMode();
        break;
      case 'toggleShuffle':
        player.toggleShuffle();
        break;
      case 'clearPlaylist':
        undo.clearAll();
        break;
      case 'setFilter':
        panel.filterText.value = raw['f']?.toString() ?? '';
        break;
      case 'setGroupMode':
        final int m = argI('m').clamp(0, 3);
        channel.setGroupMode(GroupMode.values[m], queue.items.value);
        break;
      case 'toggleFavouritesOnly':
        channel.toggleFavouritesOnly();
        break;
      case 'toggleFavourite':
        favs.toggleItem(queue.items.value.elementAtOrNull(argI('i')));
        break;
      case 'setOpenGroup':
        channel.setOpenGroup(raw['g']?.toString(),
            user: raw['u'] == true);
        break;
      case 'undo':
        undo.undo();
        break;
      case 'dock':
        unawaited(dock());
        break;
      default:
        break;
    }
  }

  /// The child window is gone (its engine ended) — reconcile state.
  void onChildGone() {
    _goneWatch?.cancel();
    _goneWatch = null;
    _detachBridge();
    _child = null;
    childReady.value = false;
    if (PanelService.instance.playlistUndocked.value) {
      PanelService.instance.playlistUndocked.value = false;
      PanelService.instance.playlistOpen.value = true;
    }
  }
}
