import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/channel_view_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/transport_actions.dart';
import '../../core/window_state_service.dart';
import '../../theme/app_theme.dart';
import '../osc/transport_cluster.dart' show PlayPauseButton;
import '../osd/osd_controller.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/transport_marks.dart';
import 'mini_feedback.dart';
import 'mini_marks.dart';
import 'mini_metrics.dart';
import 'mini_progress.dart';
import 'volume_wheel.dart';

/// The mini bar — SALU's whole window as one 32 px strip
/// (mini.md — FINAL v5).
///
/// ```
///          ← 2 px progress line along the TOP edge, full width →
/// ┌──────────────────────────────────────────────────────────┐
/// │ [S] │ > ‖ □ │ |<< >>| │ << >> │ ⊂)) (◔) │ Track title… │ ⤢ │
/// └──────────────────────────────────────────────────────────┘
/// ```
///
/// The FULL window's sequence and its exact marks live on here — the very
/// same `transport_marks.dart` painters via the very same [SaluIconButton]
/// hover recipe, only the pitch is compressed: hits 26 × 30, gaps 5 / 11 /
/// 20, glyphs 18 px unchanged (§3, §11 v5). The volume wheel stands where
/// the full window's volume bar stands (§11 v4), and the title keeps its
/// full ~141 px.
///
/// The bar is ALWAYS ALIVE (§7): nothing here fades, sleeps, collapses or
/// repositions during a mini session. Its one feedback channel is the title
/// area, which swaps to the transient message for ~1.2 s and fades back
/// (§6) — the OSD deck does not exist in mini.
///
/// What the shell does NOT build matters as much as what it does: no video
/// surface, no lyrics, no album art, no subtitles, no playlist/fetch/tune/
/// settings panels, no caption buttons, no resize, no maximize (§8). mpv
/// keeps running underneath — a video file simply plays as audio.
///
/// And no tooltips (§3): the bar is 32 px tall, and a hover popup simply
/// cannot fit inside a window that tall — it would render cut off. Every
/// control therefore drops its tooltip in the bar (transport buttons,
/// seek line, volume wheel, title); full mode keeps its hover tooltips.
class MiniShell extends StatefulWidget {
  const MiniShell({super.key, this.dropHovering = false});

  /// Whether files are hovering over the bar — the drop highlight. The
  /// drop itself follows full mode's rules exactly (§5).
  final bool dropHovering;

  @override
  State<MiniShell> createState() => _MiniShellState();
}

class _MiniShellState extends State<MiniShell> {
  final PlayerService _player = PlayerService.instance;
  final QueueService _queue = QueueService.instance;
  final TransportActions _transport = TransportActions.instance;
  final WindowStateService _windows = WindowStateService.instance;

  /// The bar's surface: `rgba(30,30,31,.97)` — the preview's own value,
  /// one notch off [AppColors.background] exactly as the mock has it.
  static const Color _surface = Color(0xF71E1E1F);

  /// The transient line currently swapped into the title area (§6).
  String? _swapText;
  Timer? _swapTimer;

