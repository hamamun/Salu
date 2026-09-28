import 'package:flutter/services.dart';

/// SALU's Shortcut Registry (shortcut.md §4.0) — ONE list of every keyboard
/// shortcut in shortcut.md §2. The Settings → Shortcuts tab (§4.1, the
/// Living Map) and Alt-Peek (§4.2) both *render* from it; neither keeps its
/// own copy.
///
/// The registry is the **display truth**: the key handlers
/// (`HomeScreen._onKeyEvent`, `BrowserScreen`'s handler, the mini handler)
/// keep working as they are, and any change to a handler must update this
/// list in the same commit. A shortcut without an entry here is a bug.
///
/// No custom key mapping — ever. SALU's shortcuts are standards (mpv / VLC
/// / MPC-HC / Edge); this list is a mirror, never an editor.

/// The surface a shortcut belongs to (§1.1 — one key, one meaning per
/// mode).
enum ShortcutScope {
  player('Player'),
  mini('Mini'),
  web('Web'),
  dialog('Dialogs');

  const ShortcutScope(this.label);

  /// The mode pill's word.
  final String label;
}

/// The §2 groups — used as the detail strip's group line.
enum ShortcutGroup {
  transport('Playback & transport'),
  speed('Speed & frame'),
  seeking('Seeking & position'),
  window('Fullscreen & window'),
  subtitles('Subtitles & tracks'),
  surfaces('Opening & surfaces'),
  tune('Tune keyboard tier'),
  mini('Mini mode'),
  webTabs('Tab management'),
  webNavigation('Navigation & address bar'),
  webPanels('Panels & shelves'),
  webFind('Page search'),
  webZoom('Zoom & window'),
  urlModal('Open URL modal'),
  addressDropdown('Address bar dropdown'),
  findBar('Find-in-page bar'),
  playlistSearch('Playlist search field'),
  playlist('Playlist');

  const ShortcutGroup(this.label);

  final String label;
}

/// When a shortcut only answers in a certain state (§4.0 · availability
/// guard). Shown on the detail strip; never enforced from here.
enum ShortcutGuard {
  seekable('While the media is seekable'),
  subtitleSelected('While a subtitle is selected'),
  tunePanelOpen('While the Tune panel is open'),
  pageFullscreen('While a page owns the screen'),
  findBarOpen('While the find bar is open'),
  groupByPillOpen('While the playlist Group by choices are open');

  const ShortcutGuard(this.label);

  final String label;
}

/// The visible controls Alt-Peek (and the Living Map) pin chips to.
enum ShortcutAnchor {
  // Player chrome (§4.2 table).
  openMedia,
  playlist,
  playlistGroupBy,
  playlistSearch,
  playlistFavourites,
  playlistClear,
  playPause,
  stop,
  previous,
  next,
  seekBack,
  seekForward,
  sound,
  timeline,
  tune,
  fetch,
  fullscreen,

  // Web row (§4.2 · Anchors — Web mode).
  webNewTab,
  webCloseTab,
  webAddress,
  webHistory,
  webDownloads,
  webFavourite,
  webHub,
  webBack,
  webForward,
  webReload,
  webHome,

  // Mini strip (Living Map only — Alt-Peek skips mini in v1).
  miniRestore,
}

