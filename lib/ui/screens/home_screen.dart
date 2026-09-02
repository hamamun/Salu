import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/drop_handler.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/custom_title_bar.dart';
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

  /// Unified global hover state: moving the mouse anywhere over the window
  /// reveals the chrome; 3 seconds of stillness hides it again.
  bool _chromeVisible = true;
  Timer? _hideTimer;

  /// Whether files are currently hovering over the window.
  bool _dropHovering = false;

  static const Duration _autoHideDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  // ── Auto-hide logic (Phase 1 · Step 4) ────────────────────────────────

  void _wakeChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      // Keep the chrome up while nothing is playing — there is no video
      // to obstruct, and the user still needs the window controls.
      if (mounted && _player.hasMedia.value) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  // ── Drag & drop (Phase 2 · Step 5) ────────────────────────────────────

  Future<void> _onDropDone(DropDoneDetails details) async {
    setState(() => _dropHovering = false);
    final List<String> paths =
        details.files.map((file) => file.path).toList();
    await DropHandler.handleDroppedPaths(paths);
  }

  // ── Minimal transport for Phase 2 testing ─────────────────────────────
  // (The real center play/pause animation + OSC arrive in Phase 3.)

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
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
