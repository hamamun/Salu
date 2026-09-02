import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/drop_handler.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../managers/ui_visibility_manager.dart';
import '../osc/osc_panel.dart';
import '../panels/right_panel_container.dart';
import '../widgets/center_play_pause.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/media_hud.dart';
import '../widgets/osd_indicator.dart';
import 'music_mode.dart';
import 'settings_screen.dart';
import 'video_screen.dart';

/// SALU's primary (and only) screen — a borderless dark canvas hosting the
/// edge-to-edge video, the invisible hover title bar, the floating OSC, and
/// every overlay (HUD, OSD, panels, music mode).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialFilePath});

  /// Media path passed on launch (double-clicked file / "Open with SALU").
  final String? initialFilePath;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerService _player = PlayerService.instance;

  /// Whether files are currently hovering over the window.
  bool _dropHovering = false;

  /// Whether the right Quick Settings panel is open.
  bool _rightPanelOpen = false;

  @override
  void initState() {
    super.initState();
    // Play the file the app was launched with, if any.
    final String? initial = widget.initialFilePath;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _player.openPath(initial);
      });
    }
  }

  // ── Transport helpers ──────────────────────────────────────────────────

  void _togglePlay() {
    final bool wasPlaying = _player.playing.value;
    _player.playOrPause();
    CenterPlayPauseController.instance
        .flash(wasPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded);
  }

  void _seekBy(int seconds) {
    _player.seekBy(Duration(seconds: seconds));
    OsdController.instance.show(
      '${seconds > 0 ? '+' : ''}$seconds s',
      icon: seconds > 0 ? Icons.forward_10_rounded : Icons.replay_10_rounded,
    );
  }

  void _adjustVolume(int delta) {
    final int next = (_player.baseVolume.value + delta).clamp(0.0, 100.0).round();
    _player.setBaseVolume(next.toDouble());
    OsdController.instance.show('Volume $next%', icon: Icons.volume_up_rounded);
  }

  void _togglePanel() => _setPanelOpen(!_rightPanelOpen);

  void _setPanelOpen(bool open) {
    if (_rightPanelOpen == open) return;
    setState(() => _rightPanelOpen = open);
    if (open) {
      UiVisibilityManager.instance.lockInteraction();
    } else {
      UiVisibilityManager.instance.unlockInteraction();
    }
  }

  void _toggleHud() => MediaHudController.instance.toggle();

  void _toggleLibrary() {
    OsdController.instance
        .show('Library arrives in Phase 6', icon: Icons.video_library_outlined);
  }

  void _openSettings() => SettingsScreen.show(context);

  // ── Drag & drop (Phase 2 · Step 5) ────────────────────────────────────

  Future<void> _onDropDone(DropDoneDetails details) async {
    setState(() => _dropHovering = false);
    final List<String> paths =
        details.files.map((DropFile file) => file.path).toList();
    await DropHandler.handleDroppedPaths(paths);
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-5);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(5);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
    } else if (key == LogicalKeyboardKey.keyF) {
      _player.toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyP) {
      _player.togglePip();
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyI) {
      _toggleHud();
    } else if (key == LogicalKeyboardKey.escape) {
      return _handleEscape();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _toggleMute() {
    final bool next = !_player.muted.value;
    _player.setMuted(next);
    OsdController.instance.show(
      next ? 'Muted' : 'Unmuted',
      icon: next ? Icons.volume_off_rounded : Icons.volume_up_rounded,
    );
  }

  KeyEventResult _handleEscape() {
    if (_rightPanelOpen) {
      _setPanelOpen(false);
      return KeyEventResult.handled;
    }
    if (MediaHudController.instance.visible) {
      MediaHudController.instance.hide();
      return KeyEventResult.handled;
    }
    if (_player.fullscreen.value) {
      _player.toggleFullscreen();
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
            onHover: (_) => UiVisibilityManager.instance.wake(),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 1 · The video canvas, stretching edge-to-edge.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _togglePlay,
                  child: const VideoScreen(),
                ),

                // 2 · Music mode (audio-only files).
                const MusicModeOverlay(),

                // 3 · Center-screen play/pause flash.
                const CenterPlayPause(),

                // 4 · The floating OSC.
                OscPanel(
                  onPlayPauseFlash: _togglePlay,
                  onTogglePanel: _togglePanel,
                  onToggleHud: _toggleHud,
                  onToggleLibrary: _toggleLibrary,
                ),

                // 5 · The invisible hover title bar, pinned to the top.
                Align(
                  alignment: Alignment.topCenter,
                  child: ListenableBuilder(
                    listenable: UiVisibilityManager.instance,
                    builder: (BuildContext context, Widget? child) {
                      return ValueListenableBuilder<String?>(
                        valueListenable: _player.currentTitle,
                        builder: (BuildContext context, String? title, Widget? _) {
                          return CustomTitleBar(
                            visible:
                                UiVisibilityManager.instance.visible || _dropHovering,
                            title: title,
                          );
                        },
                      );
                    },
                  ),
                ),

                // 6 · Right Quick Settings panel.
                RightPanel(
                  visible: _rightPanelOpen,
                  onClose: () => _setPanelOpen(false),
                  onOpenSettings: _openSettings,
                ),

                // 7 · Media Inspector HUD.
                const MediaHud(),

                // 8 · OSD indicator (top-right).
                const OsdIndicator(),

                // 9 · Drop highlight overlay.
                _DropOverlay(visible: _dropHovering),
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
