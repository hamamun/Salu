import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDownEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/material.dart';

import '../../core/clock_format.dart';
import '../../core/player_service.dart';
import '../../core/transport_actions.dart';
import '../../theme/app_theme.dart';
import 'mini_metrics.dart';

/// The mini bar's ONE edge meter (mini.md §3 "Edge meter").
///
/// Position alone rides the TOP edge: a 2 px strip along the bar's top edge,
/// full width, `#80FFFFFF` ([AppColors.barFill]) over the `#35353C`
/// ([AppColors.barTrack]) track — the same pair the full window's timeline
/// paints, at caption scale.
///
/// The strip itself is display only. The invisible ~11 px hit zone hanging
/// from the top edge is what seeks, with the timeline's own recipe (§3 item
/// 2 of the transport spec, and `media_timeline.dart`): a stationary click
/// commits on release, a drag previews live and commits where it is
/// released, and the head tick shows while hovering or scrubbing.
///
/// The zone spans the bar's full width and sits ABOVE the control row, which
/// is how the preview stacks it too (`.seekhit` over `.controls`): the 2 px
/// line can never be buried under a mark, and every control keeps its own
/// 26 × 30 box — just not the top band of the bar, which belongs to the
/// meter (§3 "Edge meter").
///
/// Channel mode has no position at all (§10.8a) and a parked queue has no
/// timeline: the strip stays drawn (every pixel of the bar is persistent,
/// §7) but empty and inert.
class MiniSeekLine extends StatefulWidget {
  const MiniSeekLine({
    super.key,
    required this.onSwap,
    this.barHovered = false,
  });

  /// The transient title line — `→ 01:23 · 02:19 left` (§6).
  final ValueChanged<String> onSwap;

  /// The pointer rests anywhere on the bar. The preview raises the head
  /// tick on `.bar:hover` (the whole strip, `.bar:hover .head`), so the
  /// line answers the cursor even before it reaches the meter's own zone.
  final bool barHovered;

  @override
  State<MiniSeekLine> createState() => _MiniSeekLineState();
}

class _MiniSeekLineState extends State<MiniSeekLine> {
  final PlayerService _player = PlayerService.instance;
  late final Listenable _merged;

  /// Press/drag preview fraction (0..1) — `null` while nothing is pressed.
  double? _pressFrac;

  /// X where the current press started (the drag slop check).
  double? _downX;

  bool _dragging = false;

  /// The pointer rests on the line itself — the head tick's other cue,
  /// on top of [MiniSeekLine.barHovered].
  bool _hovering = false;

  /// Movement (in logical px) that turns a press into a drag — the
  /// timeline's own slop.
  static const double _dragSlop = 6;

  @override
  void initState() {
    super.initState();
    _merged = Listenable.merge(<Listenable>[
      _player.position,
      _player.duration,
      _player.transportState,
      _player.hasMedia,
    ]);
    // Stop (or a channel switch) can take the strip out from under a
    // half-finished scrub; the press state must not survive it.
    _merged.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _merged.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (_pressFrac == null || _usable) return;
    setState(() {
      _pressFrac = null;
      _downX = null;
      _dragging = false;
    });
  }

  /// The strip is live only while the engine actually holds a seekable item:
  /// nothing loaded, a parked queue (Stop released the item) and live
  /// channel mode are all inert — the same gate the full timeline uses.
  bool get _usable =>
      !_player.isLiveMode &&
      _player.hasMedia.value &&
      _player.duration.value > Duration.zero;

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  /// Pointer x → the track's own fraction. The line is inset by
  /// [MiniMetrics.seekInset] at each end, so the ends of the track — not the
  /// ends of the window — are 0 % and 100 %.
  double _fracAt(double dx, double width) {
    final double track = width - MiniMetrics.seekInset * 2;
    if (track <= 0) return 0;
    return _clamp01((dx - MiniMetrics.seekInset) / track);
  }

  Duration _targetFor(double frac) => Duration(
        milliseconds: (frac * _player.duration.value.inMilliseconds).round(),
      );

  void _commit(double frac) {
    if (!_usable) return;
    final Duration target = _targetFor(frac);
    // A line click is another transport action — it resets both seek ramps
    // (the same rule the full window's timeline follows).
    TransportActions.instance.resetSeekRamps();
    _player.seekTo(target);
    widget.onSwap(_readout(target));
  }

  /// §6 — `→ 01:23 · 02:19 left`.
  String _readout(Duration target) {
    final Duration duration = _player.duration.value;
    final Duration left = duration - target;
    return '→ ${formatClockCompact(target)} · '
        '${formatClockCompact(left < Duration.zero ? Duration.zero : left)} left';
  }

