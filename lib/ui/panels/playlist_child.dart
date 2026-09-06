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
    final WindowController self = WindowController.fromCurrentEngine();

    final MirrorPlaylistStore store = MirrorPlaylistStore(
      sendIntent: (Map<String, Object?> intent) {
        try {
          unawaited(
            _bridge.invokeMethod<void>(kMsgIntent, intent),
          );
        } catch (_) {}
      },
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

    // Main-window control calls (close = dock back, focus, pulse).
    final ValueNotifier<int> pulse = ValueNotifier<int>(0);
    self.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'close':
          await windowManager.close();
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

    await _configureWindow();

    runApp(PlaylistChildApp(store: store, pulse: pulse));

    // The window is only SHOWN by the host (hiddenAtLaunch): once the
    // first frame is up, signal ready → the host publishes the snapshot
    // and brings the window on screen fully formed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bridge.invokeMethod<void>(kMsgReady));
    });
  }

  static final WindowMethodChannel _bridge =
      WindowMethodChannel(kPlaylistBridgeChannel);

  static Future<void> _configureWindow() async {
    try {
      await windowManager.ensureInitialized();
      final _Bounds bounds = await _Bounds.load();
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: bounds.size ?? _defaultSize,
          title: 'SALU Playlist',
          backgroundColor: const Color(0x00000000),
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          if (bounds.topLeft != null) {
            await windowManager.setPosition(bounds.topLeft!);
          }
        },
      );
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setHasShadow(true);
    } catch (e) {
      debugPrint('[SALU] playlist window setup (best-effort): $e');
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

  void _scheduleBoundsWrite() {
    _boundsWrite?.cancel();
    _boundsWrite =
        Timer(const Duration(milliseconds: 600), _persistBounds);
  }

  Future<void> _persistBounds() async {
    try {
      final Offset pos = await windowManager.getPosition();
      final Size size = await windowManager.getSize();
      await PlaylistChildShell.saveBounds(
        Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
      );
    } catch (_) {}
  }

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
                onDragStart: () {
                  try {
                    unawaited(windowManager.startDragging());
                  } catch (_) {}
                },
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