/// One key combination: a logical key plus the Ctrl / Shift / Alt flags.
class ShortcutCombo {
  const ShortcutCombo(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// Exact match — the modifiers must agree both ways, so `Shift+S`
  /// never reads as `S`.
  bool matches(
    LogicalKeyboardKey pressed, {
    required bool ctrl,
    required bool shift,
    required bool alt,
    bool meta = false,
  }) =>
      pressed == key &&
      ctrl == this.ctrl &&
      shift == this.shift &&
      alt == this.alt &&
      meta == this.meta;

  /// The keycap legend, e.g. `Ctrl+Shift+F`.
  String get label {
    final StringBuffer b = StringBuffer();
    if (ctrl) b.write('Ctrl+');
    if (shift) b.write('Shift+');
    if (alt) b.write('Alt+');
    if (meta) b.write('Cmd+');
    b.write(keyName(key));
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutCombo &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt, meta);

  @override
  String toString() => label;
}

/// The short legend SALU prints for a logical key.
String keyName(LogicalKeyboardKey key) {
  final String? special = _keyNames[key];
  if (special != null) return special;
  final String label = key.keyLabel;
  if (label.isEmpty) return key.debugName ?? '?';
  return label.length == 1 ? label.toUpperCase() : label;
}

final Map<LogicalKeyboardKey, String> _keyNames = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.pageUp: 'PgUp',
  LogicalKeyboardKey.pageDown: 'PgDn',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'Num Enter',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.backslash: r'\',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.minus: '-',
  LogicalKeyboardKey.numpadAdd: 'Num +',
  LogicalKeyboardKey.numpadSubtract: 'Num -',
  LogicalKeyboardKey.numpad0: 'Num 0',
  LogicalKeyboardKey.f2: 'F2',
  LogicalKeyboardKey.f3: 'F3',
  LogicalKeyboardKey.f5: 'F5',
  LogicalKeyboardKey.f6: 'F6',
  LogicalKeyboardKey.f11: 'F11',
};

/// One registered shortcut.
class ShortcutEntry {
  const ShortcutEntry({
    required this.scope,
    required this.combos,
    required this.id,
    required this.action,
    required this.group,
    this.guard,
    this.anchor,
    this.legend,
  });

  final ShortcutScope scope;

  /// Every combination that fires the action (`F2` / `Ctrl+,` …). The first
  /// is the primary one.
  final List<ShortcutCombo> combos;

  /// Stable action id (`player.playPause`) — the liveness engine and tests
  /// key off it.
  final String id;

  /// The action's name as the detail strip shows it.
  final String action;

  final ShortcutGroup group;
  final ShortcutGuard? guard;

  /// The visible control this key rides, when it has one.
  final ShortcutAnchor? anchor;

  /// A compact legend for ranges (`0–9`, `Ctrl+1–8`); otherwise the combos
  /// joined with ` / `.
  final String? legend;

  String get keys => legend ?? combos.map((ShortcutCombo c) => c.label).join(' / ');

  bool matches(
    LogicalKeyboardKey key, {
    required bool ctrl,
    required bool shift,
    required bool alt,
    bool meta = false,
  }) {
    for (final ShortcutCombo c in combos) {
      if (c.matches(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta)) return true;
    }
    return false;
  }

  @override
  String toString() => '${scope.name}:$id [$keys]';
}

typedef _K = LogicalKeyboardKey;

const List<ShortcutCombo> _digits = <ShortcutCombo>[
  ShortcutCombo(_K.digit0),
  ShortcutCombo(_K.digit1),
  ShortcutCombo(_K.digit2),
  ShortcutCombo(_K.digit3),
  ShortcutCombo(_K.digit4),
  ShortcutCombo(_K.digit5),
  ShortcutCombo(_K.digit6),
  ShortcutCombo(_K.digit7),
  ShortcutCombo(_K.digit8),
  ShortcutCombo(_K.digit9),
  ShortcutCombo(_K.numpad0),
  ShortcutCombo(_K.numpad1),
  ShortcutCombo(_K.numpad2),
  ShortcutCombo(_K.numpad3),
  ShortcutCombo(_K.numpad4),
  ShortcutCombo(_K.numpad5),
  ShortcutCombo(_K.numpad6),
  ShortcutCombo(_K.numpad7),
  ShortcutCombo(_K.numpad8),
  ShortcutCombo(_K.numpad9),
];

