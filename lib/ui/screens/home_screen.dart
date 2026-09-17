import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio_display_service.dart';
import '../../core/browser_service.dart';
import '../../core/channel_load_service.dart';
import '../../core/drop_handler.dart';
import '../../core/folder_autoload_service.dart';
import '../../core/lyric_service.dart';
import '../../core/open_media_service.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/settings_service.dart';
import '../../core/transport_actions.dart';
import '../../core/tune/tune_model.dart';
import '../../core/tune_service.dart';
import '../../core/ui_lock.dart';
import '../../core/window_state_service.dart';
import '../../theme/app_theme.dart';
import '../mini/mini_shell.dart';
import '../osc/controller_panel.dart' show ControllerPanel, kChromeBlockHeight;
import '../osc/open_url_dialog.dart';
import '../osd/osd_controller.dart';
import '../osd/osd_deck.dart';
import '../panels/playlist_panel.dart';
import '../panels/track_panel.dart';
import '../panels/tune_panel.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/eq_curve_overlay.dart';
import '../widgets/live_light.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/web_mode_toggle.dart';
import 'browser_screen.dart';
import 'video_screen.dart';

/// SALU's primary (and only) screen — a borderless dark canvas hosting the
/// edge-to-edge video, crowned by the fused top chrome: the invisible hover
/// title bar and the on-screen controller are drawn as ONE continuous glass
/// block (single shared gradient, no borders, no seams, edge to edge) that
/// shows and hides together. When it auto-hides, a thin, display-only
/// progress hairline remains at the very bottom of the window (hidden
/// entirely while STOPPED — a parked queue has no progress to draw).
///
/// Layers, back to front: video canvas → drop overlay → progress hairline
/// → top chrome → slide-out playlist panel → resume-toast click-outside
/// listener → OSD deck.
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
  final OsdController _osd = OsdController.instance;

  /// The one owner of the window's shape (mini.md §9).
  final WindowStateService _windows = WindowStateService.instance;

  /// Player · Web — which surface owns the window (web.md). In Web mode
  /// the video tree is not built at all, exactly like mini's rule: the
  /// browser fills the stage, the OSC and panels are out of work.
  final BrowserService _browser = BrowserService.instance;

  /// Unified global activity state: moving the mouse anywhere over the
  /// window — or pressing a non-transport key — reveals the chrome;
  /// 3 seconds of stillness hides it again, even while idle with nothing
  /// playing. Transport keys are the exception: they drive the OSD deck
  /// only and never wake the chrome (that is the deck's whole point).
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
  /// controller (`kChromeBlockHeight`, public — the OSD deck anchors to
  /// it so the two can never drift). Even before media loads the block
  /// keeps this size so the scrim gradient never jumps.
  static const double _chromeBlockHeight = kChromeBlockHeight;

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
    _settings.titleBarMode.addListener(_onTitleBarModeChanged);
    // The full window and the mini bar are two different trees — swapping
    // between them tears one down and builds the other (mini.md §8 · §9).
    _windows.mode.addListener(_onWindowModeChanged);
    // Player · Web swaps the full tree's CONTENT the same way: the video
    // canvas, the OSC and the panels step out while the browser is on
    // stage (web.md — "No SALU media controls in Web mode").
    _browser.mode.addListener(_onSaluModeChanged);
    // While transient UI (open pill, URL modal) is up, the chrome must
    // not auto-hide beneath it; when the last lock releases, restart the
    // countdown fresh.
    ChromeLock.instance.listenable.addListener(_onChromeLockChanged);
    // Pin-mode rule: when playback stops or pauses, the pinned chrome
    // must come up (a keypress must never kill a pinned chrome).
    _player.transportState.addListener(_onTransportStateChanged);
    // The Tune panel's owner starts mirroring the player here — the same
    // place the first media is opened, so a landed file re-lays its four
    // continua (and answers Auto EQ) before the panel can ever paint.
    TuneService.instance.startWatching();
    // Start the audio canvas listener so lyric visibility updates the
    // metadata/cover surface immediately.
    LyricService.instance.startWatching();
    AudioDisplayService.instance.startWatching();
    _restartHideTimer();

    // Play the file the app was launched with, if any.
    final String? initial = widget.initialFilePath;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A `.m3u` / `.m3u8` launch argument lists as channels through
        // SALU's own parser (playlist_imp.md M55).
        unawaited(
            ChannelLoadService.instance.openSource(initial).then((bool ch) {
          if (ch) return;
          // Single-file open-with — folder auto-load may kick in
          // (autoload_imp.md §2).
          unawaited(FolderAutoloadService.instance.maybeExpand(initial));
        }));
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _settings.titleBarMode.removeListener(_onTitleBarModeChanged);
    _windows.mode.removeListener(_onWindowModeChanged);
    _browser.mode.removeListener(_onSaluModeChanged);
    ChromeLock.instance.listenable.removeListener(_onChromeLockChanged);
    _player.transportState.removeListener(_onTransportStateChanged);
    super.dispose();
  }

  // ── Auto-hide logic ───────────────────────────────────────────────────

  /// A new title bar mode was picked in the settings window — treat it as
  /// activity so the bar stays up for another 3 seconds under the new mode.
  void _onTitleBarModeChanged() => _wakeChrome();

  /// A transient UI lock was acquired or released — wake the chrome and
  /// let the timer logic re-evaluate (it refuses to hide while locked).
  void _onChromeLockChanged() => _wakeChrome();

  /// Transport-state transitions: in "Pin (playback off)" mode, leaving
  /// `playing` (pause AND stop) must pin the chrome up.
  void _onTransportStateChanged() {
    if (_settings.titleBarMode.value == TitleBarMode.pinWhenPlaybackOff &&
        _player.transportState.value != TransportState.playing) {
      _wakeChrome();
    }
  }

  void _wakeChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _restartHideTimer();
  }

  /// A mode switch changes what EXISTS (mini.md §8 · §9): mini has no
  /// panels and no OSD deck, so the full window's surfaces are closed on
  /// the way in — otherwise the playlist would be waiting, still open,
  /// behind a window that is 32 px tall.
  ///
  /// The deck is emptied on BOTH switches: a card raised while the bar was
  /// up (a drop's whisper, a fetch result) must never be left in the slot
  /// to flash the moment the full window returns.
  void _onWindowModeChanged() {
    if (_windows.isMini) {
      PanelService.instance.closePlaylist();
      PanelService.instance.closeTrackPanel();
      PanelService.instance.closeTunePanel();
    }
    _osd.dismiss();
  }

  /// Player · Web — entering Web mode closes every player surface the same
  /// way mini does (web.md: "No SALU media controls in the browser"; the
  /// panels would be waiting behind a page otherwise) and empties the
  /// deck, so no whisper flashes over the first navigation.
  void _onSaluModeChanged() {
    if (_browser.isWeb) {
      PanelService.instance.closePlaylist();
      PanelService.instance.closeTrackPanel();
      PanelService.instance.closeTunePanel();
      _osd.dismiss();
    }
    setState(() {});
    // Coming back to Player mode re-arms the chrome countdown the web
    // branch paused; entering Web the call is simply ignored.
    _restartHideTimer();
  }

  /// The full window in Web mode: the title strip — Player · Web switch at
  /// its LEFT end, the active tab's title centered, settings and the window
  /// buttons unchanged — and below it the browser, all the way to the
  /// edges. While a page owns the screen (the fullscreen hand-off) even the
  /// strip yields; only the web view remains (web.md).
  Widget _buildWeb() {
    return Scaffold(
      backgroundColor: AppColors.videoBackdrop,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: ListenableBuilder(
          listenable: _browser.pageFullscreen,
          builder: (BuildContext context, Widget? _) {
            final bool pageOwnsScreen = _browser.pageFullscreen.value;
            return Column(
              children: <Widget>[
                if (!pageOwnsScreen)
                  Container(
                    color: const Color(0xF0121212),
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _browser.stripTitle,
                      builder:
                          (BuildContext context, String? title, Widget? _) {
                        return CustomTitleBar(
                          visible: true,
                          immersive: true,
                          title: title,
                          onSettings: _openSettings,
                          leading: const WebModeToggle(),
                          showMini: false,
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: BrowserScreen(
                    chromeVisible: !pageOwnsScreen,
                    onOpenSettings: _openSettings,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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

    // Web mode's title strip never auto-hides — there is no OSC block to
    // tuck away; the strip stays until the page takes the screen (which
    // hides it by force, not by timer).
    if (_browser.isWeb) return;

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

  // ── Settings window ────────────────────────────────────────────────────

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

  // ── Drag & drop ────────────────────────────────────────────────────────

  Future<void> _onDropDone(DropDoneDetails details) async {
    final bool playlistOpen = PanelService.instance.playlistOpen.value;
    setState(() => _dropHovering = false);
    // The drop overlay that was holding the bar up just went away — wake
    // the chrome so the freshly loaded title stays visible for 3 seconds.
    _wakeChrome();
    final List<String> paths =
        details.files.map((file) => file.path).toList();
    if (playlistOpen) {
      await DropHandler.appendDroppedToQueue(paths);
    } else {
      await DropHandler.handleDroppedPaths(paths);
    }
  }

  // ── Keyboard (silent set — never printed anywhere; follow.md rule 2) ──
  //
  // Transport keys (Space, arrows, PgUp/PgDn, M, S) drive the OSD deck
  // ONLY — they never wake the chrome. Esc only dismisses the Resume
  // toast. Everything else is activity: the chrome reveals and the
  // 3-second countdown restarts, so keyboard-only usage can't get locked
  // out of the window controls.
  //
  // The one exception is typing: while the focus sits inside a text
  // field (the playlist filter), the bare single-key shortcuts stand
  // down entirely — see [_isTyping] — so the keystroke reaches the
  // field instead of muting, stopping, seeking, or paging.

  /// Whether the keyboard focus currently sits inside an editable field
  /// under this screen (playlist filter, or a browser URL/search field).
  /// While true, the bare single-key shortcuts below stand down so typing
  /// reaches the field: `m` lands in the field instead of triggering a
  /// global binding, arrows move the caret instead of seeking, and Space
  /// types a space instead of pausing. Ctrl combinations stay global —
  /// they never insert text.
  bool get _isTyping {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final bool down = event is KeyDownEvent;
    final bool repeat = event is KeyRepeatEvent;
    if (!down && !repeat) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;

    // Mini has its own, smaller keyboard: the transport set stays live
    // (§5), `M` toggles the bar back to the full window, `Esc` restores it
    // (§4), and every key that would summon a surface mini does not have is
    // simply out of work — nothing below this line is reachable there.
    if (_windows.isMini) {
      return _onMiniKeyEvent(key, down: down, repeat: repeat);
    }

    if (_browser.isWeb) {
      // The browser owns every editable field in Web mode (URL bar,
      // suggestions search, and favourite editor). Let those fields receive
      // all ordinary keystrokes before considering SALU's global shortcuts;
      // otherwise the global M/mini binding swallows the letter "m" in the
      // address bar.
      if (_isTyping) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyM) {
        // No room for a browser in a 32-px strip (mini.md §8) — while Web
        // holds the stage the mini toggle deliberately does nothing.
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _wakeChrome();
      }
      // Everything else a player key could have done (space, arrows,
      // Ctrl+E…) is out of work while the browser has the stage.
      return KeyEventResult.ignored;
    }

    // Esc — dismisses the topmost popup first (follow.md rule 3):
    // resume toast → tune panel → track panel (its Search window is a
    // dialog route and closes itself above this) → playlist panel. With
    // nothing up it is just another key: activity → chrome wakes.
    if (key == LogicalKeyboardKey.escape) {
      if (_osd.isResumeToast) {
        _osd.dismiss();
        return KeyEventResult.handled;
      }
      if (PanelService.instance.tunePanelOpen.value) {
        PanelService.instance.closeTunePanel();
        return KeyEventResult.handled;
      }
      if (PanelService.instance.trackPanelOpen.value) {
        PanelService.instance.closeTrackPanel();
        return KeyEventResult.handled;
      }
      if (PanelService.instance.playlistOpen.value) {
        PanelService.instance.closePlaylist();
        return KeyEventResult.handled;
      }
      _wakeChrome();
      return KeyEventResult.ignored;
    }

    // ── Transport keys: OSD only, no chrome wake ─────────────────────
    //
    // Each bare key below yields while typing ([_isTyping]) — the
    // keystroke belongs to the field. Ctrl combinations (the Tune tier
    // next, the open-media set at the bottom) stay global.
    final bool typing = _isTyping;
    if (!typing && key == LogicalKeyboardKey.space) {
      TransportActions.instance.playOrPause();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowLeft) {
      TransportActions.instance.seekBackward();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowRight) {
      TransportActions.instance.seekForward();
      return KeyEventResult.handled;
    }
    // ── Tune: the silent keyboard tier (eq_imp.md §6) ──────────────────
    //
    // Ctrl/Cmd + E opens the panel; Ctrl/Cmd + ↑/↓ steps whichever line the
    // pointer last rested on inside it ("one part at a time"), and
    // Ctrl/Cmd + Alt + ↑/↓ walks that focus over the four lines. The deck
    // names the stop, because a closed bar has nothing to show — the same
    // answer the subtitle-sync keys give. The BARE arrows below stay the
    // volume, and a greyed line answers nothing at all: the key falls
    // through, exactly as if the tier were not there.
    final bool tuneCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (tuneCtrl && !repeat && key == LogicalKeyboardKey.keyE) {
      PanelService.instance.toggleTunePanel();
      return KeyEventResult.handled;
    }
    if (tuneCtrl &&
        !repeat &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final int delta = key == LogicalKeyboardKey.arrowDown ? -1 : 1;
      final TuneService tune = TuneService.instance;
      // The card is the answer for the keyboard alone: with the panel open
      // the line already says the same words (the subtitle-sync rule).
      final bool sayIt = !PanelService.instance.tunePanelOpen.value;
      if (HardwareKeyboard.instance.isAltPressed) {
        final TunePart part = tune.moveFocus(delta);
        if (sayIt) {
          _osd.show(OsdTuneCard(part: 'Tune', value: tune.partName(part)));
        }
        return KeyEventResult.handled;
      }
      final TunePart before = tune.focusedPart.value;
      if (tune.nudgeFocused(delta) != null) {
        if (sayIt) {
          _osd.show(OsdTuneCard(
            part: tune.partName(before),
            value: tune.labelFor(before),
          ));
        }
        return KeyEventResult.handled;
      }
    }

    if (!typing && key == LogicalKeyboardKey.arrowUp) {
      TransportActions.instance.volumeUp();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowDown) {
      TransportActions.instance.volumeDown();
      return KeyEventResult.handled;
    }
    // `M` means MINI (mini.md §4 — the preview spells the intent out:
    // "M toggles mini ↔ full"). The old bare-key mute keeps a binding as
    // Ctrl+M so the keyboard never loses it, and the speaker mark in the
    // cluster is unchanged in both modes.
    if (!typing &&
        key == LogicalKeyboardKey.keyM &&
        !HardwareKeyboard.instance.isControlPressed) {
      unawaited(_windows.toggleMini());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM &&
        HardwareKeyboard.instance.isControlPressed) {
      TransportActions.instance.toggleMute();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.keyS) {
      TransportActions.instance.stop();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.pageUp) {
      TransportActions.instance.previous();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.pageDown) {
      TransportActions.instance.next();
      return KeyEventResult.handled;
    }

    // Subtitle sync (owner 2026-09-13) — mpv's own convention: Z shifts
    // the text 100 ms earlier, X 100 ms later. Shift is SALU's coarse
    // second (mpv has no coarse step). Silent while no subtitle track is
    // selected; the deck names the new offset (see `TransportActions
    // .subtitleSync`). Same family as the transport keys above: OSD
    // only, no chrome wake.
    if (!typing &&
        (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyX)) {
      // Bare keys only: Ctrl/Alt stay out of SALU's way (Ctrl+Z is the
      // world's undo, and the Search window has text fields in it).
      final bool bare = !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed;
      if (bare) {
        TransportActions.instance.subtitleSync(
          later: key == LogicalKeyboardKey.keyX,
          coarse: HardwareKeyboard.instance.isShiftPressed,
        );
        return KeyEventResult.handled;
      }
    }

    // ── Everything else: activity → reveal the chrome ────────────────
    _wakeChrome();

    if (!down) return KeyEventResult.ignored; // repeats never re-open UI

    // Silent open-media shortcuts (never printed anywhere in the UI —
    // follow.md hard rule 2).
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && key == LogicalKeyboardKey.keyO) {
      OpenMediaService.openFiles();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyF) {
      OpenMediaService.openFolder();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyU) {
      showOpenUrlDialog(context);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyL) {
      PanelService.instance.togglePlaylist();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Mini's keyboard (mini.md §4 · §5).
  ///
  /// LIVE: the transport set — Space, ←/→ (ramp seeks), ↑/↓ (volume),
  /// S, PageUp/PageDown, and the subtitle-sync pair Z/X, whose OSD card
  /// becomes the bar's own title swap (the shell owns the mapping).
  ///
  /// MODE: `M` toggles back to the full window, `Esc` restores it — the
  /// keyboard twins of the Restore glyph.
  ///
  /// OUT OF WORK: everything that opens a surface the bar does not have
  /// (§8) — Ctrl+E's Tune panel, Ctrl+L's playlist, Ctrl+U's URL modal,
  /// the Ctrl+arrows tune tier, and the settings window. `typing` still
  /// stands the bare single keys down, so the guard survives even if a
  /// field is ever focused inside mini.
  ///
  /// `M` here means the same thing it means in full mode (mini.md §4's
  /// toggle, back to the full window); `Ctrl+M` is the mute, kept
  /// identical in both modes.
  KeyEventResult _onMiniKeyEvent(
    LogicalKeyboardKey key, {
    required bool down,
    required bool repeat,
  }) {
    final bool typing = _isTyping;

    if (key == LogicalKeyboardKey.escape) {
      if (!repeat) unawaited(_windows.exitMini());
      return KeyEventResult.handled;
    }
    if (!typing &&
        down &&
        key == LogicalKeyboardKey.keyM &&
        !HardwareKeyboard.instance.isControlPressed) {
      unawaited(_windows.toggleMini());
      return KeyEventResult.handled;
    }
    // Mute keeps its key with the modifier, and the bar's speaker mark
    // answers the same gesture it answers in full mode. `down` only, so a
    // held key cannot flap the mute the way a repeat would.
    if (!typing &&
        down &&
        key == LogicalKeyboardKey.keyM &&
        HardwareKeyboard.instance.isControlPressed) {
      TransportActions.instance.toggleMute();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.space) {
      TransportActions.instance.playOrPause();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowLeft) {
      TransportActions.instance.seekBackward();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowRight) {
      TransportActions.instance.seekForward();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowUp) {
      TransportActions.instance.volumeUp();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.arrowDown) {
      TransportActions.instance.volumeDown();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.keyS) {
      TransportActions.instance.stop();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.pageUp) {
      TransportActions.instance.previous();
      return KeyEventResult.handled;
    }
    if (!typing && key == LogicalKeyboardKey.pageDown) {
      TransportActions.instance.next();
      return KeyEventResult.handled;
    }
    if (!typing &&
        (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyX)) {
      final bool bare = !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed;
      if (bare) {
        TransportActions.instance.subtitleSync(
          later: key == LogicalKeyboardKey.keyX,
          coarse: HardwareKeyboard.instance.isShiftPressed,
        );
        return KeyEventResult.handled;
      }
    }
    // Nothing else has a surface to talk to here (no chrome, no panels, no
    // deck), so the key is simply left alone.
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The mode swap IS the tree swap (mini.md §9): in mini the full tree —
    // video canvas, chrome, panels, deck — is simply not built (§8).
    return ValueListenableBuilder<WindowMode>(
      valueListenable: _windows.mode,
      builder: (BuildContext context, WindowMode mode, Widget? _) {
        return mode == WindowMode.mini ? _buildMini() : _buildFull();
      },
    );
  }

  /// The mini bar's root: the bar itself, under the same drop + keyboard
  /// surface the full window has (mini.md §5 — dropping stays, hotkeys stay
  /// live while the bar has focus). Everything else is absent on purpose.
  Widget _buildMini() {
    return Scaffold(
      // Transparent: the bar paints its own rounded surface, so the 8 px
      // corners let the desktop through (mini.md §2 · the preview's own
      // look).
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: DropTarget(
          // Drop follows full mode's rules exactly, panels included: with
          // no playlist open a drop plays, and `_onDropDone` reads the same
          // service the full window does.
          onDragEntered: (_) => setState(() => _dropHovering = true),
          onDragExited: (_) => setState(() => _dropHovering = false),
          onDragDone: _onDropDone,
          child: MiniShell(dropHovering: _dropHovering),
        ),
      ),
    );
  }

  /// The full window: video canvas, fused top chrome, panels, deck — the
  /// tree that has always been there. In Web mode the browser paints this
  /// window instead (web.md) — a tree swap, mini's rule reused.
  Widget _buildFull() {
    if (_browser.isWeb) return _buildWeb();

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
                // 1 · The video canvas, stretching edge-to-edge. A tap
                //     goes through the transport facade: pause while
                //     playing, play while paused, RESUME while stopped.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: TransportActions.instance.playOrPause,
                  child: const VideoScreen(),
                ),

                // 1b · The equalizer curve on the picture (eq_imp.md §1.9)
                //      — the mark blown up, faint as grain, over the film
                //      and under everything else. It hides itself when the
                //      curve is Flat, on live media, and when the toggle is
                //      off; it ignores every pointer.
                const Positioned.fill(child: EqCurveOverlay()),

                // 2 · Drop highlight overlay.
                _DropOverlay(
                  visible: _dropHovering,
                  playlistOpen: PanelService.instance.playlistOpen.value,
                ),

                // 3 · The auto-hide hairline — appears at the very bottom
                //     when the chrome hides, and disappears entirely
                //     while STOPPED or idle (a parked queue — or no
                //     queue at all — has no progress to draw).
                _AutoHideProgress(chromeHidden: !chromeVisible),

                // 4 · The unified top chrome — title bar + controller as a
                //     single fused glass block (one gradient, one motion).
                _buildTopChrome(chromeVisible),

                // 5 · The slide-out playlist panel — glass over the video,
                //     anchored below the chrome block (top: kChromeBlockHeight).
                //     Sits under the OSD deck (z-order §4.2) and under the
                //     resume-toast dismiss layer.
                const PlaylistPanel(),

                // 5b · The Fetch button's slide-down track panel (cc.md
                //      §6, D14) — audio / embedded subs / local subs,
                //      live-mirroring mpv. Below the control row on the
                //      right; above the video, below the OSD deck.
                const TrackPanel(),

                // 5c · The Tune panel (eq_imp.md §1.2) — the fourth panel in
                //      the one-popup world: opening it closes the Playlist
                //      and Tracks panels, Esc closes it, and it locks the
                //      chrome awake while it is up.
                const Positioned.fill(child: TunePanel()),

                // 6 · Resume-toast click-outside: dismiss ONLY — never
                //     triggers Restart, never swallows the click (the
                //     translucent listener lets everything beneath keep
                //     working). Sits under the deck, so a click on the
                //     toast itself never lands here.
                ValueListenableBuilder<OsdCard?>(
                  valueListenable: _osd.current,
                  builder: (BuildContext context, OsdCard? card, Widget? _) {
                    if (card is! OsdResumeCard) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => _osd.dismiss(),
                      ),
                    );
                  },
                ),

                // 7 · The OSD deck — top center, anchored below the
                //     chrome block, never waking the chrome.
                const OsdDeck(),
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
                      // nothing — this block owns both). While STOPPED
                      // the title reads SALU (currentTitle is null) —
                      // the parked item's name returns on Play.
                      ValueListenableBuilder<String?>(
                        valueListenable: _player.currentTitle,
                        builder: (BuildContext context, String? title,
                            Widget? _) {
                          return CustomTitleBar(
                            visible: true,
                            immersive: true,
                            title: title,
                            onSettings: _openSettings,
                            leading: BrowserService.browserSupported
                                ? const WebModeToggle()
                                : null,
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

/// The hairline shown at the window's bottom edge while the chrome is
/// auto-hidden. Hidden entirely while STOPPED (and while idle) — a parked
/// queue has no progress to draw.
///
/// Local mode renders the filled progress (edge to edge). Channel mode
/// renders the still soft light instead — the same [StillSoftLight] as
/// the timeline, brighter (2 px needs the contrast), and the only hairline
/// that ever shows while live: the timeline exists only while the chrome
/// is shown and the hairline only while it is hidden, so the signal hands
/// off and is never duplicated (§10.8c).
///
/// Purely informational: never receives pointer events, and offers no
/// hover/tooltip/click action.
class _AutoHideProgress extends StatelessWidget {
  const _AutoHideProgress({required this.chromeHidden});

  /// Whether the chrome is currently hidden (the hairline's slot).
  final bool chromeHidden;

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
              player.transportState,
              player.isBuffering,
              QueueService.instance.items,
            ]),
            builder: (BuildContext context, Widget? _) {
              // Channel mode: the light, never a progress fill — a live
              // stream has no position (§10.8a–c).
              if (player.isLiveMode) {
                return StillSoftLight(
                  visible: player.isLiveReceiving,
                  peak: 0.5,
                  radiusX: 0.30,
                  radiusY: 4.0,
                  fadeStop: 0.80,
                );
              }
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

  /// Live only while an item actually plays or pauses — stopped/idle
  /// hides it even if the chrome is hidden.
  bool get visible {
    if (!chromeHidden) return false;
    switch (PlayerService.instance.transportState.value) {
      case TransportState.playing:
      case TransportState.paused:
        return true;
      case TransportState.idle:
      case TransportState.stopped:
        return false;
    }
  }
}

/// Soft rounded highlight shown while files hover over the window.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.visible, this.playlistOpen = false});

  final bool visible;
  final bool playlistOpen;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  playlistOpen
                      ? Icons.playlist_add_outlined
                      : Icons.file_download_outlined,
                  size: 34,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 8),
                Text(
                  playlistOpen ? 'Drop to add to playlist' : 'Drop to play',
                  style: const TextStyle(
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
