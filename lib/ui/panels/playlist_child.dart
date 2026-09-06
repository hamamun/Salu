import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';
import 'playlist_bridge.dart';
import 'playlist_panel.dart';

/// The playlist window's OWN process entry (playlist_imp.md §9.2/§9.3):
/// a borderless floating glass window, 3 px drag strip, no OS chrome.
/// It renders the SAME PlaylistPanel over a [MirrorPlaylistStore] —
/// every read comes from bridge deltas, every action is an intent.
///
/// Position & size persist across undocks (last spot wins, app-session
/// style); resize comes from the window borders (the strip is drag-only).
class PlaylistChildShell {
  PlaylistChildShell._();

  static const String _boundsPrefsKey = 'playlist_window_bounds';
  static const Size _defaultSize = Size(340, 560);

  /// Runs the whole child app. Called from `main()` when the engine's
  /// arguments mark it as the playlist window.
  static Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    final WindowController self =
        await WindowController.fromCurrentEngine();
    _self = self;

    final MirrorPlaylistStore store = MirrorPlaylistStore(
      sendIntent: (Map<String, Object?> intent) async {
        try {
          await _bridge.invokeMethod<void>(kMsgIntent, intent);
          return true; // the host took it
        } catch (_) {
          return false; // refused or unanswered — the store may retry
        }
      },
      onDockRequested: _destroyForDock,
      onCloseRequested: _destroyForClose,
    );

    _bridge.setMethodCallHandler((call) async {
      switch (call.method) {
        case kMsgSnapshot:
        case kMsgDelta:
          final Object? raw = call.arguments;
          if (raw is Map) {
            store.apply(raw.cast<Object?, Object?>());
          }
          break;
      }
      return null;
    });