  /// The pointer rests anywhere on the bar. The preview raises the
  /// progress head on `.bar:hover` — the whole strip, not just the meter's
  /// own hit zone — so the line answers the cursor wherever it is.
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // §6 — the bar's replacement for the deck: every card a transport
    // action would have flashed is mirrored into the title swap instead.
    _transport.onCard = _onCard;
    // Stop is the one transport action with no card of its own in full mode
    // ("the canvas change IS the feedback") — and mini has no canvas, so the
    // bar says it instead. Listening to the state rather than the button
    // means the bare `S` key, which goes straight to the facade, speaks the
    // same words as the mark.
    _player.transportState.addListener(_onTransportState);
  }

  @override
  void dispose() {
    _transport.onCard = null;
    _player.transportState.removeListener(_onTransportState);
    _swapTimer?.cancel();
    super.dispose();
  }

  /// The one transition that has no card to carry it (§6).
  void _onTransportState() {
    if (_player.transportState.value == TransportState.stopped) {
      _swap('Stopped — queue parked');
    }
  }

  // ── Feedback (§6) ─────────────────────────────────────────────────────

  void _onCard(OsdCard card) {
    _swap(miniSwapText(
      card,
      volume: _player.volumeLevel.value,
      muted: _player.isMuted.value,
    ));
  }

  /// Shows [message] in the title area for [MiniMetrics.swapHold], then
  /// fades back to the real title. A repeat restarts the hold — the deck's
  /// own TTL rule, at caption size.
  void _swap(String? message) {
    if (message == null || message.isEmpty || !mounted) return;
    setState(() => _swapText = message);
    _swapTimer?.cancel();
    _swapTimer = Timer(MiniMetrics.swapHold, () {
      if (mounted) setState(() => _swapText = null);
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// One wheel notch over the sound group — ±5 % and nothing else (§3).
  ///
  /// The mapping is the full window's volume bar's own, notch for notch
  /// (`VolumeBar._onWheel`): `dy > 0` steps UP by 5, `dy < 0` steps down.
  /// Living in one place means the wheel cannot mean two different things
  /// in the two modes; `stepVolume` unmutes the moment the level leaves
  /// silence, exactly as that bar does.
  void _stepVolume(double dy) {
    if (dy == 0 || !mounted) return;
    _player.stepVolume(dy > 0 ? 5 : -5);
    _swap(volumeSwapText(_player.volumeLevel.value, _player.isMuted.value));
  }

  /// Leave mini — the Restore button, a double-click on dead space and Esc
  /// all land here (§4). The saved full geometry comes back exactly.
  void _exit() {
    unawaited(_windows.exitMini());
  }

  // ── Title ─────────────────────────────────────────────────────────────

  /// The playing item — the CHANNEL's display name in channel mode, never a
  /// URL (§10.10e) — falling back to `SALU` while idle, as full mode does.
  /// (Full mode's title tooltip — complete text plus the channel's group —
  /// does not exist here: the bar has no room for a popup, §3.)
  String get _title => _player.currentTitle.value ?? 'SALU';

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _player.transportState,
        _player.isPlaying,
        _player.currentTitle,
        _player.volumeLevel,
        _player.isMuted,
        // Next's enable state also answers the repeat × shuffle mode, and
        // channel mode's Prev/Next follow the open group — the same merge
        // the full cluster watches, so the dim rules can never drift.
        _player.shuffleOn,
        _player.repeatMode,
        _queue.items,
        _queue.index,
        ChannelViewService.instance.groupMode,
        ChannelViewService.instance.openGroup,
        ChannelViewService.instance.searching,
      ]),
      builder: (BuildContext context, Widget? _) {
        final TransportState state = _player.transportState.value;
        final bool engineLive = state == TransportState.playing ||
            state == TransportState.paused;
        // Channel mode's timeline is inert, so the seeks dim there exactly
        // as they do with nothing to seek into — full mode's own rule.
        final bool seeksLive = engineLive && !_queue.isChannelList;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 1 · The bar's surface — the one place its color lives. The
              //     rounded corners let the desktop through.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius:
                      BorderRadius.circular(MiniMetrics.cornerRadius),
                  border: Border.all(
                    color: widget.dropHovering
                        ? AppColors.accent
                        : AppColors.surfaceOutline,
                  ),
                ),
              ),

              // 2 · The row — SALU's sequence, compressed.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MiniMetrics.outerPadding,
                  ),
                  child: Row(
                    children: _row(state: state, seeksLive: seeksLive),
                  ),
                ),
              ),

              // 3 · The top-edge meter, drawn last so it owns the bar's top
              //     band: mini.md §3 gives the seek line the full width and
              //     an ~11 px hit zone hanging from the top edge, exactly as
              //     the preview stacks it (`.seekhit` above the control row).
              //     The 2 px line itself stays clear of the marks — every
              //     control keeps its 26 × 30 box, just not the bar's top
              //     band.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: MiniMetrics.seekHitHeight,
                child: MiniSeekLine(onSwap: _swap, barHovered: _hovered),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _row({
    required TransportState state,
    required bool seeksLive,
  }) {
    final bool engineLive = state == TransportState.playing ||
        state == TransportState.paused;

    return <Widget>[
      // ── The SALU glyph — identity, and the bar's drag handle (§3) ────
      _DragArea(
        onDoubleTap: _exit,
        child: const SizedBox(
          width: MiniMetrics.saluBox,
          height: MiniMetrics.hitHeight,
          child: Center(child: _SaluTile()),
        ),
      ),
      _DragGap(MiniMetrics.iconGap, onDoubleTap: _exit),

      // ── Group 1 · playback: play/pause + stop ────────────────────────
      // No tooltips in the bar (§3) — a popup cannot fit a 32 px window.
      PlayPauseButton(
        state: state,
        hitSize: MiniMetrics.hit,
        markSize: MiniMetrics.markSize,
        tooltipEnabled: false,
      ),
      const SizedBox(width: MiniMetrics.inGroupGap),
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        // Stop dims while stopped and while idle; it is never a
        // "start over" — full mode's rule, unchanged.
        enabled: engineLive,
        onTap: _transport.stop,
        child: const StopMark(size: MiniMetrics.markSize),
      ),

      _DragGap(MiniMetrics.betweenGroupsGap, onDoubleTap: _exit),

      // ── Group 2 · items: previous + next ─────────────────────────────
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        enabled: _player.hasPreviousItem,
        onTap: _transport.previous,
        child: const PreviousMark(size: MiniMetrics.markSize),
      ),
      const SizedBox(width: MiniMetrics.inGroupGap),
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        enabled: _player.hasNextItem,
        onTap: _transport.next,
        child: const NextMark(size: MiniMetrics.markSize),
      ),

      _DragGap(MiniMetrics.betweenGroupsGap, onDoubleTap: _exit),

      // ── Group 3 · time: seek backward + forward ──────────────────────
      //     Hold-to-climb is the full window's own press-and-hold ramp.
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        enabled: seeksLive,
        onTap: () {}, // hold-repeat drives the ramp
        onHoldRepeat: _transport.seekBackward,
        child: const SeekBackMark(size: MiniMetrics.markSize),
      ),
      const SizedBox(width: MiniMetrics.inGroupGap),
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        enabled: seeksLive,
        onTap: () {}, // hold-repeat drives the ramp
        onHoldRepeat: _transport.seekForward,
        child: const SeekForwardMark(size: MiniMetrics.markSize),
      ),

      _DragGap(MiniMetrics.beforeSoundGap, onDoubleTap: _exit),

      // ── Group 4 · sound: speaker + the volume wheel, 5 px apart ──────
      //     One Listener over the pair: rolling over the speaker OR the
      //     ring is the same ±5 % gesture (§3).
      Listener(
        onPointerSignal: (PointerSignalEvent event) {
          if (event is PointerScrollEvent) _stepVolume(event.scrollDelta.dy);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SaluIconButton(
              hitSize: MiniMetrics.hit,
              onTap: _transport.toggleMute,
              // The speaker follows the volume exactly like full mode:
              // 1 arc below 50 %, 2 arcs at 50 %+, a slash when silent.
              child: SpeakerMark(
                size: MiniMetrics.markSize,
                level: _player.volumeLevel.value,
                muted: _player.isMuted.value,
              ),
            ),
            const SizedBox(width: MiniMetrics.inGroupGap),
            const VolumeWheel(),
          ],
        ),
      ),

      // ── The title — everything left over, ellipsized (§3 item 3) ─────
      // No tooltip: the complete text used to ride the hover popup, but
      // the bar has no room for one (§3).
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(
            left: MiniMetrics.titleLeftMargin,
            right: MiniMetrics.titleRightMargin,
          ),
          child: _DragArea(
            onDoubleTap: _exit,
            child: SizedBox(
              height: MiniMetrics.hitHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTitle(),
              ),
            ),
          ),
        ),
      ),

      // ── Restore — the bar's only "caption" control (§3 item 4) ───────
      SaluIconButton(
        hitSize: MiniMetrics.hit,
        onTap: _exit,
        child: const MiniRestoreMark(size: MiniMetrics.markSize),
      ),
      const SizedBox(width: MiniMetrics.restoreTrailingGap),
    ];
  }

  /// The title area's two lines of one story: the transient swap, or the
  /// real title. Same size, same family — only the ink moves (the swap sits
  /// at [AppColors.textPrimary], the resting title one step quieter).
  Widget _buildTitle() {
    final String? swap = _swapText;
    final bool swapped = swap != null;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: swapped ? AppColors.textPrimary : AppColors.textSecondary,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (BuildContext context, Color? color, Widget? _) {
        return Text(
          swap ?? _title,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.2,
            color: color ?? AppColors.textSecondary,
          ),
        );
      },
    );
  }
}

