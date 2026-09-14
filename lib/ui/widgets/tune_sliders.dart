import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent;
import 'package:flutter/material.dart';

import '../../core/tune/tune_model.dart';
import '../../theme/app_theme.dart';
import 'eq_curve_painter.dart';

/// The fine-tune layer below two of the four continua (eq_imp.md §1.2 · §4):
/// the 10 band sliders under the audio line, the 5 value bars under the
/// picture line. Both follow the locked gesture set — hover rests ~300 ms
/// and PREVIEWs the value under the cursor, leaving reverts, a click or a
/// released drag keeps — and both reset to zero on a double tap.
///
/// Nothing here stores a value: the numbers arrive in, the changes leave
/// through the callbacks, so the panel and the service agree by construction.

/// The house preview delay (TuneService.hoverLead's value, kept as a plain
/// constant so the widgets stay free of the service import).
const Duration kTuneHoverLead = Duration(milliseconds: 300);

/// Double-tap window — the sliders' reset-to-zero gesture (§1.11).
const Duration kTuneDoubleTap = Duration(milliseconds: 320);

/// The band slider's track, in its 74 px box: rule from top to bottom, the
/// label under it.
const double _bandTop = 4;
const double _bandBottom = 44;
const double _bandLabelTop = 47;

/// A ±12 dB grid quantised to halves: the number the slider holds, the
/// number the label shows, and the number a preset is matched against.
double quantizeGain(double db) =>
    clampRange((db * 2).roundToDouble() / 2, kEqGainMin, kEqGainMax);

/// One of the picture bars' −100…+100 values, whole numbers only.
double quantizeFine(double v) =>
    clampRange(v.roundToDouble(), kPictureMin, kPictureMax);

// ── The glide (§1.11) ──────────────────────────────────────────────────────

/// Smoothly chases a list of values — "the sliders smoothly slide into a new
/// curve (not a jump), also when Auto EQ applies a preset at file load".
///
/// Small steps (a drag, a key repeat) are adopted instantly so the control
/// never fights the pointer; only a real jump — a preset, a look, a reset —
/// gets animated.
class GlideList extends StatefulWidget {
  const GlideList({
    super.key,
    required this.values,
    required this.builder,
    this.jumpThreshold = 1.2,
    this.duration = const Duration(milliseconds: 200),
  });

  final List<double> values;
  final Widget Function(BuildContext context, List<double> shown) builder;

  /// A change larger than this (in any slot) glides; smaller ones land.
  final double jumpThreshold;

  final Duration duration;

  @override
  State<GlideList> createState() => _GlideListState();
}

class _GlideListState extends State<GlideList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<double> _shown;
  List<double> _from = const <double>[];

  @override
  void initState() {
    super.initState();
    _shown = List<double>.of(widget.values);
    _from = List<double>.of(widget.values);
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_tick);
  }

  @override
  void didUpdateWidget(GlideList old) {
    super.didUpdateWidget(old);
    if (listEquals(old.values, widget.values)) return;
    final List<double> target = widget.values;
    double delta = 0;
    for (int i = 0; i < target.length && i < _shown.length; i++) {
      delta = math.max(delta, (target[i] - _shown[i]).abs());
    }
    _from = List<double>.of(_shown);
    if (delta <= widget.jumpThreshold || target.length != _shown.length) {
      // A drag increment — no animation to catch up with.
      _shown = List<double>.of(target);
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1;
      setState(() {});
      return;
    }
    setState(() {});
    _controller.forward(from: 0);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double t = Curves.easeOutCubic.transform(_controller.value);
    final List<double> target = widget.values;
    final List<double> shown = List<double>.filled(target.length, 0);
    for (int i = 0; i < target.length; i++) {
      final double from = i < _from.length ? _from[i] : target[i];
      shown[i] = from + (target[i] - from) * t;
    }
    return widget.builder(context, shown);
  }
}

// ── The 10 band sliders ────────────────────────────────────────────────────

/// The audio line's fine layer: the curve line, then 10 bands, 31 Hz to
/// 16 kHz. `below` the audio continuum (§3's "around the lines").
class TuneBands extends StatelessWidget {
  const TuneBands({
    super.key,
    required this.gains,
    required this.enabled,
    required this.onBand,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.onGestureStart,
    this.onGestureEnd,
  });