    // Main-window control calls (close = a host-requested dock-back;
    // focus and pulse only affect the loose surface).
    final ValueNotifier<int> pulse = ValueNotifier<int>(0);
    self.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'close':
          // Answer FIRST, then die: an engine cannot reply once its own window
          // is gone, and a missing reply would make the host's verified
          // dock-back read as a failed attempt on the happy path. The host
          // then waits for `getAll()` to prove this window is dead.
          unawaited(_destroyForDock());
          break;
        case 'focus':
          await windowManager.focus();
          break;
        case 'pulse':
          // A brief outline pulse so a buried window is found again.
          pulse.value = pulse.value + 1;
          break;
      }
      return null;
    });

    final bool chromeOk = await _configureWindow();

    runApp(PlaylistChildApp(store: store, pulse: pulse));

    // The window is only SHOWN by the host (hiddenAtLaunch): once the
    // first frame is up, signal ready → the host publishes the snapshot
    // and brings the window on screen fully formed. `chrome` rides along so
    // the host can refuse to show a window wearing a native Windows bar
    // (§13a's abort gate; it never got a chance to run before 'ready').
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bridge.invokeMethod<void>(
        kMsgReady,
        <String, Object?>{'chrome': chromeOk},
      ));
    });
  }

  static const WindowMethodChannel _bridge =
      WindowMethodChannel(kPlaylistBridgeChannel);

  /// This window's own controller — the handle used to PROVE the window is
  /// gone. `WindowController.getAll()` is served by desktop_multi_window
  /// itself, so it answers even in an engine where window_manager cannot.
  static WindowController? _self;

  static bool _closingForDock = false;

  /// Single-flight teardown. The Dock click and the host's 'close' invoke (and
  /// a native WM_CLOSE landing between them) can all fire inside one beat;
  /// two SC_CLOSEs racing the same HWND is how an engine dies half.
  static bool _teardownInFlight = false;

  /// The host already decided to reopen the docked slot. Destroy the
  /// child locally too, because a cross-window close invoke can be lost
  /// while the plugin is tearing engines down.
  static Future<void> _destroyForDock() => _teardownOnce(forDock: true);

  static Future<void> _destroyForClose() => _teardownOnce(forDock: false);

  static Future<void> _teardownOnce({required bool forDock}) async {
    // Set BEFORE the guard: a WM_CLOSE arriving mid-teardown must still read
    // this as a dock, so it never reports a user close (§4.8).
    _closingForDock = forDock;
    if (_teardownInFlight) return;
    _teardownInFlight = true;
    await _persistCurrentBounds();
    await _destroyNativeWindow();
    // Survived every attempt → hand the next trigger a usable flag. The host
    // keeps asking until `getAll()` agrees this window is dead; a fresh
    // undock always starts with this flag false, because this isolate itself
    // is created and destroyed with the window.
    if (await _stillRegistered()) _teardownInFlight = false;
  }

  /// True while this window is still in desktop_multi_window's registry
  /// (an engine leaves it only when it is torn down).
  static Future<bool> _stillRegistered() async {
    final WindowController? self = _self;
    if (self == null) return false;
    try {
      final List<WindowController> all = await WindowController.getAll();
      return all.any((WindowController w) => w.windowId == self.windowId);
    } catch (_) {
      // A failed probe out of a half-dead engine is not evidence of life.
      return false;
    }
  }

  /// Header drag (the strip the whole panel hangs from). Failure-tolerant and
  /// CAUGHT, not just wrapped: `startDragging()` is async, so a throw from a
  /// window_manager this engine cannot reach would surface as an unhandled
  /// zone error on every drag gesture. Worst case there is no drag; the window
  /// is still movable by its native caption, if it has one.
  static Future<void> dragWindow() async {
    try {
      await windowManager.startDragging();
    } catch (e) {
      debugPrint('[SALU] playlist window drag unavailable: $e');
    }
  }

  static Future<void> _persistCurrentBounds() async {
    try {
      final Offset pos = await windowManager.getPosition();
      final Size size = await windowManager.getSize();
      await saveBounds(
        Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
      );
    } catch (_) {}
  }

  /// Native caption/Alt+F4 close: this hides the playlist only. Playback
  /// and the queue stay in the main process exactly as they were; the
  /// next chrome playlist click opens the docked panel again.
  static Future<void> notifyClosedByUser() async {
    try {
      await _bridge
          .invokeMethod<void>(
            kMsgIntent,
            <String, Object?>{'t': PlaylistIntent.closePanel.name},
          )
          .timeout(const Duration(milliseconds: 800), onTimeout: () {});
    } catch (_) {}
  }

  /// Closes this window for real.
  ///
  /// **The order here is the fix.** On Windows `windowManager.destroy()` is
  /// literally `PostQuitMessage(0)` (window_manager 0.5.x, window_manager.cpp)
  /// — it quits a message loop, it never closes the HWND. `close()` is the
  /// call that posts SC_CLOSE and actually kills the window, and it is
  /// swallowed while `preventClose` is on — which is exactly what the
  /// caption ✕ / Alt+F4 "hide the view only" path needs (§4.8). So: release
  /// the guard, close, PROVE it died, and keep `destroy()` as last resort.
  /// (The old shape called `destroy()` first and hid the working pair in a
  /// `catch` that could never fire.)
  ///
  /// Failures are LOUD, never silent: a throw here almost always means
  /// window_manager is not registered in this engine at all, i.e. the app
  /// stopped handing child engines their plugins — see
  /// `DesktopMultiWindowSetWindowCreatedCallback` in
  /// `windows/runner/flutter_window.cpp`. Swallowing that is what left a
  /// redocked playlist floating on the desktop with nobody able to reach it.
  static Future<void> _destroyNativeWindow() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
      for (int tick = 0; tick < 6; tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!await _stillRegistered()) return;
      }
      await windowManager.destroy();
      debugPrint('[SALU] playlist window: SC_CLOSE left the window alive — '
          'fell back to destroy().');
    } catch (e) {
      debugPrint('[SALU] playlist window: it cannot close itself ($e). If this '
          'is a MissingPluginException, window_manager is not registered in '
          'the child engine — check DesktopMultiWindowSetWindowCreatedCallback '
          '→ RegisterPlugins in windows/runner/flutter_window.cpp.');
      try {
        await windowManager.destroy();
      } catch (e2) {
        debugPrint(
            '[SALU] playlist window: destroy() fallback failed too: $e2');
      }
    }
  }

  /// The loose window's chrome contract (playlist_imp.md §9.2): SALU's glass,
  /// **no Windows bar, no caption buttons** — `TitleBarStyle.hidden` is the
  /// very mechanism the player window uses (window_manager eats
  /// WM_NCCALCSIZE, so the caption strip belongs to the Flutter view and the
  /// panel's own header carries the drag area and our ✕). The style is
  /// applied twice — inside `waitUntilReadyToShow` and again once the frame
  /// exists — because this is the one property the window must never ship
  /// without.
  ///
  /// Every step is guarded ON ITS OWN, and the answer says whether the native
  /// bar is actually gone: one try/catch around the whole list meant a single
  /// early throw left the glass hanging off a native title bar, silently. A
  /// `false` here travels to the host with 'ready', and the host keeps the
  /// window off screen (§13a's abort gate — a native-looking window is
  /// dropped, not shipped).
  static Future<bool> _configureWindow() async {
    final bool bound = await _bestEffort(
      'bind window_manager to this engine',
      windowManager.ensureInitialized,
    );
    if (!bound) return false; // without the binding nothing else can answer
    final _Bounds bounds = await _Bounds.load();
    final bool framed = await _bestEffort('size + position + glass', () {
      return windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: bounds.size ?? _defaultSize,
          title: 'SALU Playlist',
          backgroundColor: const Color(0x00000000),
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        ),
        () async {
          if (bounds.topLeft != null) {
            await windowManager.setPosition(bounds.topLeft!);
          }
        },
      );
    });
    final bool bare = await _bestEffort('strip the Windows bar', () async {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setHasShadow(true);
    });
    // The caption ✕ / Alt+F4 must HIDE the view, never clear the queue
    // (§4.8) — the close is intercepted and answered in onWindowClose.
    await _bestEffort(
      'preventClose',
      () => windowManager.setPreventClose(true),
    );
    return framed && bare;
  }

  /// One chrome step, on its own. A failure prints WHY and reports `false`;
  /// it never cancels the steps that would still have worked.
  static Future<bool> _bestEffort(
    String what,
    Future<void> Function() run,
  ) async {
    try {
      await run();
      return true;
    } catch (e) {
      debugPrint('[SALU] playlist window: $what FAILED: $e — if this is '
          'MissingPluginException, child engines have no plugins: see '
          'DesktopMultiWindowSetWindowCreatedCallback → RegisterPlugins in '
          'windows/runner/flutter_window.cpp.');
      return false;
    }
  }

  /// Persists the bounds so the next undock lands where the last one was.
  static Future<void> saveBounds(Rect bounds) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _boundsPrefsKey,
        jsonEncode(<String, double>{
          'l': bounds.left,
          't': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        }),
      );
    } catch (_) {}
  }
}

