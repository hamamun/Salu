import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts/shortcut_registry.dart';
import '../../theme/app_theme.dart';
import 'alt_peek.dart' show PeekChip;
import 'glass_capsule.dart';
import 'salu_marks.dart';
import 'transport_marks.dart';
import 'web_marks.dart';

/// Settings → Shortcuts — the Living Map (shortcut.md §4.1).
///
/// A miniature SALU that is alive: the app itself, shrunken, every visible
/// control wearing its keys (the Alt-Peek chip recipe, always visible
/// here), and answering when they are pressed. Pure reference — nothing on
/// it is configurable, and there is no rebind affordance anywhere (§4.0).
///
/// Everything it prints comes from [SaluShortcuts]; a chip without a
/// registry entry cannot exist. The mock never plays real media and keeps
/// no state beyond the open tab — it is a mirror, not a player.
class ShortcutsTab extends StatefulWidget {
  const ShortcutsTab({super.key});

  /// The miniature's design size; narrower windows scale it as one piece.
  static const Size miniatureSize = Size(600, 280);

  @override
  State<ShortcutsTab> createState() => ShortcutsTabState();
}

/// Public for tests (reads the mock's state).
class ShortcutsTabState extends State<ShortcutsTab> {
  final FocusNode _focus = FocusNode(debugLabel: 'ShortcutsTab');

  ShortcutScope mode = ShortcutScope.player;

  /// The entry the detail strip describes — the last one hovered or
  /// pressed.
  ShortcutEntry? selected;
  ShortcutCombo? _selectedCombo;

  // ── The mock (slice B · the liveness engine) ────────────────────────
  bool playing = true;
  double position = 0.32;
  int volume = 62;
  bool muted = false;
  bool fullscreen = false;
  bool playlistOpen = false;
  bool urlModalOpen = false;
  double speed = 1.0;
  int subDelayMs = 0;
  bool shuffle = false;
  int repeatMode = 0; // 0 off · 1 all · 2 one
  int item = 1;
  int audioTrack = 0;
  int subtitleTrack = 1;

  int webTabs = 3;
  int webActive = 0;
  bool addressFocused = false;
  bool findBarOpen = false;
  int findMatch = 1;
  String? webPanel; // history · downloads · favourite · hub · clear
  int zoom = 100;

  /// The mock OSD deck's card (and the mini bar's title swap).
  String? osd;
  Timer? _osdTimer;

  static const List<String> _items = <String>[
    'Northern Lights.mkv',
    'Ocean Drift.mp4',
    'City at Night.mkv',
    'Quiet Hours.flac',
  ];

