import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_prefs.dart';
import '../../core/drag_drop_handler.dart';
import '../../core/player_service.dart';
import '../../core/stream_manager.dart';
import '../../theme/app_theme.dart';
import '../managers/ui_visibility_manager.dart';
import '../osc/osc_panel.dart';
import '../panels/library_panel.dart';
import '../panels/right_panel_container.dart';
import '../widgets/center_play_pause.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/media_hud.dart';
import '../widgets/osd_indicator.dart';
import 'browser_screen.dart';
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

  /// Whether the left Library sidebar is open (Phase 6 · Step 1).
  bool _libraryOpen = false;

  /// Whether the built-in browser covers the player (Phase 6 · Step 4).
  bool _browserOpen = false;

  @override
  void initState() {
    super.initState();
    // Let the core layers flash OSD messages (resume, smart queue…).
    _player.onOsdMessage = (String message) =>
        OsdController.instance.show(message, icon: Icons.info_outline_rounded);
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

  /// Phase 5 · Step 5 — keyframe seeking by default, exact while Shift is
  /// held (or the reverse when the user flips the Settings toggle).
  void _seekBy(int seconds, {bool shiftHeld = false}) {
    _player.seekByWithMode(Duration(seconds: seconds), shiftHeld: shiftHeld);
    final bool exact =
        AppPrefs.instance.exactSeekByDefault ? !shiftHeld : shiftHeld;
    OsdController.instance.show(
      '${seconds > 0 ? '+' : ''}$seconds s${exact ? ' · exact' : ''}',
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

  void _toggleLibrary() => _setLibraryOpen(!_libraryOpen);

  void _setLibraryOpen(bool open) {
    if (_libraryOpen == open) return;
    setState(() => _libraryOpen = open);
    if (open) {
      UiVisibilityManager.instance.lockInteraction();
    } else {
      UiVisibilityManager.instance.unlockInteraction();
    }
  }

  /// Opens a saved bookmark in the built-in browser, spawning a new tab if
  /// the browser is already visible (Phase 6 · Step 4).
  Future<void> _openBookmark(SavedBookmark bookmark) async {
    _setLibraryOpen(false);
    if (_player.playing.value) {
      await _player.pause();
    }
    setState(() => _browserOpen = true);
    await BrowserController.instance
        .openUrl(bookmark.url, title: bookmark.name);
  }

  /// Returns to the player and frees every WebView2 controller.
  Future<void> _closeBrowser() async {
    setState(() => _browserOpen = false);
    await BrowserController.instance.closeBrowser();
  }

  void _openSettings() => SettingsScreen.show(context);

  // ── Drag & drop (Phase 5 · Step 1) ────────────────────────────────────

  /// Phase 5 · Step 1 — the drop zone depends on where the files landed:
  /// over the open Playlist panel they are appended, anywhere else they
  /// replace the queue and start playing.
  Future<void> _onDropDone(DropDoneDetails details) async {
    setState(() => _dropHovering = false);
    final List<String> paths =
        details.files.map((DropItem file) => file.path).toList();
    final DropZone zone = _zoneForPosition(details.localPosition);
    final DropResult result =
        await DragDropHandler.handle(paths, zone: zone);
    if (result.handled && result.message.isNotEmpty) {
      OsdController.instance
          .show(result.message, icon: Icons.file_download_outlined);
    }
  }

  /// The right Quick Settings panel is 340 px wide; a drop inside it while
  /// the Playlist tab is showing counts as a playlist drop.
  DropZone _zoneForPosition(Offset position) {
    if (!_rightPanelOpen) return DropZone.mainScreen;
    final double width = MediaQuery.of(context).size.width;
    return position.dx >= width - 340
        ? DropZone.playlistPanel
        : DropZone.mainScreen;
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────────

  bool get _shiftHeld {
    final Set<LogicalKeyboardKey> pressed =
        HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // The browser owns the keyboard while it is open.
    if (_browserOpen) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-5, shiftHeld: _shiftHeld);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(5, shiftHeld: _shiftHeld);
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
    if (_libraryOpen) {
      _setLibraryOpen(false);
      return KeyEventResult.handled;
    }
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

                // 4 · The floating OSC (hidden entirely in browser mode —
                // the streaming site provides its own player controls).
                if (!_browserOpen)
                  OscPanel(
                    onPlayPauseFlash: _togglePlay,
                    onTogglePanel: _togglePanel,
                    onToggleHud: _toggleHud,
                    onToggleLibrary: _toggleLibrary,
                  ),

                // 5 · The built-in browser, covering the player but staying
                // beneath the title bar so window controls remain usable.
                if (_browserOpen)
                  Positioned.fill(
                    top: CustomTitleBar.height,
                    child: BrowserScreen(onCloseBrowser: _closeBrowser),
                  ),

                // 6 · The invisible hover title bar, pinned to the top.
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

                // 7 · Right Quick Settings panel.
                RightPanel(
                  visible: _rightPanelOpen,
                  onClose: () => _setPanelOpen(false),
                  onOpenSettings: _openSettings,
                ),

                // 8 · Left Library sidebar (streams + bookmarks).
                LibraryPanel(
                  visible: _libraryOpen,
                  onClose: () => _setLibraryOpen(false),
                  onOpenBookmark: _openBookmark,
                ),

                // 9 · Media Inspector HUD.
                const MediaHud(),

                // 10 · OSD indicator (top-right).
                const OsdIndicator(),

                // 11 · Drop highlight overlay.
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
