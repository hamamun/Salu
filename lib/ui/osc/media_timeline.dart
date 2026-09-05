import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent;
import 'package:flutter/material.dart';

import '../../core/clock_format.dart';
import '../../core/player_service.dart';
import '../../core/transport_actions.dart';
import '../../theme/app_theme.dart';
import 'hover_chip.dart';

/// Formats live in `lib/core/clock_format.dart` (formatClock here,
/// formatClockCompact in the Resume toast).

/// SALU's unified timeline — identical for video and audio.
///
/// A paste-window style thick bar: a gentle light fill grows from the left
/// over a darker track. The time readouts live INSIDE the bar:
///   · left   — playback position   (hh:mm:ss)
///   · middle — −remaining time     (−hh:mm:ss, hidden when narrow)
///   · right  — total media time    (hh:mm:ss)
/// all in one single quiet tone.
///
/// Interactions (playback is never paused or disturbed by any of them):
///   · click anywhere            → instant precise jump
///   · press + drag, release     → live scrub preview, jump on release
///   · mouse wheel over the bar  → ±1 second per notch (fine scrub)
///   · hover                     → faint minute-rule ticks + a time chip
///                                below the bar showing the target time
class MediaTimeline extends StatefulWidget {
  const MediaTimeline({super.key});

  /// Full widget height: the bar plus room for the chip underneath.
  static const double widgetHeight = 48;

  /// Visual height of the thick bar itself.
  static const double barHeight = 23;

  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  final PlayerService _player = PlayerService.instance;
  late final Listenable _merged;

  /// Pointer x as a fraction of the bar (0..1) — shows the hover chip.
  double? _hoverFrac;

  /// Press/drag scrub position (0..1) — preview only; committed on release.
  double? _pressFrac;

  /// X where the current press started (for the drag slop check).
  double? _downX;

  /// Whether the press has moved beyond slop (i.e. it is a drag, not a
  /// click). A click commits on release; a drag previews live and commits
  /// on release at the final position.
  bool _dragging = false;

  /// Movement (in logical px) that turns a press into a drag.
  static const double _dragSlop = 6;