class _Bounds {
  _Bounds(this.topLeft, this.size);

  final Offset? topLeft;
  final Size? size;

  static Future<_Bounds> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw =
          prefs.getString(PlaylistChildShell._boundsPrefsKey);
      if (raw == null) return _Bounds(null, null);
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return _Bounds(null, null);
      double? numOf(String k) {
        final Object? v = decoded[k];
        return v is num ? v.toDouble() : null;
      }

      final double? l = numOf('l'), t = numOf('t');
      final double? w = numOf('w'), h = numOf('h');
      return _Bounds(
        (l != null && t != null) ? Offset(l, t) : null,
        (w != null && h != null) ? Size(w, h) : null,
      );
    } catch (_) {
      return _Bounds(null, null);
    }
  }
}

/// The child window's one screen: the playlist panel, full-bleed inside
/// its rounded frame. No title bar, no second chrome — the panel's own
/// header carries everything (§9.3).
class PlaylistChildApp extends StatelessWidget {
  const PlaylistChildApp({
    super.key,
    required this.store,
    required this.pulse,
  });

  final MirrorPlaylistStore store;
  final ValueNotifier<int> pulse;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: PlaylistChildWindow(store: store, pulse: pulse),
    );
  }
}

class PlaylistChildWindow extends StatefulWidget {
  const PlaylistChildWindow({
    super.key,
    required this.store,
    required this.pulse,
  });

  final MirrorPlaylistStore store;
  final ValueNotifier<int> pulse;

  @override
  State<PlaylistChildWindow> createState() => _PlaylistChildWindowState();
}

class _PlaylistChildWindowState extends State<PlaylistChildWindow>
    with WindowListener {
  Timer? _boundsWrite;
  bool _handlingWindowClose = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _boundsWrite?.cancel();
    super.dispose();
  }

  @override
  void onWindowMoved() => _scheduleBoundsWrite();

  @override
  void onWindowResized() => _scheduleBoundsWrite();

  @override
  void onWindowClose() async {
    if (_handlingWindowClose) return;
    _handlingWindowClose = true;
    _boundsWrite?.cancel();
    await _persistBounds();
    // Tell the host only when THIS engine is the one that noticed the close.
    // A dock/✕ teardown already in flight means the host raised it, and a
    // second closePanel intent mid-teardown is a round-trip nobody asked for.
    if (!PlaylistChildShell._closingForDock &&
        !PlaylistChildShell._teardownInFlight) {
      await PlaylistChildShell.notifyClosedByUser();
    }
    // Through the single-flight teardown, not straight at _destroyNativeWindow:
    // a native close racing the Dock click must not fire a second SC_CLOSE.
    await PlaylistChildShell
        ._teardownOnce(forDock: PlaylistChildShell._closingForDock);
  }

  void _scheduleBoundsWrite() {
    _boundsWrite?.cancel();
    _boundsWrite =
        Timer(const Duration(milliseconds: 600), _persistBounds);
  }

  Future<void> _persistBounds() => PlaylistChildShell._persistCurrentBounds();

  /// Esc (panel closed-ladder end rung in its own window) and Ctrl+L dock
  /// the window back — never die, never leave an orphan.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        (ctrl && event.logicalKey == LogicalKeyboardKey.keyL)) {
      widget.store.toggleDock();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          // A hair of outer space so the rounded glass reads as floating.
          padding: const EdgeInsets.all(6),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PlaylistPanel(
                store: widget.store,
                inOwnWindow: true,
                onDragStart: () => unawaited(PlaylistChildShell.dragWindow()),
              ),
              // The summon pulse: one quick accent ring, then gone.
              ValueListenableBuilder<int>(
                valueListenable: widget.pulse,
                builder: (BuildContext context, int tick, Widget? _) {
                  if (tick == 0) return const SizedBox.shrink();
                  return IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<int>(tick),
                      tween: Tween<double>(begin: 0.55, end: 0),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (BuildContext context, double a, Widget? _) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.accent.withAlpha(
                                  (a * 255).round().clamp(0, 255).toInt(),
                                ),
                                width: 1.4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