  void _onPointerDown(PointerDownEvent e, double w) {
    if (!_usable) return;
    _downX = e.localPosition.dx;
    _dragging = false;
    final double frac = _fracAt(e.localPosition.dx, w);
    setState(() => _pressFrac = frac);
    widget.onSwap(_readout(_targetFor(frac)));
  }

  void _onPointerMove(PointerMoveEvent e, double w) {
    if (_pressFrac == null) return; // not pressed on this line
    final double dx = e.localPosition.dx;
    if (!_dragging) {
      final double? downX = _downX;
      if (downX == null || (dx - downX).abs() < _dragSlop) return;
      _dragging = true;
    }
    final double frac = _fracAt(dx, w);
    setState(() => _pressFrac = frac);
    widget.onSwap(_readout(_targetFor(frac)));
  }

  void _onPointerUp(PointerUpEvent e, double w) {
    final double? frac = _pressFrac;
    if (frac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Click and drag both commit exactly where the pointer was released.
    _commit(_fracAt(e.localPosition.dx, w));
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_pressFrac == null) return;
    _downX = null;
    _dragging = false;
    setState(() => _pressFrac = null);
    // Cancel = abandon the scrub, no seek (the timeline's rule).
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: (BuildContext context, Widget? _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double w = constraints.maxWidth;
            final bool usable = _usable;
            final Duration duration = usable ? _player.duration.value : Duration.zero;
            final double live = duration > Duration.zero
                ? (duration.inMicroseconds <= 0
                    ? 0.0
                    : (_player.position.value.inMicroseconds /
                            duration.inMicroseconds)
                        .clamp(0.0, 1.0)
                        .toDouble())
                : 0.0;

            // A live line owns the bar's top band (the preview stacks its
            // `.seekhit` above the control row); an inert one gets out of
            // the way completely, so the controls under it keep every
            // pixel of their own hit boxes.
            return IgnorePointer(
              ignoring: !usable,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent e) => _onPointerDown(e, w),
                onPointerMove: (PointerMoveEvent e) => _onPointerMove(e, w),
                onPointerUp: (PointerUpEvent e) => _onPointerUp(e, w),
                onPointerCancel: _onPointerCancel,
                child: MouseRegion(
                  cursor: usable
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onEnter: (_) => setState(() => _hovering = true),
                  onExit: (_) => setState(() => _hovering = false),
                  child: Tooltip(
                    message: 'Seek',
                    waitDuration: const Duration(milliseconds: 600),
                    child: CustomPaint(
                      painter: MiniProgressStrip(
                        frac: _pressFrac ?? live,
                        head: usable &&
                            (widget.barHovered ||
                                _hovering ||
                                _pressFrac != null),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The top-edge strip: track, fill, and the hover/scrub head tick.
class MiniProgressStrip extends CustomPainter {
  const MiniProgressStrip({required this.frac, required this.head});

  /// 0–1 fill; the track is drawn full width whatever this says, because
  /// every pixel of the bar is persistent (§7).
  final double frac;

  /// Whether the head tick is up (hovering or scrubbing the line).
  final bool head;

  @override
  void paint(Canvas canvas, Size size) {
    final double trackWidth = size.width - MiniMetrics.seekInset * 2;
    if (trackWidth <= 0) return;
    final Rect track = Rect.fromLTWH(
      MiniMetrics.seekInset,
      MiniMetrics.seekTop,
      trackWidth,
      MiniMetrics.seekHeight,
    );
    final RRect rounded =
        RRect.fromRectAndRadius(track, const Radius.circular(1));
    canvas.drawRRect(rounded, Paint()..color = AppColors.barTrack);

    final double filled = (frac.clamp(0.0, 1.0).toDouble()) * trackWidth;
    if (filled > 0) {
      canvas.save();
      // The fill keeps the track's rounded ends.
      canvas.clipRRect(rounded);
      canvas.drawRect(
        Rect.fromLTWH(track.left, track.top, filled, track.height),
        Paint()..color = AppColors.barFill,
      );
      canvas.restore();
    }

    if (!head) return;
    canvas.drawCircle(
      Offset(track.left + filled, track.center.dy),
      MiniMetrics.seekHeadSize / 2,
      Paint()..color = AppColors.barThumb,
    );
  }

  @override
  bool shouldRepaint(MiniProgressStrip old) =>
      old.frac != frac || old.head != head;
}
