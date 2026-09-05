import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/drop_handler.dart';
import '../../core/open_media_service.dart';
import '../../core/player_service.dart';
import '../../core/settings_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart';
import '../osc/open_url_dialog.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/settings_dialog.dart';
import 'video_screen.dart';

/// SALU's primary (and only) screen — a borderless dark canvas hosting the
/// edge-to-edge video, crowned by the fused top chrome: the invisible hover
/// title bar and the on-screen controller are drawn as ONE continuous glass
/// block (single shared gradient, no borders, no seams, edge to edge) that
/// shows and hides together. When it auto-hides, a thin, display-only
/// progress hairline remains at the very bottom of the window.
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

  /// True while the pointer rests inside the top chrome block (title bar
  /// or controller). While interacting with the controls the chrome never
  /// auto-hides; the countdown starts when the pointer leaves it.
  bool _chromeHovered = false;

  /// Whether files are currently hovering over the window.
  bool _dropHovering = false;

  static const Duration _autoHideDelay = Duration(seconds: 3);

  /// Fixed height of the unified chrome block: 40px title bar + 108px
  /// controller. Even before media loads the block keeps this size so the
  /// scrim gradient never jumps.
  static const double _chromeBlockHeight = 148;

  /// One continuous scrim for the whole chrome block — strong at the very
  /// top (caption buttons), melting away at the block's bottom edge so the
  /// glass block merges into the video with no outline.
  static const List<Color> _scrimColors = <Color>[
    Color(0xF0121212),
    Color(0xE0121212),
    Color(0xC8121212),
    Color(0xB4121212),
    Color(0x99121212),
    Color(0x00121212),
  ];
  static const List<double> _scrimStops = <double>[
    0.0,
    0.2027, // y ≈ 30px
    0.5676, // y ≈ 84px
    0.8243, // y ≈ 122px
    0.9324, // y ≈ 138px
    1.0,
  ];

  @override
  void initState() {
    super.initState();
    // Follow title bar mode changes made from the settings window.
    // (`titleBarMode` is a [ValueNotifier], so it is listened to with
    // addListener/removeListener — it is not a stream.)
    _settings.titleBarMode.addListener(_onTitleBarModeChanged);
    // While transient UI (open pill, URL modal) is up, the chrome must
    // not auto-hide beneath it; when the last lock releases, restart the
    // countdown fresh.
    ChromeLock.instance.listenable.addListener(_onChromeLockChanged);
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
    ChromeLock.instance.listenable.removeListener(_onChromeLockChanged);
    super.dispose();
  }

  // ── Auto-hide logic (Phase 1 · Step 4, extended for the controller) ───

  /// A new title bar mode was picked in the settings window — treat it as
  /// activity so the bar stays up for another 3 seconds under the new mode.
  void _onTitleBarModeChanged() => _wakeChrome();

  /// A transient UI lock was acquired or released — wake the chrome and
  /// let the timer logic re-evaluate (it refuses to hide while locked).
  void _onChromeLockChanged() => _wakeChrome();

  void _wakeChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _restartHideTimer();
  }

  /// The pointer entered the chrome block — keep it visible while the user
  /// works the controls, no matter how still the mouse is.
  void _onChromeEnter() {
    if (!_chromeHovered) setState(() => _chromeHovered = true);
    _wakeChrome();
  }

  /// The pointer left the chrome block — the countdown starts afresh.
  void _onChromeExit() {
    if (_chromeHovered) setState(() => _chromeHovered = false);
    _wakeChrome();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();

    final TitleBarMode mode = _settings.titleBarMode.value;
    // "Locked" — the bar never hides itself; no timer needed.
    if (mode == TitleBarMode.locked) return;

    _hideTimer = Timer(_autoHideDelay, () {
      // While the pointer is inside the chrome (using the controls) the
      // block stays up; the countdown really starts on exit.
      if (_chromeHovered) return;

      // Transient UI (open pill, URL modal) is showing — never hide the
      // chrome beneath it. The lock's release listener restarts the timer.
      if (ChromeLock.instance.isLocked) return;

      // Auto-hide decision after 3s without mouse movement or key presses,
      // per the selected mode (General → Controls in the settings window).
      final bool shouldHide = switch (mode) {
        TitleBarMode.borderless => true,
        TitleBarMode.pinWhenPlaybackOff => _player.isPlaying.value,
        TitleBarMode.locked => false,
      };
      if (mounted && shouldHide && _chromeVisible) {
        // The chrome region may vanish under a parked pointer — reset the
        // flag so a later exit event can't lock the chrome visible forever.
        _chromeHovered = false;
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

  // ── Keyboard transport (Phase 2 testing set) ──────────────────────────

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Any key press counts as activity: reveal the chrome and restart the
    // 3-second countdown, so keyboard-only usage can't get locked out of
    // the window controls.
    _wakeChrome();

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }

    // Silent open-media shortcuts (never printed anywhere in the UI —
    // follow.md hard rule 2).
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyO) {
      OpenMediaService.openFiles();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      OpenMediaService.openFolder();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyU) {
      showOpenUrlDialog(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool chromeVisible = _chromeVisible || _dropHovering;

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

                // 3 · The auto-hide hairline — appears at the very bottom
                // when the chrome hides. Display only: not clickable, not
                // draggable, no hover action, no tooltip.
                _AutoHideProgress(visible: !chromeVisible),

                // 4 · The unified top chrome — title bar + controller as a
                // single fused glass block (one gradient, one animation).
                _buildTopChrome(chromeVisible),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopChrome(bool chromeVisible) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !chromeVisible,
        child: Listener(
          // Absorb taps on the chrome's empty areas so they never
          // fall through to the video's play/pause layer. (Raw
          // listener — no gesture arena, so the title bar's
          // double-click-to-maximize still works.)
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {},
          child: AnimatedSlide(
            offset: chromeVisible ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Container(
                height: _chromeBlockHeight,
                alignment: Alignment.topCenter,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _scrimColors,
                    stops: _scrimStops,
                  ),
                ),
                child: MouseRegion(
                  // While the pointer works inside the visible chrome
                  // content, auto-hide is suspended (even without mouse
                  // movement). The region hugs the content — it never
                  // covers the block's invisible glass areas.
                  onEnter: (_) => _onChromeEnter(),
                  onExit: (_) => _onChromeExit(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // The invisible-until-activity title bar
                      // (immersive: paints no scrim and animates
                      // nothing — this block owns both).
                      ValueListenableBuilder<String?>(
                        valueListenable: _player.currentTitle,
                        builder: (BuildContext context, String? title,
                            Widget? _) {
                          return CustomTitleBar(
                            visible: true,
                            immersive: true,
                            title: title,
                            onSettings: _openSettings,
                          );
                        },
                      ),
                      // The controller container, attached directly
                      // beneath the title bar — the two read as one
                      // single window with no outline between them.
                      // It stays visible even when no media is loaded;
                      // only the parent chrome block's auto-hide logic
                      // (configured in Settings) can hide it.
                      const ControllerPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline progress bar shown at the window's bottom edge while the
/// chrome is auto-hidden.
///
/// Purely informational: renders only the filled progress (edge to edge),
/// never receives pointer events, and offers no hover/tooltip/click action.
class _AutoHideProgress extends StatelessWidget {
  const _AutoHideProgress({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 2,
      // Display only: absorb pointer events so the hairline can never be
      // clicked, dragged or scrolled (no seek, no hover action, nothing).
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {},
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              player.position,
              player.duration,
            ]),
            builder: (BuildContext context, Widget? _) {
              final Duration dur = player.duration.value;
              final double frac = dur > Duration.zero
                  ? (player.position.value.inMilliseconds /
                          dur.inMilliseconds)
                      .clamp(0.0, 1.0)
                      .toDouble()
                  : 0.0;
              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double w = constraints.maxWidth;
                  return Stack(
                    children: <Widget>[
                      if (w > 0 && frac > 0)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: w * frac,
                          child: const ColoredBox(color: AppColors.threadFill),
                        ),
                    ],
                  );
                },
              );
            },
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