  final List<double> gains;
  final bool enabled;
  final void Function(int index, double db, bool commit) onBand;
  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  static const double bandWidth = 34;
  static const double bandHeight = 62;
  static const double curveHeight = 20;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The response at a glance (§1.11) — the same painter as the
        // on-video drawing, so the two can never disagree.
        SizedBox(
          height: curveHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GlideList(
              values: gains,
              builder: (BuildContext context, List<double> shown) {
                return CustomPaint(
                  painter: EqCurvePainter(
                    gains: shown,
                    ink: AppColors.iconIdle,
                    fill: true,
                    strokeWidth: 1.3,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: bandHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < kEqBandCount; i++)
                Expanded(
                  child: _TuneBand(
                    index: i,
                    label: kEqBandLabels[i],
                    value: gains.length > i ? gains[i] : 0,
                    enabled: enabled,
                    onChanged: onBand,
                    onPreviewStart: onPreviewStart,
                    onPreviewEnd: onPreviewEnd,
                    onGestureStart: onGestureStart,
                    onGestureEnd: onGestureEnd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One band: a thin vertical rule, a notch at zero, a knob, and the
/// frequency label that becomes the value while it is being worked — the
/// house bar language, vertical.
class _TuneBand extends StatefulWidget {
  const _TuneBand({
    required this.index,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.onGestureStart,
    this.onGestureEnd,
  });

  final int index;
  final String label;
  final double value;
  final bool enabled;
  final void Function(int index, double db, bool commit) onChanged;
  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  @override
  State<_TuneBand> createState() => _TuneBandState();
}

class _TuneBandState extends State<_TuneBand> {
  Timer? _armTimer;
  bool _armed = false;
  bool _dragging = false;
  bool _inside = false;
  DateTime? _lastUp;
  double _hoverValue = 0;

  static double get _mid => (_bandTop + _bandBottom) / 2;
  static double get _half => (_bandBottom - _bandTop) / 2;

  double _valueAt(double dy) => quantizeGain((_mid - dy) / _half * kEqGainMax);

  static double _yFor(double gain) =>
      _mid - clampRange(gain, kEqGainMin, kEqGainMax) / kEqGainMax * _half;

  void _arm() {
    _armTimer?.cancel();
    if (!widget.enabled) return;
    _armTimer = Timer(kTuneHoverLead, () {
      if (!_inside || _armed || _dragging || !widget.enabled) return;
      setState(() => _armed = true);
      widget.onPreviewStart?.call();
      widget.onChanged(widget.index, _hoverValue, false);
    });
  }

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    if (!_armed || _dragging) return;
    _armed = false;
    widget.onPreviewEnd?.call();
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _inside || _dragging;
    return SizedBox(
      height: TuneBands.bandHeight,
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double h = box.maxHeight;
            return MouseRegion(
              onEnter: (PointerEvent e) {
                _inside = true;
                // The value under the pointer, from the first moment — a
                // rest that previews 0 dB would be a lie.
                _hoverValue = _valueAt(e.localPosition.dy);
                setState(() {});
                _arm();
              },
              onExit: (PointerExitEvent _) {
                _inside = false;
                setState(() {});
                if (!_dragging) _disarm();
              },
              onHover: (PointerHoverEvent e) {
                _hoverValue = _valueAt(e.localPosition.dy);
                if (_armed && !_dragging) {
                  widget.onChanged(widget.index, _hoverValue, false);
                }
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent e) {
                  setState(() => _dragging = true);
                  widget.onGestureStart?.call();
                  widget.onChanged(widget.index, _valueAt(e.localPosition.dy), false);
                },
                onPointerMove: (PointerMoveEvent e) {
                  if (!_dragging) return;
                  widget.onChanged(widget.index, _valueAt(e.localPosition.dy), false);
                },
                onPointerUp: (PointerUpEvent e) {
                  if (!_dragging) return;
                  final DateTime now = DateTime.now();
                  final bool doubleUp = _lastUp != null &&
                      now.difference(_lastUp!) < kTuneDoubleTap;
                  _lastUp = now;
                  setState(() => _dragging = false);
                  if (doubleUp) {
                    // Double tap = back to zero (§1.11).
                    widget.onChanged(widget.index, 0, true);
                  } else {
                    widget.onChanged(
                        widget.index, _valueAt(e.localPosition.dy), true);
                  }
                  widget.onGestureEnd?.call();
                  _armTimer?.cancel();
                  _armed = false;
                },
                onPointerCancel: (PointerCancelEvent _) {
                  if (!_dragging) return;
                  setState(() => _dragging = false);
                  widget.onGestureEnd?.call();
                },
                child: CustomPaint(
                  size: Size(box.maxWidth, h),
                  painter: _BandPainter(
                    y: _yFor(widget.value),
                    mid: _mid,
                    active: active,
                    previewing: _armed && !_dragging,
                    enabled: widget.enabled,
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _bandLabelTop,
                        child: Text(
                          active
                              ? formatGainDb(widget.value)
                              : widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1,
                            letterSpacing: 0.2,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textSecondary.withAlpha(200),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  const _BandPainter({
    required this.y,
    required this.mid,
    required this.active,
    required this.previewing,
    required this.enabled,
  });

  final double y;
  final double mid;
  final bool active;
  final bool previewing;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final double x = size.width / 2;
    final Color idle = enabled
        ? (active ? AppColors.textPrimary : AppColors.iconIdle)
        : AppColors.iconIdle.withAlpha(100);
    // The rule.
    canvas.drawLine(
      Offset(x, _bandTop),
      Offset(x, _bandBottom),
      Paint()
        ..color = idle.withAlpha(90)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    // The zero notch.
    canvas.drawLine(
      Offset(x - 4.5, mid),
      Offset(x + 4.5, mid),
      Paint()
        ..color = idle.withAlpha(150)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    // The filled span from zero to the knob.
    if ((y - mid).abs() > 0.6) {
      canvas.drawLine(
        Offset(x, mid),
        Offset(x, y),
        Paint()
          ..color = idle.withAlpha(210)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
    // The knob.
    canvas.drawCircle(
      Offset(x, y),
      3.4,
      Paint()
        ..color = !enabled
            ? AppColors.iconIdle.withAlpha(120)
            : (previewing ? AppColors.textSecondary : AppColors.textPrimary),
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.y != y ||
      old.active != active ||
      old.previewing != previewing ||
      old.enabled != enabled;
}

// ── The 5 picture bars ─────────────────────────────────────────────────────

/// The picture line's fine layer (eq_imp.md §4): Saturation · Gamma ·
/// Contrast · Brightness · Hue, each −100…+100, 0 = neutral. Always
/// live-bound to whatever the knob is on — a look, a blend, or free.
class TunePictureBars extends StatelessWidget {
  const TunePictureBars({
    super.key,
    required this.values,
    required this.enabled,
    required this.onValue,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.onGestureStart,
    this.onGestureEnd,
  });

  final List<double> values;
  final bool enabled;
  final void Function(int index, double value, bool commit) onValue;
  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < kPictureKeys.length; i++)
            _TuneFineBar(
              index: i,
              label: kPictureLabels[i],
              value: values.length > i ? values[i] : 0,
              enabled: enabled,
              onChanged: onValue,
              onPreviewStart: onPreviewStart,
              onPreviewEnd: onPreviewEnd,
              onGestureStart: onGestureStart,
              onGestureEnd: onGestureEnd,
            ),
        ],
      ),
    );
  }
}

class _TuneFineBar extends StatefulWidget {
  const _TuneFineBar({
    required this.index,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.onPreviewStart,
    this.onPreviewEnd,
    this.onGestureStart,
    this.onGestureEnd,
  });

  final int index;
  final String label;
  final double value;
  final bool enabled;
  final void Function(int index, double value, bool commit) onChanged;
  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  @override
  State<_TuneFineBar> createState() => _TuneFineBarState();
}

class _TuneFineBarState extends State<_TuneFineBar> {
  Timer? _armTimer;
  bool _armed = false;
  bool _dragging = false;
  bool _inside = false;
  DateTime? _lastUp;
  double _hoverValue = 0;

  static const double _barHeight = 18;

  double _valueAt(double dx, double width) {
    final double usable = width - 12;
    if (usable <= 0) return 0;
    final double t = clampRange((dx - 6) / usable, 0, 1) * 2 - 1;
    return quantizeFine(t * kPictureMax);
  }

  void _arm() {
    _armTimer?.cancel();
    if (!widget.enabled) return;
    _armTimer = Timer(kTuneHoverLead, () {
      if (!_inside || _armed || _dragging || !widget.enabled) return;
      setState(() => _armed = true);
      widget.onPreviewStart?.call();
      widget.onChanged(widget.index, _hoverValue, false);
    });
  }

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    if (!_armed || _dragging) return;
    _armed = false;
    widget.onPreviewEnd?.call();
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _inside || _dragging;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 2, 1),
      child: SizedBox(
        height: 20,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 50,
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.4,
                  height: 1,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: IgnorePointer(
                ignoring: !widget.enabled,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double w = box.maxWidth;
                    return MouseRegion(
                      onEnter: (PointerEvent e) {
                        _inside = true;
                        _hoverValue = _valueAt(e.localPosition.dx, w);
                        setState(() {});
                        _arm();
                      },
                      onExit: (PointerExitEvent _) {
                        _inside = false;
                        setState(() {});
                        if (!_dragging) _disarm();
                      },
                      onHover: (PointerHoverEvent e) {
                        _hoverValue = _valueAt(e.localPosition.dx, w);
                        if (_armed && !_dragging) {
                          widget.onChanged(widget.index, _hoverValue, false);
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (PointerDownEvent e) {
                          setState(() => _dragging = true);
                          widget.onGestureStart?.call();
                          widget.onChanged(
                              widget.index, _valueAt(e.localPosition.dx, w), false);
                        },
                        onPointerMove: (PointerMoveEvent e) {
                          if (!_dragging) return;
                          widget.onChanged(
                              widget.index, _valueAt(e.localPosition.dx, w), false);
                        },
                        onPointerUp: (PointerUpEvent e) {
                          if (!_dragging) return;
                          final DateTime now = DateTime.now();
                          final bool doubleUp = _lastUp != null &&
                              now.difference(_lastUp!) < kTuneDoubleTap;
                          _lastUp = now;
                          setState(() => _dragging = false);
                          widget.onChanged(
                            widget.index,
                            doubleUp ? 0 : _valueAt(e.localPosition.dx, w),
                            true,
                          );
                          widget.onGestureEnd?.call();
                          _armTimer?.cancel();
                          _armed = false;
                        },
                        onPointerCancel: (PointerCancelEvent _) {
                          if (!_dragging) return;
                          setState(() => _dragging = false);
                          widget.onGestureEnd?.call();
                        },
                        child: CustomPaint(
                          size: Size(w, _barHeight),
                          painter: _FineBarPainter(
                            value: widget.value,
                            active: active,
                            previewing: _armed && !_dragging,
                            enabled: widget.enabled,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                widget.value == 0
                    ? '0'
                    : widget.value.round().toString(),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  letterSpacing: 0.2,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary.withAlpha(190),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A −100…+100 bar that grows from its centre, breathing on hover (the
/// timeline's and the volume bar's sibling, mirrored).
class _FineBarPainter extends CustomPainter {
  const _FineBarPainter({
    required this.value,
    required this.active,
    required this.previewing,
    required this.enabled,
  });

  final double value;
  final bool active;
  final bool previewing;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final double mid = w / 2;
    final Color idle = enabled
        ? (active ? AppColors.textPrimary : AppColors.iconIdle)
        : AppColors.iconIdle.withAlpha(100);
    final RRect track = RRect.fromRectAndRadius(
      Rect.fromLTWH(6, (h - 6) / 2, w - 12, 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      track,
      Paint()..color = active ? const Color(0xFF3C3C40) : AppColors.barTrack,
    );
    final double t = clampRange(value / kPictureMax, -1, 1);
    if (t.abs() > 0.005) {
      final double from = mid + (w / 2 - 6) * (t < 0 ? t : 0);
      final double to = mid + (w / 2 - 6) * (t > 0 ? t : 0);
      final Rect fill = Rect.fromLTRB(from, (h - 6) / 2, to, (h - 6) / 2 + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(3)),
        Paint()
          ..color = (previewing
                  ? AppColors.barFill.withAlpha(150)
                  : AppColors.barFill)
              .withAlpha(230),
      );
    }
    // Zero tick, so the neutral point is visible without hovering.
    canvas.drawLine(
      Offset(mid, 3),
      Offset(mid, h - 3),
      Paint()
        ..color = idle.withAlpha(140)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(mid + (w / 2 - 6) * t, h / 2),
      3,
      Paint()
        ..color = !enabled
            ? AppColors.iconIdle.withAlpha(120)
            : (previewing ? AppColors.textSecondary : AppColors.textPrimary),
    );
  }

  @override
  bool shouldRepaint(_FineBarPainter old) =>
      old.value != value ||
      old.active != active ||
      old.previewing != previewing ||
      old.enabled != enabled;
}