/// Dead space — the icon, the group gaps and the title area drag the whole
/// bar (§3 "Dragging"). Controls never drag: they are simply not wrapped.
///
/// The drag itself is the native Windows move loop (`startDragging`), so the
/// bar follows the cursor exactly like a caption would; the move-end hook in
/// [WindowStateService] is what remembers (and clamps) where it landed.
/// A double-click on any of it restores the full window (§4).
class _DragArea extends StatelessWidget {
  const _DragArea({required this.child, required this.onDoubleTap});

  final Widget child;

  /// Dead space is also the bar's second way out of mini (§4).
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(windowManager.startDragging()),
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

/// A draggable gap between two groups — the bar's dead space, with the
/// row's own height so it is really there for the pointer.
class _DragGap extends StatelessWidget {
  const _DragGap(this.width, {required this.onDoubleTap});

  final double width;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return _DragArea(
      onDoubleTap: onDoubleTap,
      child: SizedBox(width: width, height: MiniMetrics.hitHeight),
    );
  }
}

/// The SALU glyph in the row's first slot: the app's own tile at 19 px,
/// softly rounded. mpv keeps playing underneath it — that is the whole
/// point of the bar.
class _SaluTile extends StatelessWidget {
  const _SaluTile();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.asset(
        'assets/images/salu_logo.png',
        width: MiniMetrics.saluGlyph,
        height: MiniMetrics.saluGlyph,
        filterQuality: FilterQuality.medium,
        // A caption-size decode of the app icon: sharp at any DPI, and
        // nowhere near the cost of the full-size PNG.
        cacheWidth: 64,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          // Never a broken-image glyph — a thin frame in the family's ink.
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            child: const SizedBox(
              width: MiniMetrics.saluGlyph,
              height: MiniMetrics.saluGlyph,
            ),
          );
        },
      ),
    );
  }
}