const List<ShortcutCombo> _ctrlDigits1to8 = <ShortcutCombo>[
  ShortcutCombo(_K.digit1, ctrl: true),
  ShortcutCombo(_K.digit2, ctrl: true),
  ShortcutCombo(_K.digit3, ctrl: true),
  ShortcutCombo(_K.digit4, ctrl: true),
  ShortcutCombo(_K.digit5, ctrl: true),
  ShortcutCombo(_K.digit6, ctrl: true),
  ShortcutCombo(_K.digit7, ctrl: true),
  ShortcutCombo(_K.digit8, ctrl: true),
  ShortcutCombo(_K.numpad1, ctrl: true),
  ShortcutCombo(_K.numpad2, ctrl: true),
  ShortcutCombo(_K.numpad3, ctrl: true),
  ShortcutCombo(_K.numpad4, ctrl: true),
  ShortcutCombo(_K.numpad5, ctrl: true),
  ShortcutCombo(_K.numpad6, ctrl: true),
  ShortcutCombo(_K.numpad7, ctrl: true),
  ShortcutCombo(_K.numpad8, ctrl: true),
];

/// The registry itself.
class SaluShortcuts {
  SaluShortcuts._();

  static const List<ShortcutEntry> entries = <ShortcutEntry>[
    // ── Group A · Player mode ────────────────────────────────────────
    // A1 · Playback & transport
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.space)],
      id: 'player.playPause',
      action: 'Play / Pause',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.playPause,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowLeft)],
      id: 'player.seekBack',
      action: 'Seek backward 5 s (hold ramps)',
      group: ShortcutGroup.transport,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.seekBack,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowRight)],
      id: 'player.seekForward',
      action: 'Seek forward 5 s (hold ramps)',
      group: ShortcutGroup.transport,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.seekForward,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowUp)],
      id: 'player.volumeUp',
      action: 'Volume up 5 %',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowDown)],
      id: 'player.volumeDown',
      action: 'Volume down 5 %',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyM)],
      id: 'player.mute',
      action: 'Mute / Unmute',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyM, ctrl: true)],
      id: 'player.mini',
      action: 'Mini mode',
      group: ShortcutGroup.transport,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyS)],
      id: 'player.stop',
      action: 'Stop',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.stop,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyS, shift: true),
        ShortcutCombo(_K.keyS, alt: true),
      ],
      id: 'player.shuffle',
      action: 'Toggle shuffle',
      group: ShortcutGroup.transport,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyR)],
      id: 'player.repeat',
      action: 'Cycle repeat (Off → All → One)',
      group: ShortcutGroup.transport,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.pageUp)],
      id: 'player.previous',
      action: 'Previous item',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.previous,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.pageDown)],
      id: 'player.next',
      action: 'Next item',
      group: ShortcutGroup.transport,
      anchor: ShortcutAnchor.next,
    ),

    // A2 · Speed & frame
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.bracketLeft)],
      id: 'player.speedDown',
      action: 'Speed −0.1×',
      group: ShortcutGroup.speed,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.bracketRight)],
      id: 'player.speedUp',
      action: 'Speed +0.1×',
      group: ShortcutGroup.speed,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.backslash),
        ShortcutCombo(_K.backspace),
      ],
      id: 'player.speedReset',
      action: 'Reset speed (1.0×)',
      group: ShortcutGroup.speed,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.period)],
      id: 'player.frameForward',
      action: 'Frame step forward',
      group: ShortcutGroup.speed,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.comma)],
      id: 'player.frameBack',
      action: 'Frame step backward',
      group: ShortcutGroup.speed,
    ),

    // A3 · Seeking & position
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: _digits,
      id: 'player.jumpPercent',
      action: 'Jump to 0 % – 90 %',
      group: ShortcutGroup.seeking,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.timeline,
      legend: '0–9',
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.home)],
      id: 'player.jumpStart',
      action: 'Jump to beginning',
      group: ShortcutGroup.seeking,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.timeline,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.end)],
      id: 'player.jumpEnd',
      action: 'Jump to end / next item',
      group: ShortcutGroup.seeking,
      anchor: ShortcutAnchor.timeline,
    ),

    // A4 · Fullscreen & window
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyF), ShortcutCombo(_K.f11)],
      id: 'player.fullscreen',
      action: 'Toggle fullscreen',
      group: ShortcutGroup.window,
      anchor: ShortcutAnchor.fullscreen,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'player.escape',
      action: 'Close popup, then exit fullscreen',
      group: ShortcutGroup.window,
    ),

    // A5 · Subtitles & tracks
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyZ)],
      id: 'player.subEarlier',
      action: 'Subtitle sync −100 ms',
      group: ShortcutGroup.subtitles,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyX)],
      id: 'player.subLater',
      action: 'Subtitle sync +100 ms',
      group: ShortcutGroup.subtitles,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyZ, shift: true)],
      id: 'player.subEarlierCoarse',
      action: 'Subtitle sync −1 s',
      group: ShortcutGroup.subtitles,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyX, shift: true)],
      id: 'player.subLaterCoarse',
      action: 'Subtitle sync +1 s',
      group: ShortcutGroup.subtitles,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.backspace, shift: true),
        ShortcutCombo(_K.keyZ, ctrl: true, shift: true),
      ],
      id: 'player.subReset',
      action: 'Reset subtitle sync',
      group: ShortcutGroup.subtitles,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyC), ShortcutCombo(_K.keyT)],
      id: 'player.tracks',
      action: 'Tracks panel (video) / Lyrics (audio)',
      group: ShortcutGroup.subtitles,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyB)],
      id: 'player.cycleAudio',
      action: 'Cycle audio track',
      group: ShortcutGroup.subtitles,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyV)],
      id: 'player.cycleSubtitle',
      action: 'Cycle subtitle track',
      group: ShortcutGroup.subtitles,
    ),

    // A6 · Opening, searching & surfaces
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyO, ctrl: true)],
      id: 'player.openFiles',
      action: 'Open file(s)',
      group: ShortcutGroup.surfaces,
      anchor: ShortcutAnchor.openMedia,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyO, ctrl: true, shift: true)],
      id: 'player.openFolder',
      action: 'Open folder',
      group: ShortcutGroup.surfaces,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyU, ctrl: true)],
      id: 'player.openUrl',
      action: 'Open URL modal',
      group: ShortcutGroup.surfaces,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyL, ctrl: true)],
      id: 'player.playlist',
      action: 'Toggle playlist',
      group: ShortcutGroup.surfaces,
      anchor: ShortcutAnchor.playlist,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyF, ctrl: true)],
      id: 'player.findInPlaylist',
      action: 'Find in playlist',
      group: ShortcutGroup.surfaces,
      anchor: ShortcutAnchor.playlistSearch,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyF, ctrl: true, shift: true)],
      id: 'player.searchSubtitles',
      action: 'Search subtitles online',
      group: ShortcutGroup.surfaces,
      anchor: ShortcutAnchor.fetch,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyI, ctrl: true)],
      id: 'player.info',
      action: 'Toggle info panel',
      group: ShortcutGroup.surfaces,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyE, ctrl: true),
        ShortcutCombo(_K.keyE, meta: true),
      ],
      id: 'player.tune',
      action: 'Toggle Tune panel',
      group: ShortcutGroup.surfaces,
      anchor: ShortcutAnchor.tune,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyG, ctrl: true)],
      id: 'player.groupBy',
      action: 'Open playlist Group by',
      group: ShortcutGroup.playlist,
      anchor: ShortcutAnchor.playlistGroupBy,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyD, ctrl: true)],
      id: 'player.playlistFavourites',
      action: 'Toggle playlist favourites filter',
      group: ShortcutGroup.playlist,
      anchor: ShortcutAnchor.playlistFavourites,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.delete, ctrl: true, shift: true),
      ],
      id: 'player.clearPlaylist',
      action: 'Clear playlist',
      group: ShortcutGroup.playlist,
      anchor: ShortcutAnchor.playlistClear,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyR, ctrl: true, shift: true)],
      id: 'player.remote',
      action: 'Remote QR pairing',
      group: ShortcutGroup.surfaces,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.f2),
        ShortcutCombo(_K.comma, ctrl: true),
      ],
      id: 'player.settings',
      action: 'Open Settings',
      group: ShortcutGroup.surfaces,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyW, alt: true),
        ShortcutCombo(_K.keyW, ctrl: true, shift: true),
      ],
      id: 'player.webMode',
      action: 'Switch to Web mode',
      group: ShortcutGroup.surfaces,
    ),

    // A7 · Tune keyboard tier
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.arrowUp, ctrl: true),
        ShortcutCombo(_K.arrowDown, ctrl: true),
        ShortcutCombo(_K.arrowUp, meta: true),
        ShortcutCombo(_K.arrowDown, meta: true),
      ],
      id: 'player.tuneNudge',
      action: 'Nudge the focused Tune parameter',
      group: ShortcutGroup.tune,
      guard: ShortcutGuard.tunePanelOpen,
    ),
    ShortcutEntry(
      scope: ShortcutScope.player,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.arrowUp, ctrl: true, alt: true),
        ShortcutCombo(_K.arrowDown, ctrl: true, alt: true),
        ShortcutCombo(_K.arrowUp, meta: true, alt: true),
        ShortcutCombo(_K.arrowDown, meta: true, alt: true),
      ],
      id: 'player.tuneFocus',
      action: 'Move focus across the Tune sections',
      group: ShortcutGroup.tune,
      guard: ShortcutGuard.tunePanelOpen,
    ),

    // ── Group B · Mini mode ───────────────────────────────────────────
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.escape),
        ShortcutCombo(_K.keyM, ctrl: true),
      ],
      id: 'mini.exit',
      action: 'Exit mini mode',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.miniRestore,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyM)],
      id: 'mini.mute',
      action: 'Mute / Unmute',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.space)],
      id: 'mini.playPause',
      action: 'Play / Pause',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.playPause,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowLeft)],
      id: 'mini.seekBack',
      action: 'Seek backward',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.seekBack,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowRight)],
      id: 'mini.seekForward',
      action: 'Seek forward',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.seekable,
      anchor: ShortcutAnchor.seekForward,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowUp)],
      id: 'mini.volumeUp',
      action: 'Volume up 5 %',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowDown)],
      id: 'mini.volumeDown',
      action: 'Volume down 5 %',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.sound,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyS)],
      id: 'mini.stop',
      action: 'Stop',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.stop,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.pageUp)],
      id: 'mini.previous',
      action: 'Previous item',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.previous,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.pageDown)],
      id: 'mini.next',
      action: 'Next item',
      group: ShortcutGroup.mini,
      anchor: ShortcutAnchor.next,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyZ)],
      id: 'mini.subEarlier',
      action: 'Subtitle sync −100 ms',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyX)],
      id: 'mini.subLater',
      action: 'Subtitle sync +100 ms',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyZ, shift: true)],
      id: 'mini.subEarlierCoarse',
      action: 'Subtitle sync −1 s',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.subtitleSelected,
    ),
    ShortcutEntry(
      scope: ShortcutScope.mini,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyX, shift: true)],
      id: 'mini.subLaterCoarse',
      action: 'Subtitle sync +1 s',
      group: ShortcutGroup.mini,
      guard: ShortcutGuard.subtitleSelected,
    ),

    // ── Group C · Web mode ────────────────────────────────────────────
    // C1 · Tabs
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyT, ctrl: true)],
      id: 'web.newTab',
      action: 'New tab',
      group: ShortcutGroup.webTabs,
      anchor: ShortcutAnchor.webNewTab,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyW, ctrl: true)],
      id: 'web.closeTab',
      action: 'Close tab',
      group: ShortcutGroup.webTabs,
      anchor: ShortcutAnchor.webCloseTab,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.tab, ctrl: true),
        ShortcutCombo(_K.pageDown, ctrl: true),
      ],
      id: 'web.nextTab',
      action: 'Next tab',
      group: ShortcutGroup.webTabs,
      legend: 'Ctrl+Tab',
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.tab, ctrl: true, shift: true),
        ShortcutCombo(_K.pageUp, ctrl: true),
      ],
      id: 'web.previousTab',
      action: 'Previous tab',
      group: ShortcutGroup.webTabs,
      legend: 'Ctrl+Shift+Tab',
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: _ctrlDigits1to8,
      id: 'web.jumpTab',
      action: 'Jump to tab 1–8',
      group: ShortcutGroup.webTabs,
      legend: 'Ctrl+1–8',
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit9, ctrl: true),
        ShortcutCombo(_K.numpad9, ctrl: true),
      ],
      id: 'web.lastTab',
      action: 'Jump to last tab',
      group: ShortcutGroup.webTabs,
      legend: 'Ctrl+9',
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyT, ctrl: true, shift: true)],
      id: 'web.reopenTab',
      action: 'Reopen closed tab',
      group: ShortcutGroup.webTabs,
    ),

    // C2 · Navigation & address bar
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyL, ctrl: true),
        ShortcutCombo(_K.keyD, alt: true),
        ShortcutCombo(_K.f6),
      ],
      id: 'web.address',
      action: 'Focus address bar',
      group: ShortcutGroup.webNavigation,
      anchor: ShortcutAnchor.webAddress,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyR, ctrl: true),
        ShortcutCombo(_K.f5),
      ],
      id: 'web.reload',
      action: 'Reload page',
      group: ShortcutGroup.webNavigation,
      anchor: ShortcutAnchor.webReload,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.f5, ctrl: true),
        ShortcutCombo(_K.keyR, ctrl: true, shift: true),
      ],
      id: 'web.hardReload',
      action: 'Hard reload',
      group: ShortcutGroup.webNavigation,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowLeft, alt: true)],
      id: 'web.back',
      action: 'Back',
      group: ShortcutGroup.webNavigation,
      anchor: ShortcutAnchor.webBack,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.arrowRight, alt: true)],
      id: 'web.forward',
      action: 'Forward',
      group: ShortcutGroup.webNavigation,
      anchor: ShortcutAnchor.webForward,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.home, alt: true)],
      id: 'web.home',
      action: 'Site home',
      group: ShortcutGroup.webNavigation,
      anchor: ShortcutAnchor.webHome,
    ),

    // C3 · Panels & shelves
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyH, ctrl: true)],
      id: 'web.history',
      action: 'History panel',
      group: ShortcutGroup.webPanels,
      anchor: ShortcutAnchor.webHistory,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyJ, ctrl: true)],
      id: 'web.downloads',
      action: 'Downloads shelf',
      group: ShortcutGroup.webPanels,
      anchor: ShortcutAnchor.webDownloads,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyD, ctrl: true)],
      id: 'web.favourite',
      action: 'Add / edit favourite',
      group: ShortcutGroup.webPanels,
      anchor: ShortcutAnchor.webFavourite,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyO, ctrl: true, shift: true)],
      id: 'web.hub',
      action: 'Favourites hub',
      group: ShortcutGroup.webPanels,
      anchor: ShortcutAnchor.webHub,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.delete, ctrl: true, shift: true),
        ShortcutCombo(_K.backspace, ctrl: true, shift: true),
      ],
      id: 'web.clearData',
      action: 'Clear browsing data',
      group: ShortcutGroup.webPanels,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.f2),
        ShortcutCombo(_K.comma, ctrl: true),
      ],
      id: 'web.settings',
      action: 'Settings (Web tab)',
      group: ShortcutGroup.webPanels,
    ),

    // C4 · Find
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.keyF, ctrl: true)],
      id: 'web.find',
      action: 'Find in page',
      group: ShortcutGroup.webFind,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.f3)],
      id: 'web.findNext',
      action: 'Next match',
      group: ShortcutGroup.webFind,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.f3, shift: true)],
      id: 'web.findPrevious',
      action: 'Previous match',
      group: ShortcutGroup.webFind,
    ),

    // C5 · Zoom & window
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.equal, ctrl: true),
        ShortcutCombo(_K.numpadAdd, ctrl: true),
      ],
      id: 'web.zoomIn',
      action: 'Zoom in',
      group: ShortcutGroup.webZoom,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.minus, ctrl: true),
        ShortcutCombo(_K.numpadSubtract, ctrl: true),
      ],
      id: 'web.zoomOut',
      action: 'Zoom out',
      group: ShortcutGroup.webZoom,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit0, ctrl: true),
        ShortcutCombo(_K.numpad0, ctrl: true),
      ],
      id: 'web.zoomReset',
      action: 'Reset zoom',
      group: ShortcutGroup.webZoom,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.f11)],
      id: 'web.fullscreen',
      action: 'Browser fullscreen',
      group: ShortcutGroup.webZoom,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'web.escape',
      action: 'Release page fullscreen / exit fullscreen',
      group: ShortcutGroup.webZoom,
    ),
    ShortcutEntry(
      scope: ShortcutScope.web,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.keyW, alt: true),
        ShortcutCombo(_K.keyW, ctrl: true, shift: true),
      ],
      id: 'web.playerMode',
      action: 'Switch to Player mode',
      group: ShortcutGroup.webZoom,
    ),

    // ── Group D · Dialogs & focused components ────────────────────────
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.enter)],
      id: 'dialog.url.play',
      action: 'Play URL',
      group: ShortcutGroup.urlModal,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.enter, ctrl: true)],
      id: 'dialog.url.playSave',
      action: 'Play & save URL',
      group: ShortcutGroup.urlModal,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.arrowUp),
        ShortcutCombo(_K.arrowDown),
      ],
      id: 'dialog.url.walk',
      action: 'Walk saved URLs',
      group: ShortcutGroup.urlModal,
      legend: '↑ ↓',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'dialog.url.close',
      action: 'Close the modal',
      group: ShortcutGroup.urlModal,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.arrowDown),
        ShortcutCombo(_K.arrowUp),
      ],
      id: 'dialog.address.walk',
      action: 'Walk suggestions',
      group: ShortcutGroup.addressDropdown,
      legend: '↓ ↑',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.enter),
        ShortcutCombo(_K.numpadEnter),
      ],
      id: 'dialog.address.submit',
      action: 'Go / pick suggestion',
      group: ShortcutGroup.addressDropdown,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'dialog.address.hide',
      action: 'Hide suggestions',
      group: ShortcutGroup.addressDropdown,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.enter),
        ShortcutCombo(_K.numpadEnter),
      ],
      id: 'dialog.find.next',
      action: 'Next match',
      group: ShortcutGroup.findBar,
      guard: ShortcutGuard.findBarOpen,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.enter, shift: true)],
      id: 'dialog.find.previous',
      action: 'Previous match',
      group: ShortcutGroup.findBar,
      guard: ShortcutGuard.findBarOpen,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'dialog.find.close',
      action: 'Close the find bar',
      group: ShortcutGroup.findBar,
      guard: ShortcutGuard.findBarOpen,
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit1),
        ShortcutCombo(_K.numpad1),
      ],
      id: 'dialog.groupFlat',
      action: 'Choose Flat grouping',
      group: ShortcutGroup.playlist,
      guard: ShortcutGuard.groupByPillOpen,
      legend: '1',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit2),
        ShortcutCombo(_K.numpad2),
      ],
      id: 'dialog.groupCategory',
      action: 'Choose Category grouping',
      group: ShortcutGroup.playlist,
      guard: ShortcutGuard.groupByPillOpen,
      legend: '2',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit3),
        ShortcutCombo(_K.numpad3),
      ],
      id: 'dialog.groupCountry',
      action: 'Choose Country grouping',
      group: ShortcutGroup.playlist,
      guard: ShortcutGuard.groupByPillOpen,
      legend: '3',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[
        ShortcutCombo(_K.digit4),
        ShortcutCombo(_K.numpad4),
      ],
      id: 'dialog.groupLanguage',
      action: 'Choose Language grouping',
      group: ShortcutGroup.playlist,
      guard: ShortcutGuard.groupByPillOpen,
      legend: '4',
    ),
    ShortcutEntry(
      scope: ShortcutScope.dialog,
      combos: <ShortcutCombo>[ShortcutCombo(_K.escape)],
      id: 'dialog.playlistSearch.escape',
      action: 'Clear query, then leave the field',
      group: ShortcutGroup.playlistSearch,
    ),
  ];

  /// Every entry of [scope], in registry order.
  static List<ShortcutEntry> forScope(ShortcutScope scope) => <ShortcutEntry>[
        for (final ShortcutEntry e in entries)
          if (e.scope == scope) e,
      ];

  /// The entry with [id], or null.
  static ShortcutEntry? byId(String id) {
    for (final ShortcutEntry e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The entries riding [anchor] in [scope].
  static List<ShortcutEntry> forAnchor(
    ShortcutScope scope,
    ShortcutAnchor anchor,
  ) =>
      <ShortcutEntry>[
        for (final ShortcutEntry e in entries)
          if (e.scope == scope && e.anchor == anchor) e,
      ];

  /// The keys with no visible control to ride — the Living Map's quiet
  /// cluster (§4.1 · layout, point 2).
  static List<ShortcutEntry> rideless(ShortcutScope scope) => <ShortcutEntry>[
        for (final ShortcutEntry e in entries)
          if (e.scope == scope && e.anchor == null) e,
      ];

  /// The first entry of [scope] a key press answers to, or null. Dialog
  /// scope has several components sharing keys; the first registered wins
  /// (the Open URL modal).
  static ShortcutEntry? match(
    ShortcutScope scope,
    LogicalKeyboardKey key, {
    required bool ctrl,
    required bool shift,
    required bool alt,
    bool meta = false,
  }) {
    for (final ShortcutEntry e in entries) {
      if (e.scope != scope) continue;
      if (e.matches(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta)) return e;
    }
    return null;
  }

  /// What [combo] does in every OTHER scope — the detail strip's right
  /// column (the §3 conflict matrix).
  static Map<ShortcutScope, ShortcutEntry?> across(
    ShortcutCombo combo, {
    required ShortcutScope except,
  }) =>
      <ShortcutScope, ShortcutEntry?>{
        for (final ShortcutScope s in ShortcutScope.values)
          if (s != except)
            s: match(s, combo.key,
                ctrl: combo.ctrl, shift: combo.shift, alt: combo.alt, meta: combo.meta),
      };

  /// The chip legend for [anchor] — the key only, never the action (§4.2 ·
  /// the chip recipe). Several entries on one anchor fold into one chip
  /// (`↑ ↓ · M`, `0–9 · Home · End`). Null when nothing rides it.
  static String? chipLegend(ShortcutScope scope, ShortcutAnchor anchor) {
    final String? fixed = _chipOverrides[anchor];
    final List<ShortcutEntry> riding = forAnchor(scope, anchor);
    if (riding.isEmpty) return null;
    if (fixed != null && scope != ShortcutScope.mini) return fixed;
    return riding.map(_compactKeys).join(' · ');
  }

  static String _compactKeys(ShortcutEntry e) =>
      e.legend ?? e.combos.map((ShortcutCombo c) => c.label).join(' · ');

  /// Hand-folded legends from shortcut.md §4.2's anchor table.
  static const Map<ShortcutAnchor, String> _chipOverrides =
      <ShortcutAnchor, String>{
    ShortcutAnchor.sound: '↑ ↓ · M',
    ShortcutAnchor.tune: 'Ctrl+E · Cmd+E',
    ShortcutAnchor.playlistGroupBy: 'Ctrl+G',
    ShortcutAnchor.playlistSearch: 'Ctrl+F',
    ShortcutAnchor.playlistFavourites: 'Ctrl+D',
    ShortcutAnchor.playlistClear: 'Ctrl+Shift+Delete',
    ShortcutAnchor.timeline: '0–9 · Home · End',
    ShortcutAnchor.fullscreen: 'F · F11',
    ShortcutAnchor.webAddress: 'Ctrl+L',
    ShortcutAnchor.webReload: 'Ctrl+R · F5',
  };
}