  @override
  void dispose() {
    _osdTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _flash(String text) {
    _osdTimer?.cancel();
    osd = text;
    _osdTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => osd = null);
    });
  }

  void _select(ShortcutEntry? entry, [ShortcutCombo? combo]) {
    if (entry == null) return;
    setState(() {
      selected = entry;
      _selectedCombo = combo ?? entry.combos.first;
    });
  }

  void _setMode(ShortcutScope next) {
    setState(() {
      mode = next;
      selected = null;
      _selectedCombo = null;
      osd = null;
    });
  }

  static bool _isModifier(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight ||
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight ||
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight;

  /// While the tab is open it swallows the keyboard: every registered key
  /// fires its mock feedback; unregistered keys do nothing. `Esc` follows
  /// the app's own order — panel → fullscreen → (in the app) close
  /// Settings, which is why a spent `Esc` is let through.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (_isModifier(key)) return KeyEventResult.ignored;
    final HardwareKeyboard hw = HardwareKeyboard.instance;
    final bool ctrl = hw.isControlPressed;
    final bool shift = hw.isShiftPressed;
    final bool alt = hw.isAltPressed;

    final ShortcutEntry? entry =
        SaluShortcuts.match(mode, key, ctrl: ctrl, shift: shift, alt: alt);
    if (entry == null) return KeyEventResult.handled;
    ShortcutCombo? combo;
    for (final ShortcutCombo c in entry.combos) {
      if (c.matches(key, ctrl: ctrl, shift: shift, alt: alt)) combo = c;
    }
    final bool repeat = event is KeyRepeatEvent;
    bool handled = true;
    setState(() {
      selected = entry;
      _selectedCombo = combo;
      handled = _apply(entry, key, repeat: repeat);
    });
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Plays [entry]'s mock feedback. Returns false only for an `Esc` with
  /// nothing left to close — that one belongs to the Settings window.
  bool _apply(ShortcutEntry entry, LogicalKeyboardKey key,
      {required bool repeat}) {
    String vol() => muted ? 'Muted' : 'Volume $volume %';
    String delay() =>
        'Subtitle delay ${subDelayMs >= 0 ? '+' : '−'}${(subDelayMs.abs() / 1000).toStringAsFixed(1)} s';
    String spd() => 'Speed ${speed.toStringAsFixed(1)}×';

    switch (entry.id) {
      // ── Player + mini transport ─────────────────────────────────────
      case 'player.playPause':
      case 'mini.playPause':
        if (repeat) return true;
        playing = !playing;
        _flash(playing ? 'Play' : 'Pause');
      case 'player.seekBack':
      case 'mini.seekBack':
        position = (position - 0.02).clamp(0.0, 1.0);
        _flash('−5 s');
      case 'player.seekForward':
      case 'mini.seekForward':
        position = (position + 0.02).clamp(0.0, 1.0);
        _flash('+5 s');
      case 'player.volumeUp':
      case 'mini.volumeUp':
        muted = false;
        volume = (volume + 5).clamp(0, 100);
        _flash(vol());
      case 'player.volumeDown':
      case 'mini.volumeDown':
        muted = false;
        volume = (volume - 5).clamp(0, 100);
        _flash(vol());
      case 'player.mute':
      case 'mini.mute':
        if (repeat) return true;
        muted = !muted;
        _flash(vol());
      case 'player.stop':
      case 'mini.stop':
        playing = false;
        position = 0;
        _flash('Stopped');
      case 'player.previous':
      case 'mini.previous':
        item = (item - 1).clamp(0, _items.length - 1);
        position = 0;
        _flash(_items[item]);
      case 'player.next':
      case 'mini.next':
      case 'player.jumpEnd':
        item = (item + 1).clamp(0, _items.length - 1);
        position = 0;
        _flash(_items[item]);
      case 'player.subEarlier':
      case 'mini.subEarlier':
        subDelayMs -= 100;
        _flash(delay());
      case 'player.subLater':
      case 'mini.subLater':
        subDelayMs += 100;
        _flash(delay());
      case 'player.subEarlierCoarse':
      case 'mini.subEarlierCoarse':
        subDelayMs -= 1000;
        _flash(delay());
      case 'player.subLaterCoarse':
      case 'mini.subLaterCoarse':
        subDelayMs += 1000;
        _flash(delay());
      case 'player.subReset':
        subDelayMs = 0;
        _flash(delay());
      case 'player.shuffle':
        shuffle = !shuffle;
        _flash(shuffle ? 'Shuffle on' : 'Shuffle off');
      case 'player.repeat':
        repeatMode = (repeatMode + 1) % 3;
        _flash(const <String>['Repeat off', 'Repeat all', 'Repeat one'][repeatMode]);
      case 'player.speedDown':
        speed = (speed - 0.1).clamp(0.1, 4.0);
        _flash(spd());
      case 'player.speedUp':
        speed = (speed + 0.1).clamp(0.1, 4.0);
        _flash(spd());
      case 'player.speedReset':
        speed = 1.0;
        _flash(spd());
      case 'player.frameForward':
        playing = false;
        position = (position + 0.002).clamp(0.0, 1.0);
        _flash('Frame +1');
      case 'player.frameBack':
        playing = false;
        position = (position - 0.002).clamp(0.0, 1.0);
        _flash('Frame −1');
      case 'player.jumpPercent':
        {
          final int d = _digitOf(key);
          position = d / 10;
          _flash('${d * 10} %');
        }
      case 'player.jumpStart':
        position = 0;
        _flash('0:00');
      case 'player.fullscreen':
        if (repeat) return true;
        fullscreen = !fullscreen;
      case 'player.cycleAudio':
        audioTrack = (audioTrack + 1) % 2;
        _flash(audioTrack == 0 ? 'Audio 1 · English' : 'Audio 2 · Français');
      case 'player.cycleSubtitle':
        subtitleTrack = (subtitleTrack + 1) % 3;
        _flash(const <String>[
          'Subtitles off',
          'Subtitle 1 · English',
          'Subtitle 2 · Español',
        ][subtitleTrack]);
      case 'player.playlist':
        if (repeat) return true;
        playlistOpen = !playlistOpen;
      case 'player.findInPlaylist':
        playlistOpen = true;
      case 'player.openUrl':
        urlModalOpen = true;
      case 'player.mini':
        mode = ShortcutScope.mini;
        osd = null;
      case 'mini.exit':
        mode = ShortcutScope.player;
        osd = null;
      case 'player.webMode':
        if (repeat) return true;
        mode = ShortcutScope.web;
        osd = null;
      case 'web.playerMode':
        if (repeat) return true;
        mode = ShortcutScope.player;
        osd = null;
      case 'player.escape':
        if (urlModalOpen) {
          urlModalOpen = false;
        } else if (playlistOpen) {
          playlistOpen = false;
        } else if (fullscreen) {
          fullscreen = false;
        } else {
          return false;
        }

      // ── Web ───────────────────────────────────────────────────────
      case 'web.newTab':
      case 'web.reopenTab':
        if (webTabs < 8) webTabs++;
        webActive = webTabs - 1;
        if (entry.id == 'web.newTab') addressFocused = true;
      case 'web.closeTab':
        if (webTabs > 1) webTabs--;
        webActive = webActive.clamp(0, webTabs - 1);
      case 'web.nextTab':
        webActive = (webActive + 1) % webTabs;
      case 'web.previousTab':
        webActive = (webActive - 1 + webTabs) % webTabs;
      case 'web.jumpTab':
        {
          final int d = _digitOf(key);
          if (d >= 1 && d <= webTabs) webActive = d - 1;
        }
      case 'web.lastTab':
        webActive = webTabs - 1;
      case 'web.address':
        addressFocused = true;
      case 'web.reload':
      case 'web.hardReload':
      case 'web.back':
      case 'web.forward':
      case 'web.home':
      case 'web.settings':
        _flash(entry.action);
      case 'web.history':
        webPanel = webPanel == 'history' ? null : 'history';
      case 'web.downloads':
        webPanel = webPanel == 'downloads' ? null : 'downloads';
      case 'web.favourite':
        webPanel = webPanel == 'favourite' ? null : 'favourite';
      case 'web.hub':
        webPanel = webPanel == 'hub' ? null : 'hub';
      case 'web.clearData':
        webPanel = 'clear';
      case 'web.find':
        findBarOpen = true;
      case 'web.findNext':
        if (findBarOpen) findMatch = findMatch % 4 + 1;
      case 'web.findPrevious':
        if (findBarOpen) findMatch = (findMatch + 2) % 4 + 1;
      case 'web.zoomIn':
        zoom = (zoom + 10).clamp(30, 300);
        _flash('Zoom $zoom %');
      case 'web.zoomOut':
        zoom = (zoom - 10).clamp(30, 300);
        _flash('Zoom $zoom %');
      case 'web.zoomReset':
        zoom = 100;
        _flash('Zoom $zoom %');
      case 'web.fullscreen':
        if (repeat) return true;
        fullscreen = !fullscreen;
      case 'web.escape':
        if (webPanel != null) {
          webPanel = null;
        } else if (findBarOpen) {
          findBarOpen = false;
        } else if (addressFocused) {
          addressFocused = false;
        } else if (fullscreen) {
          fullscreen = false;
        } else {
          return false;
        }

      // ── Dialogs ─────────────────────────────────────────────────────
      case 'dialog.url.close':
        return false;

      default:
        // Doors that open real app surfaces (Ctrl+O, Ctrl+I, F2 …) flash
        // their name on the mock deck — the mirror never opens them.
        _flash(entry.action);
    }
    return true;
  }

  static int _digitOf(LogicalKeyboardKey key) {
    const List<LogicalKeyboardKey> row = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const List<LogicalKeyboardKey> pad = <LogicalKeyboardKey>[
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final int a = row.indexOf(key);
    if (a >= 0) return a;
    final int b = pad.indexOf(key);
    return b >= 0 ? b : 0;
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focus.requestFocus,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: _ModePill(mode: mode, onChoose: _setMode),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox.fromSize(
                    size: ShortcutsTab.miniatureSize,
                    child: _buildMiniature(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 84,
                child: _DetailStrip(
                  mode: mode,
                  entry: selected ?? _defaultEntry(),
                  combo: selected == null ? null : _selectedCombo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ShortcutEntry _defaultEntry() => SaluShortcuts.forScope(mode).first;

  Widget _buildMiniature() {
    final Widget body = switch (mode) {
      ShortcutScope.player => _buildPlayer(),
      ShortcutScope.mini => _buildMini(),
      ShortcutScope.web => _buildWeb(),
      ShortcutScope.dialog => _buildDialogs(),
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.videoBackdrop,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }

  // ── Chips ────────────────────────────────────────────────────────────

  bool _isLit(ShortcutEntry e) => selected?.id == e.id;

  /// A control of the miniature wearing its chip. Hover names it on the
  /// detail strip; the chip and the mark light while it is the one shown.
  Widget _control(ShortcutAnchor anchor, Widget mark, {bool chipAbove = false}) {
    final List<ShortcutEntry> riding = SaluShortcuts.forAnchor(mode, anchor);
    final String? legend = SaluShortcuts.chipLegend(mode, anchor);
    final bool lit = riding.any(_isLit);
    final Widget icon = IconTheme(
      data: IconThemeData(
        color: lit ? AppColors.textPrimary : AppColors.iconIdle,
        size: 16,
      ),
      child: SizedBox(width: 24, height: 24, child: Center(child: mark)),
    );
    if (legend == null || riding.isEmpty) return icon;
    final Widget chip = Transform.scale(
      scale: 0.82,
      child: PeekChip(legend, bright: lit),
    );
    return MouseRegion(
      onEnter: (_) => _select(riding.first),
      child: GestureDetector(
        onTap: () => _select(riding.first),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            icon,
            Positioned(
              left: -50,
              right: -50,
              top: chipAbove ? -20 : 24,
              height: 20,
              child: Center(child: chip),
            ),
          ],
        ),
      ),
    );
  }

  /// A cluster chip for a key with no control to ride.
  Widget _keyChip(ShortcutEntry e) {
    final String legend =
        e.legend ?? e.combos.map((ShortcutCombo c) => c.label).join(' · ');
    return MouseRegion(
      onEnter: (_) => _select(e),
      child: GestureDetector(
        onTap: () => _select(e),
        child: Transform.scale(
          scale: 0.86,
          child: PeekChip(legend, bright: _isLit(e)),
        ),
      ),
    );
  }

  Widget _cluster(List<ShortcutEntry> entries, {double width = 280}) {
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: <Widget>[for (final ShortcutEntry e in entries) _keyChip(e)],
      ),
    );
  }

  Widget _osdCard() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: osd == null ? 0 : 1,
        duration: const Duration(milliseconds: 140),
        child: GlassCapsule(
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            osd ?? '',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Player miniature ─────────────────────────────────────────────────

  Widget _buildPlayer() {
    const double titleH = 22;
    const double timelineH = 16;
    const double rowH = 28;
    const double chromeH = titleH + timelineH + rowH + 8;

    final List<ShortcutEntry> rideless =
        SaluShortcuts.rideless(ShortcutScope.player);
    final List<ShortcutEntry> quiet = <ShortcutEntry>[
      for (final ShortcutEntry e in rideless)
        if (e.group == ShortcutGroup.transport ||
            e.group == ShortcutGroup.speed ||
            e.group == ShortcutGroup.subtitles)
          if (e.id != 'player.mini') e,
    ];
    final List<ShortcutEntry> doors = <ShortcutEntry>[
      for (final ShortcutEntry e in rideless)
        if (!quiet.contains(e)) e,
    ];

    return Stack(
      children: <Widget>[
        // The video surface.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  const Color(0xFF1B2330),
                  playing ? const Color(0xFF12161D) : const Color(0xFF15171B),
                ],
              ),
            ),
          ),
        ),
        // Quiet cluster · keys with no control to ride.
        Positioned(
          left: 10,
          bottom: 10,
          child: _cluster(quiet, width: 300),
        ),
        // The doors · surfaces opened by keys alone.
        Positioned(
          right: 10,
          bottom: 10,
          child: _cluster(doors, width: 260),
        ),
        // The top chrome — hidden by F / F11.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          top: fullscreen ? -chromeH - 30 : 0,
          height: chromeH,
          child: Container(
            color: const Color(0xE0121212),
            child: Column(
              children: <Widget>[
                _titleBar(titleH),
                SizedBox(height: timelineH, child: _timeline()),
                const SizedBox(height: 4),
                SizedBox(height: rowH, child: _controlRow()),
              ],
            ),
          ),
        ),
        // Fullscreen · the bottom hairline cluster (§4.2 · chrome hidden).
        if (fullscreen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: position,
              child: Container(color: AppColors.threadFill),
            ),
          ),
        if (fullscreen)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: IgnorePointer(
              child: Center(
                child: PeekChip(SaluShortcuts.hiddenChromeCluster),
              ),
            ),
          ),
        // The OSD deck — below the chrome.
        Positioned(
          left: 0,
          right: 0,
          top: fullscreen ? 14 : chromeH + 30,
          child: Center(child: _osdCard()),
        ),
        // The playlist panel (Ctrl+L).
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          top: fullscreen ? 0 : chromeH,
          bottom: 0,
          right: playlistOpen ? 0 : -180,
          width: 170,
          child: _playlistPanel(),
        ),
        // The Open URL modal (Ctrl+U).
        if (urlModalOpen) ...<Widget>[
          Positioned.fill(child: Container(color: const Color(0x99000000))),
          Center(child: _urlModal()),
        ],
      ],
    );
  }

  Widget _titleBar(double h) {
    // The title bar stays silent — no shortcuts live there (§4.2).
    return SizedBox(
      height: h,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: IconTheme(
          data: const IconThemeData(color: AppColors.iconIdle),
          child: Row(
            children: <Widget>[
              const Text(
                'SALU',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _items[item],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const MinimizeMark(size: 10),
              const SizedBox(width: 10),
              const MaximizeMark(size: 10),
              const SizedBox(width: 10),
              const CloseMark(size: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeline() {
    final List<ShortcutEntry> riding =
        SaluShortcuts.forAnchor(mode, ShortcutAnchor.timeline);
    final bool lit = riding.any(_isLit);
    final String legend =
        SaluShortcuts.chipLegend(mode, ShortcutAnchor.timeline) ?? '';
    return MouseRegion(
      onEnter: (_) => _select(riding.first),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Transform.scale(
              scale: 0.8,
              child: PeekChip(legend, bright: lit),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(height: 3, color: AppColors.barTrack),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 3,
                        width: c.maxWidth * position,
                        color: lit ? AppColors.textPrimary : AppColors.barFill,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          _control(ShortcutAnchor.openMedia, const PlusMark(size: 14)),
          const SizedBox(width: 4),
          _control(ShortcutAnchor.playlist, const NowRowMark(size: 14)),
          const Spacer(),
          _control(
            ShortcutAnchor.playPause,
            playing ? const PauseMark(size: 13) : const PlayChevronMark(size: 14),
          ),
          const SizedBox(width: 6),
          _control(ShortcutAnchor.stop, const StopMark(size: 12)),
          const SizedBox(width: 12),
          _control(ShortcutAnchor.previous, const PreviousMark(size: 14)),
          const SizedBox(width: 6),
          _control(ShortcutAnchor.next, const NextMark(size: 14)),
          const SizedBox(width: 12),
          _control(ShortcutAnchor.seekBack, const SeekBackMark(size: 14)),
          const SizedBox(width: 6),
          _control(ShortcutAnchor.seekForward, const SeekForwardMark(size: 14)),
          const SizedBox(width: 18),
          _control(
            ShortcutAnchor.sound,
            SpeakerMark(size: 14, level: volume.toDouble(), muted: muted),
          ),
          const SizedBox(width: 4),
          _volumeBar(),
          const Spacer(),
          _control(ShortcutAnchor.tune, const EqualizerMark(size: 14)),
          const SizedBox(width: 4),
          _control(ShortcutAnchor.fetch, const CcMark(size: 13)),
          const SizedBox(width: 4),
          _control(
            ShortcutAnchor.fullscreen,
            Icon(
              fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeBar() {
    return SizedBox(
      width: 60,
      height: 3,
      child: Stack(
        children: <Widget>[
          Container(color: AppColors.barTrack),
          FractionallySizedBox(
            widthFactor: muted ? 0 : volume / 100,
            child: Container(color: AppColors.barFill),
          ),
        ],
      ),
    );
  }

  Widget _playlistPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF01E1E1E),
        border: Border(left: BorderSide(color: AppColors.surfaceOutline)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: selected?.id == 'player.findInPlaylist'
                    ? AppColors.accent
                    : AppColors.surfaceOutline,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _items[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: i == item ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _urlModal() {
    return GlassCapsule(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(color: AppColors.textPrimary),
                  child: LinkMark(size: 14),
                ),
                SizedBox(width: 8),
                Text(
                  'Open URL',
                  style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mini miniature ───────────────────────────────────────────────────

  Widget _buildMini() {
    final List<ShortcutEntry> quiet =
        SaluShortcuts.rideless(ShortcutScope.mini);
    final String title = osd ?? _items[item];
    return Stack(
      children: <Widget>[
        // The desktop behind the strip.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF161A20), Color(0xFF0F1114)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 40,
          right: 40,
          top: 90,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF01E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                _control(
                  ShortcutAnchor.playPause,
                  playing ? const PauseMark(size: 13) : const PlayChevronMark(size: 14),
                ),
                const SizedBox(width: 6),
                _control(ShortcutAnchor.stop, const StopMark(size: 12)),
                const SizedBox(width: 10),
                _control(ShortcutAnchor.previous, const PreviousMark(size: 14)),
                _control(ShortcutAnchor.next, const NextMark(size: 14)),
                const SizedBox(width: 10),
                _control(ShortcutAnchor.seekBack, const SeekBackMark(size: 14)),
                _control(ShortcutAnchor.seekForward, const SeekForwardMark(size: 14)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: osd == null ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                  ),
                ),
                _control(
                  ShortcutAnchor.sound,
                  SpeakerMark(size: 14, level: volume.toDouble(), muted: muted),
                ),
                const SizedBox(width: 10),
                _control(ShortcutAnchor.miniRestore, const MaximizeMark(size: 12)),
              ],
            ),
          ),
        ),
        // The strip's progress hairline.
        Positioned(
          left: 50,
          right: 50,
          top: 128,
          height: 2,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: position,
            child: Container(color: AppColors.threadFill),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: _cluster(quiet, width: 400),
        ),
      ],
    );
  }

  // ── Web miniature ────────────────────────────────────────────────────

  Widget _buildWeb() {
    final List<ShortcutEntry> quiet =
        SaluShortcuts.rideless(ShortcutScope.web);
    const double stripH = 28;
    const double rowH = 30;
    return Stack(
      children: <Widget>[
        // The page.
        Positioned.fill(
          top: fullscreen ? 0 : stripH + rowH,
          child: Container(
            color: const Color(0xFF17191C),
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
            child: Transform.scale(
              scale: zoom / 100,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _pageBar(180, 10, AppColors.textSecondary),
                  const SizedBox(height: 10),
                  _pageBar(320, 6, AppColors.barTrack),
                  const SizedBox(height: 6),
                  _pageBar(280, 6, AppColors.barTrack),
                  const SizedBox(height: 6),
                  _pageBar(300, 6, AppColors.barTrack),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: _cluster(quiet, width: 580),
        ),
        if (!fullscreen) ...<Widget>[
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: stripH,
            child: _webStrip(),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: stripH,
            height: rowH,
            child: _webRow(),
          ),
        ],
        // Find bar (Ctrl+F).
        if (findBarOpen)
          Positioned(
            right: 14,
            top: (fullscreen ? 0 : stripH + rowH) + 8,
            child: GlassCapsule(
              radius: 8,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                'find  ·  $findMatch / 4',
                style: const TextStyle(fontSize: 10.5, color: AppColors.textPrimary),
              ),
            ),
          ),
        // Panels & shelves.
        if (webPanel != null)
          Positioned(
            right: 14,
            top: (fullscreen ? 0 : stripH + rowH) + (findBarOpen ? 40 : 8),
            width: 170,
            height: 110,
            child: GlassCapsule(
              radius: 10,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _panelTitle(webPanel!),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _pageBar(120, 5, AppColors.barTrack),
                  const SizedBox(height: 6),
                  _pageBar(100, 5, AppColors.barTrack),
                  const SizedBox(height: 6),
                  _pageBar(130, 5, AppColors.barTrack),
                ],
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: fullscreen ? 14 : stripH + rowH + 40,
          child: Center(child: _osdCard()),
        ),
      ],
    );
  }

  static String _panelTitle(String panel) => switch (panel) {
        'history' => 'History',
        'downloads' => 'Downloads',
        'favourite' => 'Favourite',
        'hub' => 'Favourites',
        _ => 'Clear browsing data',
      };

  Widget _pageBar(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h / 2),
        ),
      );

  Widget _webStrip() {
    // Up to eight tabs share the strip; they narrow rather than overflow.
    final double tabW = ((440 / webTabs) - 4).clamp(30.0, 64.0);
    return Container(
      color: const Color(0xF0121212),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          _control(ShortcutAnchor.webHub, const HeartMark(size: 13)),
          const SizedBox(width: 6),
          for (int i = 0; i < webTabs; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: tabW,
                height: 20,
                padding: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: i == webActive ? AppColors.surfaceHighlight : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: i == webActive ? AppColors.accent : AppColors.surfaceOutline,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Tab ${i + 1}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          color: i == webActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (i == webActive)
                      Transform.scale(
                        scale: 0.75,
                        child: _control(
                          ShortcutAnchor.webCloseTab,
                          const CloseMark(size: 9),
                          chipAbove: false,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (webTabs < 8)
            _control(ShortcutAnchor.webNewTab, const PlusMark(size: 12)),
        ],
      ),
    );
  }

  Widget _webRow() {
    final List<ShortcutEntry> address =
        SaluShortcuts.forAnchor(mode, ShortcutAnchor.webAddress);
    final bool addressLit = address.any(_isLit) || addressFocused;
    return Container(
      color: const Color(0xF0121212),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          _control(ShortcutAnchor.webHome, const HomeMark(size: 13)),
          _control(ShortcutAnchor.webBack, const ArrowMark(size: 12)),
          _control(ShortcutAnchor.webForward, const ArrowMark(size: 12, flipped: true)),
          _control(ShortcutAnchor.webReload, const ReloadMark(size: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: MouseRegion(
              onEnter: (_) => _select(address.first),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: addressLit ? AppColors.accent : AppColors.surfaceOutline,
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 2),
                    child: Row(
                      children: <Widget>[
                        _control(ShortcutAnchor.webFavourite, const StarMark(size: 11)),
                        const Text(
                          'example.com',
                          style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 22,
                    height: 20,
                    child: Center(
                      child: Transform.scale(
                        scale: 0.82,
                        child: PeekChip(
                          SaluShortcuts.chipLegend(mode, ShortcutAnchor.webAddress) ?? '',
                          bright: addressLit,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _control(ShortcutAnchor.webDownloads, const DownloadMark(size: 13)),
          _control(ShortcutAnchor.webHistory, const ClockMark(size: 12)),
          const IconTheme(
            data: IconThemeData(color: AppColors.iconIdle),
            child: SizedBox(width: 24, child: Center(child: MenuMark(size: 13))),
          ),
        ],
      ),
    );
  }

  // ── Dialogs miniature ────────────────────────────────────────────────

  Widget _buildDialogs() {
    Widget card(ShortcutGroup group, Widget mock) {
      final List<ShortcutEntry> entries = <ShortcutEntry>[
        for (final ShortcutEntry e in SaluShortcuts.forScope(ShortcutScope.dialog))
          if (e.group == group) e,
      ];
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: entries.any(_isLit) ? const Color(0x604C9EEB) : AppColors.surfaceOutline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              group.label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            mock,
            const Spacer(),
            Wrap(
              children: <Widget>[for (final ShortcutEntry e in entries) _keyChip(e)],
            ),
          ],
        ),
      );
    }

    Widget field({bool focused = false}) => Container(
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: focused ? AppColors.accent : AppColors.surfaceOutline,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: card(ShortcutGroup.urlModal, field(focused: true))),
                const SizedBox(width: 10),
                Expanded(child: card(ShortcutGroup.addressDropdown, field())),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: card(ShortcutGroup.findBar, field())),
                const SizedBox(width: 10),
                Expanded(child: card(ShortcutGroup.playlistSearch, field())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mode pill — `Player · Mini · Web · Dialogs` on the pill recipe
/// (glass capsule, the selected word bright).
class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.onChoose});

  final ShortcutScope mode;
  final ValueChanged<ShortcutScope> onChoose;

  @override
  Widget build(BuildContext context) {
    return GlassCapsule(
      radius: 15,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final ShortcutScope s in ShortcutScope.values)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChoose(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s == mode ? const Color(0x264C9EEB) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  height: 24,
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: s == mode ? FontWeight.w600 : FontWeight.w400,
                      color: s == mode ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The detail strip — left: keycap + group + action (+ guard); right: the
/// same key in the other three modes (the §3 conflict matrix).
class _DetailStrip extends StatelessWidget {
  const _DetailStrip({required this.mode, required this.entry, this.combo});

  final ShortcutScope mode;
  final ShortcutEntry entry;
  final ShortcutCombo? combo;

  @override
  Widget build(BuildContext context) {
    final ShortcutCombo key = combo ?? entry.combos.first;
    final Map<ShortcutScope, ShortcutEntry?> across =
        SaluShortcuts.across(key, except: mode);
    final List<ShortcutCombo> caps = entry.legend != null
        ? const <ShortcutCombo>[]
        : entry.combos.take(3).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: 20,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (entry.legend != null)
                          PeekChip(entry.legend!, bright: true),
                        for (final ShortcutCombo c in caps) ...<Widget>[
                          PeekChip(c.label, bright: c == key),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.guard == null
                      ? entry.group.label
                      : '${entry.group.label} · ${entry.guard!.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, color: AppColors.divider),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final MapEntry<ShortcutScope, ShortcutEntry?> m in across.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 54,
                          child: Text(
                            m.key.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            m.value?.action ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: m.value == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
