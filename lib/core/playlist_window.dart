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
/// docked panel — one queue, one truth. Closing the loose window hides the
/// playlist view only; playback continues and the next chrome playlist click
/// reopens the docked panel.
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

  /// Polls for the child window's disappearance (its engine ended). The
  /// watchdog is the belt; the plugin's own change event is the braces.
  Timer? _goneWatch;

  /// `onWindowsChanged` — desktop_multi_window broadcasts when a window is
  /// created or destroyed. It is the only proof of death the host can trust:
  /// a window leaves the plugin registry (`getAll()`) exactly when its
  /// engine is torn down, so "not in `getAll()`" = "gone for good". This is
  /// what a dock-back waits on instead of assuming its close landed.
  StreamSubscription<void>? _windowsChanged;

  /// How many times a dock/close asks the child to destroy itself, and how
  /// long each ask waits for proof (50 ms ticks). A healthy child is proven
  /// dead on the first tick; the full budget only burns on one that refuses.
  static const int _kCloseAttempts = 3;
  static const int _kGoneTicks = 6;

  /// Multi-window is only attempted on desktop platforms.
  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// Undock: move the playlist into its own borderless glass window. The
  /// docked panel closes; the state restore travels in the bridge snapshot.
  Future<void> undock() async {
    if (_child != null || !supported) return;
    // The bridge answers BEFORE the child exists — its first handshake
    // ('ready') must never fall into the void.
    _ensureBridge();
    await _reapOrphans();
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

  /// Dock back: reopen the docked slot with the mirrored state, and make sure
  /// the loose window is REALLY gone.
  Future<void> dock() => _retireLooseWindow(openDocked: true, why: 'dock');

  /// The dock-back / close teardown, with proof.
  ///
  /// Two halves, deliberately decoupled:
  ///  · the STATE half (which surface shows the one queue) is this engine's
  ///    own business and flips immediately — it never waits on a window;
  ///  · the WINDOW half belongs to the child: desktop_multi_window 0.3.x
  ///    gives the host `window_show` / `window_hide` only, never a native
  ///    destroy. The child also closes itself after raising the Dock intent
  ///    (`_destroyForDock`), so a dropped host-side invoke is not fatal —
  ///    which is precisely why this VERIFIES instead of assuming.
  ///
  /// The old shape cleared `_child` and cancelled the watchdog BEFORE sending
  /// the close: one lost invoke and the main window had already forgotten the
  /// window it was supposed to kill — a redocked playlist left floating over
  /// the desktop, unreachable by anyone. Now the handle survives until
  /// `getAll()` agrees the engine is gone. A window that still refuses gets
  /// HIDDEN (native; it lands even against a deaf engine), so the worst case
  /// is a zombie nobody sees — reaped by the next undock — never an orphan
  /// sitting in the user's face.
  Future<void> _retireLooseWindow({
    required bool openDocked,
    required String why,
  }) async {
    final WindowController? child = _child;
    final PanelService panel = PanelService.instance;
    panel.playlistUndocked.value = false;
    panel.playlistOpen.value = openDocked;
    if (child == null) return;

    for (int attempt = 0; attempt < _kCloseAttempts; attempt++) {
      if (await _childAlive(child) == false) {
        _finishLooseWindow(openDocked: openDocked);
        return;
      }
      try {
        // The timeout is not ceremony: an engine that is alive but deaf never
        // replies, and this loop is the only thing between the user and a
        // window nobody can close.
        await child
            .invokeMethod<void>('close')
            .timeout(const Duration(milliseconds: 400));
      } catch (e) {
        debugPrint('[SALU] $why/close attempt ${attempt + 1}: $e');
      }
      for (int tick = 0; tick < _kGoneTicks; tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (await _childAlive(child) == false) {
          _finishLooseWindow(openDocked: openDocked);
          return;
        }
      }
    }

    debugPrint('[SALU] $why: the loose window refused to die — hiding it. '
        'window_manager is unreachable in the child engine: check '
        'DesktopMultiWindowSetWindowCreatedCallback → RegisterPlugins in '
        'windows/runner/flutter_window.cpp.');
    try {
      await child.hide();
    } catch (e) {
      debugPrint('[SALU] $why/hide fallback: $e');
    }
    _finishLooseWindow(openDocked: openDocked);
  }

  /// Still in the plugin registry? `null` means the PROBE failed — never read
  /// as a death certificate by the watchdog, and never as "gone" by a dock
  /// that must keep trying. Only an explicit `false` is proof of death.
  Future<bool?> _childAlive(WindowController child) async {
    try {
      final List<WindowController> all = await WindowController.getAll();
      return all.any((WindowController w) => w.windowId == child.windowId);
    } catch (_) {
      return null;
    }
  }

  /// Reap any loose playlist window an earlier dock failed to kill. One queue,
  /// ONE window — a re-undock must never stack a second one on the desktop.
  Future<void> _reapOrphans() async {
    final WindowController? mine = _child;
    try {
      final List<WindowController> all = await WindowController.getAll();
      for (final WindowController w in all) {
        if (w.windowId == mine?.windowId) continue;
        if (!w.arguments.contains(PanelService.kPlaylistWindowArguments)) {
          continue;
        }
        try {
          await w
              .invokeMethod<void>('close')
              .timeout(const Duration(milliseconds: 300));
        } catch (_) {
          try {
            await w.hide();
          } catch (_) {
            // Nothing left that works; it stays out of sight.
          }
        }
      }
    } catch (_) {
      // No registry answer → nothing to reap; the undock proceeds anyway.
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
  ///
  /// [chromeOk] is the child's own verdict on its chrome. When the frame
  /// could not be stripped there is nothing the main window can do about it
  /// (`desktop_multi_window` gives the host no native styling either), so
  /// §13a's abort gate runs here instead: the window is hidden, never shown,
  /// and the docked slot takes the playlist back. SALU does not ship a
  /// native-looking window hanging off a borderless player.
  Future<void> onChildReady({bool chromeOk = true}) async {
    final WindowController? child = _child;
    if (child == null) return;
    if (!chromeOk) {
      debugPrint('[SALU] undock dropped: the loose window could not strip its '
          'native Windows bar. Keeping the docked panel (§4.8/§13a) — the '
          'child engine has no window_manager: see '
          'DesktopMultiWindowSetWindowCreatedCallback → RegisterPlugins in '
          'windows/runner/flutter_window.cpp.');
      try {
        await child.hide();
      } catch (e) {
        debugPrint('[SALU] hide unstyled loose window: $e');
      }
      // Best effort only: if the child's window_manager is alive enough to
      // close, the orphan dies here instead of lingering hidden until the
      // next undock reaps it.
      try {
        await child
            .invokeMethod<void>('close')
            .timeout(const Duration(milliseconds: 300));
      } catch (_) {}
      _finishLooseWindow(openDocked: true);
      return;
    }
    childReady.value = true;
    _attachBridge(child);
    // The snapshot is the ONE message that must land, and it must land before
    // the window is shown: it appears fully formed, never as an empty list
    // that fills a beat later (§4.8's hidden-at-launch rule).
    await _sendChecked(kMsgSnapshot, _snapshot());
    try {
      await child.show();
    } catch (e) {
      debugPrint('[SALU] show loose window: $e');
    }
    _goneWatch ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_checkChildAlive());
    });
    // The plugin's own window-change broadcast beats the poll by up to two
    // seconds: this is what makes "the window really died" arrive the moment
    // it happens — and what reconciles a native caption ✕ instantly.
    _windowsChanged ??= onWindowsChanged.listen((_) {
      unawaited(_checkChildAlive());
    });
  }

  Future<void> _checkChildAlive() async {
    final WindowController? child = _child;
    if (child == null) {
      _stopWatching();
      return;
    }
    // `== false`: proof of death only. A failed probe is not a death
    // certificate, and a wrong guess here closes a live window's slot.
    if (await _childAlive(child) == false) onChildGone();
  }

  void _stopWatching() {
    _goneWatch?.cancel();
    _goneWatch = null;
    final StreamSubscription<void>? changed = _windowsChanged;
    _windowsChanged = null;
    if (changed != null) unawaited(changed.cancel());
  }

  /// Points a method-call invoke at the child (window control channel).
  Future<T?> invokeControl<T>(String method, [Object? args]) async {
    try {
      return await _child?.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  void _finishLooseWindow({required bool openDocked}) {
    _stopWatching();
    _detachBridge();
    _child = null;
    childReady.value = false;
    PanelService.instance.playlistUndocked.value = false;
    PanelService.instance.playlistOpen.value = openDocked;
  }

  // ── Bridge publishing ────────────────────────────────────────────────

  /// Installs the shared bridge channel + the decode routes: the child's
  /// 'ready' handshake and every intent it raises.
  void _ensureBridge() {
    _bridge ??= const WindowMethodChannel(kPlaylistBridgeChannel);
    _bridge!.setMethodCallHandler((call) async {
      switch (call.method) {
        case kMsgReady:
          // 'ready' carries the child's chrome verdict under 'chrome'; an
          // absent flag reads as OK, so nothing is ever dropped for a message
          // this side does not understand.
          final Object? args = call.arguments;
          final bool chromeOk = args is! Map || args['chrome'] != false;
          await onChildReady(chromeOk: chromeOk);
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

  Map<String, Object?> _snapshot() {
    final QueueService queue = QueueService.instance;
    final PlayerService player = PlayerService.instance;
    final PanelService panel = PanelService.instance;
    final ChannelService channel = ChannelService.instance;
    final FavouritesService favs = FavouritesService.instance;
    return playlistSnapshot(
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
    );
  }

  /// A send the caller needs an answer to. The snapshot is the one message no
  /// later delta can repair (a dropped one leaves the loose window showing an
  /// empty queue forever, because deltas only carry what CHANGES), so: await
  /// it, retry once if the child's engine is still wiring its channels or too
  /// busy to answer, and print the failure rather than eating it.
  Future<void> _sendChecked(String method, Object? args) async {
    final WindowMethodChannel? bridge = _bridge;
    if (bridge == null) return;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await bridge
            .invokeMethod<void>(method, args)
            .timeout(const Duration(milliseconds: 800));
        return;
      } catch (e) {
        debugPrint('[SALU] playlist $method, attempt ${attempt + 1}: $e');
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
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
      case 'closePanel':
        // The child is already tearing itself down (`_destroyForClose`) —
        // VERIFY that happened, and hide the window if it cannot: the ✕
        // inside the loose window has to land on screen, not only in state.
        unawaited(_retireLooseWindow(openDocked: false, why: 'close'));
        break;
      default:
        break;
    }
  }

  /// The child window is gone (its engine ended) — reconcile state. An
  /// external/native close hides the playlist view rather than reopening
  /// the dock; an explicit Dock click has already run [dock()].
  void onChildGone() {
    if (PanelService.instance.playlistUndocked.value) {
      _finishLooseWindow(openDocked: false);
    } else {
      _finishLooseWindow(
        openDocked: PanelService.instance.playlistOpen.value,
      );
    }
  }
}
