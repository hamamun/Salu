import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/language_names.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import '../widgets/subtitle_search_dialog.dart';

/// The Fetch button's slide-down track panel (cc.md §6 · D14).
///
/// One surface, three parts, live-mirroring mpv's track-list:
///   · Part 1 — **Audio**: every audio track, marked at mpv's pick.
///   · Part 2 — **Subtitles** (embedded only): **Off pinned on top**.
///   · Part 3 — **Local** (external autoloaded + manually loaded).
/// Below: a hairline and the Load (file) + Search (online) marks.
///
/// The panel stays open across taps; the row marks do all the talking
/// (§6.6 — no OSD for track switches). It closes on Esc / click-outside
/// (nothing shifted underneath — rule 5) and, always, on media change
/// (§6.2 — a stale list would be worse than none).
class TrackPanel extends StatefulWidget {
  const TrackPanel({super.key});

  /// Panel width (the mock's 302 px).
  static const double width = 302;

  @override
  State<TrackPanel> createState() => _TrackPanelState();
}

class _TrackPanelState extends State<TrackPanel>
    with SingleTickerProviderStateMixin {
  final PanelService _panels = PanelService.instance;
  final PlayerService _player = PlayerService.instance;

  late final AnimationController _open;
  late final Animation<double> _curve;

  /// Chrome is locked awake for the panel's lifetime — rows must stay
  /// answerable even while the viewer reads, exactly like the playlist
  /// panel. Released on close/dispose (counted by [ChromeLock]).
  bool _locked = false;

  /// The media the panel was opened against; a change closes the
  /// surface (§6.2 lock).
  String? _openedFor;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _curve = CurvedAnimation(
      parent: _open,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _panels.trackPanelOpen.addListener(_onOpenChanged);
    _player.currentPath.addListener(_onMediaChanged);
  }

  @override
  void dispose() {
    _panels.trackPanelOpen.removeListener(_onOpenChanged);
    _player.currentPath.removeListener(_onMediaChanged);
    if (_locked) ChromeLock.instance.release();
    _open.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    final bool open = _panels.trackPanelOpen.value;
    if (open) {
      // Opening one popup closes the others (rule 3).
      _panels.closePlaylist();
      _openedFor = _player.currentPath.value;
      ChromeLock.instance.acquire();
      _locked = true;
      _open.forward();
    } else {
      if (_locked) {
        ChromeLock.instance.release();
        _locked = false;
      }
      _open.reverse();
    }
  }

  /// §6.2 — the panel closes on media change, every time (a stale track
  /// list is worse than any reopen).
  void _onMediaChanged() {
    if (!_panels.trackPanelOpen.value) return;
    if (_player.currentPath.value != _openedFor) {
      _panels.closeTrackPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _panels.trackPanelOpen,
      builder: (BuildContext context, bool open, Widget? _) {
        return IgnorePointer(
          ignoring: !open,
          child: AnimatedBuilder(
            animation: _curve,
            builder: (BuildContext context, Widget? _) {
              final double v = _curve.value.clamp(0.0, 1.0).toDouble();
              return Stack(
                children: <Widget>[
                  // Click-outside (rule 3) — the open pill's recipe:
                  // OPAQUE so the closing click never falls through to
                  // the video (no accidental play/pause zaps). Taps on
                  // the panel's own rows resolve in-transit and never
                  // reach this barrier.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _panels.closeTrackPanel,
                      onSecondaryTap: _panels.closeTrackPanel,
                    ),
                  ),
                  Positioned(
                    top: kChromeBlockHeight + 6,
                    right: 16,
                    width: TrackPanel.width,
                    child: Opacity(
                      opacity: v,
                      child: Transform(
                        // vector_math 2.4: the dynamic-typed
                        // translate()/scale() cascades are deprecated —
                        // the ByDouble forms are the replacements.
                        transform: Matrix4.identity()
                          ..translateByDouble(0.0, (1 - v) * -8, 0.0, 1.0)
                          ..scaleByDouble(
                            0.96 + 0.04 * v,
                            0.96 + 0.04 * v,
                            0.96 + 0.04 * v,
                            1.0,
                          ),
                        alignment: Alignment.topRight,
                        child: _glass(_body()),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Glass — the same recipe as the Open pill / OSD deck: blur 18,
  /// AppColors.glass, surfaceOutline hairline, radius 11 (the mock).
  Widget _glass(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.surfaceOutline),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 50,
                offset: Offset(0, 18),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: child,
        ),
      ),
    );
  }

  Widget _body() {
    return ValueListenableBuilder<TrackSurface>(
      valueListenable: _player.trackSurface,
      builder: (BuildContext context, TrackSurface surface, Widget? _) {
        final List<Widget> children = <Widget>[];

        // Part 1 — Audio (§6.3).
        if (surface.audio.isNotEmpty) {
          children.add(const _PartLabel('Audio'));
          children.add(_PartRows(
            rows: surface.audio
                .map((MpvTrack t) => _TrackRowData.fromAudio(t,
                    surface.audio.indexOf(t) + 1))
                .toList(),
            onTap: (MpvTrack t) =>
                unawaited(_player.selectAudioTrack(t)),
          ));
        }

        final bool hasEmbedded = surface.embeddedSubs.isNotEmpty;
        final bool hasLocal = surface.localSubs.isNotEmpty;
        final bool offMarked = surface.offIsMarked;

        // Part 2 — Embedded subtitles; Off pinned on top (§6.3).
        if (hasEmbedded) {
          children.add(const _PartLabel('Subtitles'));
          children.add(_PartRows(
            rows: <_TrackRowData>[
              _TrackRowData.offRow(selected: offMarked),
              ...surface.embeddedSubs.map((MpvTrack t) =>
                  _TrackRowData.fromSub(t,
                      surface.embeddedSubs.indexOf(t) + 1)),
            ],
            onTap: (MpvTrack t) => unawaited(_player.selectSubTrack(t)),
            onOffTap: () => unawaited(_player.selectSubOff()),
          ));
        }

        // Part 3 — Local subs; Off lives here if there are no embedded
        // tracks (§6.3's pinned-Off rule), or nowhere on a bare video.
        if (hasLocal) {
          children.add(const _PartLabel('Local'));
          children.add(_PartRows(
            rows: <_TrackRowData>[
              if (!hasEmbedded) _TrackRowData.offRow(selected: offMarked),
              ...surface.localSubs.map((MpvTrack t) =>
                  _TrackRowData.fromSub(t,
                      surface.localSubs.indexOf(t) + 1)),
            ],
            onTap: (MpvTrack t) => unawaited(_player.selectSubTrack(t)),
            onOffTap: () => unawaited(_player.selectSubOff()),
          ));
        }

        // Actions — always present (§6.4: the Load + Search marks are
        // the whole panel on a bare video).
        children
          ..add(const _Hairline())
          ..add(_Actions(openSearch: () => _openSearch(context)));

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    await showSubtitleSearchDialog(context);
  }
}

/// One row's data for any part. Keeps the widget tree identical for
/// audio / embedded / local / off rows — one shape, several sources.
class _TrackRowData {
  _TrackRowData({
    required this.label,
    required this.selected,
    this.sub,
    this.track,
    this.isOff = false,
  });

  factory _TrackRowData.offRow({required bool selected}) =>
      _TrackRowData(label: 'Off', selected: selected, isOff: true);

  /// Audio (§6.3): language name → title → Track n; the sub-line is the
  /// technical shape `5.1 · ac3` when mpv reports it, 'untagged' when it
  /// does not.
  factory _TrackRowData.fromAudio(MpvTrack t, int n) {
    final String? lang = LanguageNames.nameOf(t.lang);
    final String label =
        lang ?? (t.title?.isNotEmpty ?? false ? t.title! : 'Track $n');
    final String? channels = _channelsOf(t.channels);
    final String sub = channels != null && t.codec != null
        ? '$channels · ${t.codec}'
        : (t.codec ?? 'untagged');
    return _TrackRowData(
      label: label,
      sub: sub,
      selected: t.selected,
      track: t,
    );
  }

  /// Embedded / Local sub rows (§6.3): language name → title → Track n.
  /// Embedded say "embedded"; locals say the file's own name.
  factory _TrackRowData.fromSub(MpvTrack t, int n) {
    final String? lang = LanguageNames.nameOf(t.lang);
    final String label =
        lang ?? (t.title?.isNotEmpty ?? false ? t.title! : 'Track $n');
    String sub = t.external ? 'external' : 'embedded';
    if (t.external && t.externalFilename != null) {
      final String file =
          t.externalFilename!.split(RegExp(r'[/\\]')).last;
      if (file.isNotEmpty) sub = file;
    } else if (!t.external && t.codec != null) {
      sub = 'embedded';
    }
    return _TrackRowData(
      label: label,
      sub: sub,
      selected: t.selected,
      track: t,
    );
  }

  final String label;
  final String? sub;
  final bool selected;
  final MpvTrack? track;
  final bool isOff;

  /// mpv's `demux-channels` strings read `5.1(side)`, `2.0`, …; the
  /// row shows the compact layout only.
  static String? _channelsOf(String? raw) {
    if (raw == null) return null;
    final int paren = raw.indexOf('(');
    final String s = (paren >= 0 ? raw.substring(0, paren) : raw).trim();
    return s.isEmpty ? null : s;
  }
}

/// Part header — the mock's 10 px / w600 / +0.1em uppercase label.
class _PartLabel extends StatelessWidget {
  const _PartLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 3),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// One part's rows, scrolling on its own once past five (§6.3) — the
/// panel NEVER grows, only the inner list scrolls.
class _PartRows extends StatefulWidget {
  // No `key`: the parts are singletons of the panel's body — identity
  // is positional, never keyed.
  const _PartRows({
    required this.rows,
    required this.onTap,
    this.onOffTap,
  });

  final List<_TrackRowData> rows;
  final ValueChanged<MpvTrack> onTap;
  final VoidCallback? onOffTap;

  static const double rowHeight = 28;
  static const int maxVisible = 5;

  @override
  State<_PartRows> createState() => _PartRowsState();
}

class _PartRowsState extends State<_PartRows> {
  final ScrollController _scroll = ScrollController();

  /// Tap selections must NOT reset the scroll (the mock: re-mark rows
  /// without rebuilding). The controller survives surface refreshes;
  /// the clamp only matters when a brand-new shorter list arrives.
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      for (final _TrackRowData row in widget.rows)
        _TrackRow(
          data: row,
          onTap: row.isOff
              ? (widget.onOffTap ?? () {})
              : () => widget.onTap(row.track!),
        ),
    ];
    if (widget.rows.length <= _PartRows.maxVisible) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
    // Past 5 rows the part scrolls INSIDE (§6.3) — the panel NEVER
    // grows, only the inner list rows scroll.
    return SizedBox(
      height: _PartRows.maxVisible * _PartRows.rowHeight,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: false,
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
    );
  }
}

/// 28 px row: 12.5 px label · 10.5 px sub · tick on the right when
/// mpv's pick. Hover = surfaceHighlight wash + textPrimary label.
class _TrackRow extends StatefulWidget {
  const _TrackRow({required this.data, required this.onTap});

  final _TrackRowData data;
  final VoidCallback onTap;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final _TrackRowData d = widget.data;
    final Color labelColor = _hover || d.selected
        ? AppColors.textPrimary
        : AppColors.iconIdle;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _PartRows.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        d.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (d.sub != null && d.sub!.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          d.sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // The tick is mpv's truth, not SALU's target (§6.3/D17) —
              // appears only on the marked row.
              if (d.selected)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: IconTheme(
                    data: IconThemeData(color: AppColors.textPrimary),
                    child: TickMark(size: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: AppColors.divider,
    );
  }
}

/// The panel's action strip (§6.4–§6.5): Load (real file picker,
/// session-only) + Search (centered glass query-window) — icon marks
/// only, nothing textual (rule 6).
class _Actions extends StatelessWidget {
  const _Actions({required this.openSearch});

  final VoidCallback openSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Row(
        children: <Widget>[
          SaluIconButton(
            tooltip: 'Load subtitle',
            size: 30,
            onTap: () => unawaited(_pickFile()),
            child: const LoadSubMark(size: 19),
          ),
          const SizedBox(width: 20),
          SaluIconButton(
            tooltip: 'Search subtitles',
            size: 30,
            onTap: openSearch,
            child: const MagnifierMark(size: 18),
          ),
        ],
      ),
    );
  }

  /// §6.4 — the Load mark: a real file picker, any of mpv's subtitle
  /// extensions, session-only by default (it lands in the Local part
  /// marked; nothing is persisted).
  static Future<void> _pickFile() async {
    const List<String> exts = <String>['srt', 'ass', 'ssa', 'vtt', 'sub'];
    final fs.XFile? file = await fs.openFile(
      acceptedTypeGroups: <fs.XTypeGroup>[
        const fs.XTypeGroup(label: 'Subtitles', extensions: exts),
        const fs.XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null || file.path.isEmpty) return;
    if (!File(file.path).existsSync()) return;
    // D-SHAME-LOCK: subtitles load via the existing engine path — mpv
    // makes them the active track (§6.4 "session-only by default");
    // nothing remembers the pick.
    await PlayerService.instance.loadExternalSubtitle(file.path);
  }
}
