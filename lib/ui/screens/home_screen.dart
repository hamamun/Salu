import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/drop_handler.dart';
import '../../core/player_service.dart';
import '../../core/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/settings_dialog.dart';
import 'video_screen.dart';

/// SALU's primary (and only) screen — a borderless dark canvas hosting the
/// edge-to-edge video, crowned by the invisible hover title bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialFilePath});

  /// Media path passed on launch (double-clicked file / "Open with SALU").
  final String? initialFilePath;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerService _player = PlayerService.instance;
  final SettingsService _settings = SettingsService.instance;

  /// Unified global activity state: moving the mouse anywhere over the
  /// window — or pressing any key — reveals the chrome; 3 seconds of
  /// stillness hides it again, even while idle with nothing playing.
  bool _chromeVisible = true;
  Timer? _hideTimer;

  /// Whether files are currently hovering over the window.
  bool _dropHovering = false;

  static const Duration _autoHideDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    // Follow title bar mode changes made from the settings window.
    // (`titleBarMode` is a [ValueNotifier], so it is listened to with
    // addListener/removeListener — it is not a stream.)
    _settings.titleBarMode.addListener(_onTitleBarModeChanged);
    _restartHideTimer();

    // Play the file the app was launched with, if any.
    final String? initial = widget.initialFilePath;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _player.openPath(initial);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _settings.titleBarMode.removeListener(_onTitleBarModeChanged);
    super.dispose();
  }

  // ── Auto-hide logic (Phase 1 · Step 4) ────────────────────────────────

  /// A new title bar mode was picked in the settings window — treat it as
  /// activity so the bar stays up for another 3 seconds under the new mode.
  void _onTitleBarModeChanged() => _wakeChrome();

  void _wakeChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();

    final TitleBarMode mode = _settings.titleBarMode.value;
    // "Locked" — the bar never hides itself; no timer needed.
    if (mode == TitleBarMode.locked) return;

    _hideTimer = Timer(_autoHideDelay, () {
      // Auto-hide decision after 3s without mouse movement or key presses,
      // per the selected mode (General → Controls in the settings window).
      final bool shouldHide = switch (mode) {
        TitleBarMode.borderless => true,
        TitleBarMode.pinWhenPlaybackOff => _player.isPlaying.value,
        TitleBarMode.locked => false,
      };
      if (mounted && shouldHide && _chromeVisible) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  // ── Settings window ─────────────────────────────────────────────────────

  void _openSettings() {
    _wakeChrome();
    // `showGeneralDialog` — unlike `showDialog` — accepts the transition
    // knobs below, so SALU's own fade + scale can drive the dialog in.
    showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) {
        final CurvedAnimation curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) => const SettingsDialog(),
    );
  }

  // ── Drag & drop (Phase 2 · Step 5) ────────────────────────────────────

  Future<void> _onDropDone(DropDoneDetails details) async {
    setState(() => _dropHovering = false);
    // The drop overlay that was holding the bar up just went away — wake
    // the chrome so the freshly loaded title stays visible for 3 seconds.
    _wakeChrome();
    final List<String> paths =
        details.files.map((file) => file.path).toList();
    await DropHandler.handleDroppedPaths(paths);
  }

  // ── Minimal transport for Phase 2 testing ─────────────────────────────
  // (The real center play/pause animation + OSC arrive in Phase 3.)

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Any key press counts as activity: reveal the chrome and restart the
    // 3-second countdown, so keyboard-only usage can't get locked out of
    // the window controls.
    _wakeChrome();

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dropHovering = true),
          onDragExited: (_) => setState(() => _dropHovering = false),
          onDragDone: _onDropDone,
          child: MouseRegion(
            opaque: false,
            onHover: (_) => _wakeChrome(),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 1 · The video canvas, stretching edge-to-edge.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _player.playOrPause,
                  child: const VideoScreen(),
                ),

                // 2 · Drop highlight overlay.
                _DropOverlay(visible: _dropHovering),

                // 3 · The invisible hover title bar, pinned to the top.
                Align(
                  alignment: Alignment.topCenter,
                  child: ValueListenableBuilder<String?>(
                    valueListenable: _player.currentTitle,
                    builder:
                        (BuildContext context, String? title, Widget? _) {
                      return CustomTitleBar(
                        visible: _chromeVisible || _dropHovering,
                        title: title,
                        onSettings: _openSettings,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft rounded highlight shown while files hover over the window.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          margin: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x331E90FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent, width: 2),
          ),
          alignment: Alignment.center,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.file_download_outlined,
                    size: 34, color: AppColors.textPrimary),
                SizedBox(height: 8),
                Text(
                  'Drop to play',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