  @override
  void initState() {
    super.initState();
    _merged = Listenable.merge(<Listenable>[
      _player.position,
      _player.duration,
      _player.transportState,
    ]);
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  Duration get _duration => _player.duration.value;

  /// The bar is live only while the engine actually holds an item —
  /// while STOPPED it is inert and reads zeros (the parked queue has no
  /// timeline), and while idle there is simply nothing to show.
  bool get _usable =>
      _duration > Duration.zero && _player.hasMedia.value;

  // ── Seek helpers ──────────────────────────────────────────────────────

  Duration _targetForFrac(double frac) {
    return Duration(
      milliseconds: (frac * _duration.inMilliseconds).round(),
    );
  }

  void _commitFrac(double frac) {
    if (!_usable) return;
    // A timeline click is another transport action — it resets both
    // seek ramps (the outline's ramp rule).
    TransportActions.instance.resetSeekRamps();
    _player.seekTo(_targetForFrac(frac));
  }

  // ── Pointer handling (raw listener — no gesture arena, so presses are
  //    tracked 1:1: preview appears the instant the button goes down, a
  //    stationary click commits on release, a drag previews live and
  //    commits where it is released) ────────────────────────────────────

  double _fracAt(double dx, double width) =>
      _clamp01(width <= 0 ? 0 : dx / width);

  void _onPointerDown(PointerDownEvent e, double w) {
    if (!_usable) return;
    _downX = e.localPosition.dx;
    _dragging = false;
    setState(() => _pressFrac = _fracAt(e.localPosition.dx, w));
  }

  void _onPointerMove(PointerMoveEvent e, double w) {
    if (_pressFrac == null) return; // Button was not pressed on this bar.
    final double dx = e.localPosition.dx;
    if (!_dragging) {
      final double? downX = _downX;
      if (downX == null || (dx - downX).abs() < _dragSlop) return;
      _dragging = true;
    }
    setState(() => _pressFrac = _fracAt(dx, w));
  }

  void _onPointerUp(PointerUpEvent e, double w) {
    final double? frac = _pressFrac;
    if (frac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Click (no drag) and drag both commit exactly where the pointer was
    // released — that is also the press position for a plain click.
    _commitFrac(frac);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_pressFrac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Cancel (rare on desktop) = abandon the scrub, no seek.
  }

  void _onWheel(double dy) {
    if (!_usable) return;
    // Wheel down (positive) scrubs forward, wheel up backward — 1 second
    // per notch. seekTo clamps at the media bounds. Like every seek
    // from outside the ramp, this resets the ramp sequences.
    TransportActions.instance.resetSeekRamps();
    _player.seekBy(dy > 0 ? const Duration(seconds: 1) : const Duration(seconds: -1));
  }

  // ── Aiming ruler (minute ticks) ───────────────────────────────────────

  /// Chooses a tick step (from a friendly ladder) so neighboring ticks sit
  /// roughly 60–120 px apart on the given bar width.
  Duration _tickStep(double width) {
    const List<int> ladderMs = <int>[
      500, 1000, 2000, 5000, 10000, 15000, 30000,
      60000, 120000, 300000, 600000, 900000, 1800000, 3600000,
      7200000, 14400000, 28800000,
    ];
    final int durMs = _duration.inMilliseconds;
    final double targetMs = durMs * 72 / (width <= 0 ? 1 : width);
    for (final int ms in ladderMs) {
      if (ms >= targetMs) return Duration(milliseconds: ms);
    }
    return Duration(milliseconds: ladderMs.last);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: (BuildContext context, Widget? _) {
        final bool usable = _usable;
        return SizedBox(
          height: MediaTimeline.widgetHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double w = constraints.maxWidth;
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent e) => _onPointerDown(e, w),
                onPointerMove: (PointerMoveEvent e) => _onPointerMove(e, w),
                onPointerUp: (PointerUpEvent e) => _onPointerUp(e, w),
                onPointerCancel: _onPointerCancel,
                onPointerSignal: (PointerSignalEvent event) {
                  if (event is PointerScrollEvent) _onWheel(event.scrollDelta.dy);
                },
                child: MouseRegion(
                  onHover: (PointerHoverEvent e) {
                    if (!usable) return;
                    setState(() => _hoverFrac = _fracAt(e.localPosition.dx, w));
                  },
                  onExit: (PointerExitEvent e) {
                    if (_hoverFrac != null) setState(() => _hoverFrac = null);
                  },
                  child: _buildBody(w, usable),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(double w, bool usable) {
    final Duration pos = _player.position.value;
    final Duration dur = usable ? _duration : Duration.zero;
    final int durMs = dur.inMilliseconds;

    // The boundary shown on the bar: the scrub preview while pressing or
    // dragging, the real playback position otherwise.
    final double boundaryFrac = _pressFrac ??
        (usable ? _clamp01(pos.inMilliseconds / durMs) : 0);
    final double boundaryX = boundaryFrac * w;

    // Time readouts.
    final Duration shown =
        _pressFrac != null && usable ? _targetForFrac(_pressFrac!) : pos;
    final Duration remaining =
        dur - shown > Duration.zero ? dur - shown : Duration.zero;
    final bool showTicks = usable && (_hoverFrac != null || _pressFrac != null);
    final Duration tickStep = usable ? _tickStep(w) : Duration.zero;

    // Tooltip chip — target time under the cursor / thumb.
    const double chipWidth = 96; // HoverChip's timeline width
    final double? chipFrac = _pressFrac ?? _hoverFrac;
    final bool showChip = usable && chipFrac != null;
    final double clampedChipFrac = chipFrac?.clamp(0.0, 1.0).toDouble() ?? 0;
    final double chipLeft = w <= chipWidth
        ? 0
        : (clampedChipFrac * w - chipWidth / 2)
            .clamp(0.0, w - chipWidth)
            .toDouble();

    const TextStyle labelStyle = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1,
      letterSpacing: 0.4,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      shadows: <Shadow>[
        Shadow(color: Color(0x99000000), blurRadius: 2),
      ],
    );

    return Stack(
      children: <Widget>[
        // ── The thick bar ─────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaTimeline.barHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: <Widget>[
                // Track.
                const Positioned.fill(
                  child: ColoredBox(color: AppColors.barTrack),
                ),
                // Paste-window style fill.
                if (boundaryX > 0)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: boundaryX,
                    child: const ColoredBox(color: AppColors.barFill),
                  ),
                // Aiming ruler (hover / scrub) — faint vertical ticks.
                if (showTicks && tickStep > Duration.zero)
                  for (Duration t = tickStep;
                      t < dur;
                      t += tickStep)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: w * (t.inMilliseconds / durMs),
                      child: const ColoredBox(
                        color: AppColors.barTick,
                        child: SizedBox(width: 1),
                      ),
                    ),
                // Flat playhead notch at the fill edge (no glow). Hidden
                // only at the exact extremes where it would clip off-bar.
                if (usable && boundaryX > 0.5 && boundaryX < w - 1.5)
                  Positioned(
                    top: 4,
                    bottom: 4,
                    left: boundaryX - 1,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: AppColors.barThumb,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                // Time readouts — inside the bar, all one tone.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: <Widget>[
                          Text(
                            usable ? formatClock(shown) : '00:00:00',
                            style: labelStyle,
                          ),
                          const Spacer(),
                          if (w > 560)
                            Text(
                              usable ? '-${formatClock(remaining)}' : '',
                              style: labelStyle,
                            ),
                          const Spacer(),
                          Text(
                            usable ? formatClock(dur) : '00:00:00',
                            style: labelStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Hover / scrub time chip (below the bar) ───────────────────
        // The timeline's chip and the volume bar's chip are ONE widget
        // (HoverChip) — chip = value under the cursor; the bar's in-bar
        // labels = current value.
        if (showChip)
          Positioned(
            top: MediaTimeline.barHeight + 2,
            left: chipLeft,
            child: HoverChip(
              label: formatClock(_targetForFrac(clampedChipFrac)),
            ),
          ),
      ],
    );
  }
}
