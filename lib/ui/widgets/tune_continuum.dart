import 'dart:async';

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
import '../../core/tune_service.dart';
import '../../theme/app_theme.dart';
import '../osc/hover_chip.dart';

/// SALU's selection language: **a thin line with labeled stops**
/// (eq_imp.md §3) — one widget, used four times.
///
/// The knob rests ON a stop (a named setting) or BETWEEN stops (a blend),
/// and the floating label above it always names what it is on. The gestures
/// are the locked set (§8):
///
///   · hover ~300 ms → live preview of the value under the cursor
///   · leave         → revert, nothing saved
///   · click         → keep it (snapped to the named stop when near one)
///   · drag          → live, release keeps
///
/// The two hover gestures are the **Mouse over preview** switch in Settings
/// (default **Off**): off, a hover only brightens the row — the line moves
/// on a click or a drag, and never because a pointer crossed it.
///
/// The widget holds no values of its own — every position comes in, every
/// change goes out through [onChanged] — so the panel, the keyboard tier and
/// the service can never disagree.
class TuneContinuum extends StatefulWidget {
  const TuneContinuum({
    super.key,
    required this.title,
    required this.line,
    required this.position,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.trailing,
    this.below,
    this.marks = const <Widget>[],
    this.titleExtra,
    this.previewDelay = const Duration(milliseconds: 300),
    this.onPreviewStart,
    this.onPreviewEnd,
    this.onGestureStart,
    this.onGestureEnd,
    this.previewing = false,
    this.focused = false,
    this.custom = false,
  });

  /// The part's name, spoken once at the row's head — never an instruction.
  final String title;

  /// The math: stops, positions, snapping.
  final Continuum line;

  /// The knob's current position, 0…1.
  final double position;

  /// The floating label's text (the service formats it).
  final String label;

  /// Live change. `commit == false` while dragging or previewing, `true` on
  /// release (the line snaps then).
  final void Function(double position, bool commit) onChanged;

  /// False dims the row and swallows every pointer event (audio-only files
  /// dim their video parts; live media dims the whole panel).
  final bool enabled;

  /// The right of the row: the toggle (Snap window · Keep pitch).
  final Widget? trailing;

  /// Below the line: the fine sliders.
  final Widget? below;

  /// Below the line, at the left: the marks that live AROUND the line
  /// (My · save · curve-on-video).
  final List<Widget> marks;

  /// Beside the title: the Auto EQ indicator dot.
  final Widget? titleExtra;

  /// How long a pointer must rest here before the preview starts (§8).
  final Duration previewDelay;

  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  /// Whether what is on screen is a preview that will revert — the knob then
  /// stays quiet, because a hover is not a decision yet.
  final bool previewing;

  /// The line the keyboard tier is driving (eq_imp.md §6's "one part at a
  /// time"). No legend, no instruction — the part's name simply comes up
  /// white, the same answer every label in the house gives to attention.
  final bool focused;

  /// The value in force is a hand-edited curve (§4's `Custom`): the knob
  /// parks on the nearest stop, but that stop's name is not lit — the chip
  /// says `Custom` and no stop borrows its name for someone else's numbers.
  final bool custom;

  @override
  State<TuneContinuum> createState() => _TuneContinuumState();
}

class _TuneContinuumState extends State<TuneContinuum> {
  Timer? _armTimer;
  bool _armed = false; // the rest-time elapsed → the preview is live
  bool _dragging = false;
  bool _inside = false;
  double _hoverT = 0;

  /// Keeps the knob inside the row at both ends.
  static const double _inset = 10;

  static const double _chipWidth = 96;
  static const double _lineHeight = 48;
  static const double _lineY = 26;

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  double _tAt(double dx, double width) {
    final double span = width - _inset * 2;
    if (span <= 0) return 0;
    return clampRange((dx - _inset) / span, 0, 1);
  }

  void _arm() {
    _armTimer?.cancel();
    if (!widget.enabled || widget.line.isEmpty) return;
    // Mouse over preview (Settings → Equalizer): off, a rest on the line is
    // only a rest. The pointer never moves the knob, never touches the
    // engine, and the label keeps naming the value really in force.
    if (!TuneService.instance.hoverPreview) return;
    _armTimer = Timer(widget.previewDelay, () {
      if (!_inside || !widget.enabled || _armed) return;
      setState(() => _armed = true);
      widget.onPreviewStart?.call();
      widget.onChanged(_hoverT, false);
    });
  }

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    if (!_armed) return;
    _armed = false;
    widget.onPreviewEnd?.call();
  }

  /// A click keeps what it landed on — the preview becomes the value, so the
  /// revert must be dropped without firing.
  void _disarmSilently() {
    _armTimer?.cancel();
    _armTimer = null;
    _armed = false;
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled;
    return Opacity(
      opacity: on ? 1 : 0.42,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _head(),
            SizedBox(
              height: _lineHeight,
              child: IgnorePointer(
                ignoring: !on,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double w = box.maxWidth;
                    return MouseRegion(
                      // `PointerEnterEvent` is not in the gestures export the
                      // house imports, so the supertype stands in — a hover
                      // event carries the same local position anyway.
                      onEnter: (PointerEvent e) {
                        _inside = true;
                        _hoverT = _tAt(e.localPosition.dx, w);
                        setState(() {});
                        _arm();
                      },
                      onExit: (PointerExitEvent _) {
                        _inside = false;
                        setState(() {});
                        if (!_dragging) _disarm();
                      },
                      onHover: (PointerHoverEvent e) {
                        _hoverT = _tAt(e.localPosition.dx, w);
                        if (_armed && !_dragging) {
                          widget.onChanged(_hoverT, false);
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (PointerDownEvent e) {
                          if (!on) return;
                          setState(() => _dragging = true);
                          widget.onGestureStart?.call();
                          widget.onChanged(_tAt(e.localPosition.dx, w), false);
                        },
                        onPointerMove: (PointerMoveEvent e) {
                          if (!_dragging) return;
                          widget.onChanged(_tAt(e.localPosition.dx, w), false);
                        },
                        onPointerUp: (PointerUpEvent e) {
                          if (!_dragging) return;
                          setState(() => _dragging = false);
                          widget.onChanged(_tAt(e.localPosition.dx, w), true);
                          widget.onGestureEnd?.call();
                          _disarmSilently();
                        },
                        onPointerCancel: (PointerCancelEvent e) {
                          if (!_dragging) return;
                          setState(() => _dragging = false);
                          widget.onGestureEnd?.call();
                        },
                        child: _body(w),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (widget.below != null || widget.marks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (widget.marks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 0, 2),
                        child: Row(children: widget.marks),
                      ),
                    if (widget.below != null) widget.below!,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The row's head: the part's name at the left, its toggle at the right.
  Widget _head() {
    return SizedBox(
      height: 18,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    widget.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.focused || _inside || _dragging
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                if (widget.titleExtra != null) ...<Widget>[
                  const SizedBox(width: 6),
                  widget.titleExtra!,
                ],
              ],
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }

  Widget _body(double w) {
    final double span =
        (w - _inset * 2).clamp(0.0, double.infinity).toDouble();
    final double knobX = _inset + span * widget.position;
    final List<double> stops = <double>[
      for (int i = 0; i < widget.line.length; i++)
        _inset + span * widget.line.positionOf(i),
    ];
    final bool bright = _inside || _dragging;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _ContinuumPainter(
              stops: stops,
              knobX: knobX,
              lineY: _lineY,
              enabled: widget.enabled,
              previewing: widget.previewing,
              bright: bright,
            ),
          ),
        ),
        // The floating label: it names what the knob is on and glides with
        // it — nothing else in the row moves.
        Positioned(
          left: (knobX - _chipWidth / 2)
              .clamp(0.0, (w - _chipWidth).clamp(0.0, w))
              .toDouble(),
          top: 0,
          child: IgnorePointer(
            child: HoverChip(label: widget.label, width: _chipWidth),
          ),
        ),
        // The stop labels, centred under their ticks and clamped inside the
        // row. Display-only: a click anywhere on the row picks the position
        // under the cursor, which lands on the same stop.
        for (int i = 0; i < widget.line.length; i++)
          _stopLabel(i, w, span, widget.line.length > 1 ? span / (widget.line.length - 1) : span),
      ],
    );
  }

  /// A label's honest width at 9 px — narrower than the font size suggests,
  /// because these are short lowercase words.
  static double _labelWidth(String label) => label.length * 4.7 + 6;

  Widget _stopLabel(int i, double w, double span, double pitch) {
    final ContinuumStop stop = widget.line.stopAt(i);
    final double position = widget.line.positionOf(i);
    final double x = _inset + span * position;
    final double est = _labelWidth(stop.label);
    final bool on =
        !widget.custom && (widget.position - position).abs() < 1e-6;
    // Thirteen names on one line cannot all fit at rest — so at rest the line
    // says every other one, and the moment the pointer is on the line they are
    // all there. Never a scroll, never a truncation, never a tooltip.
    final bool crowded = est + 4 > pitch;
    final bool many = _inside || _dragging || on;
    if (crowded && !many && i != 0 && i != widget.line.length - 1) {
      return const SizedBox.shrink();
    }
    final double left =
        (x - est / 2).clamp(0.0, (w - est).clamp(0.0, w)).toDouble();
    return Positioned(
      left: left,
      top: 32,
      width: est,
      child: IgnorePointer(
        child: SizedBox(
          height: 14,
          child: Center(
            child: Text(
              stop.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 9,
                height: 1,
                letterSpacing: 0.2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on
                    ? AppColors.textPrimary
                    : AppColors.textSecondary.withAlpha(200),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line itself: a hair-thin rule, one tick per stop, and the knob.
class _ContinuumPainter extends CustomPainter {
  const _ContinuumPainter({
    required this.stops,
    required this.knobX,
    required this.lineY,
    required this.enabled,
    required this.previewing,
    required this.bright,
  });

  final List<double> stops;
  final double knobX;
  final double lineY;
  final bool enabled;
  final bool previewing;
  final bool bright;

  @override
  void paint(Canvas canvas, Size size) {
    final Color base = enabled
        ? (bright ? AppColors.textPrimary : AppColors.iconIdle)
        : AppColors.iconIdle.withAlpha(110);
    canvas.drawLine(
      Offset(10, lineY),
      Offset(size.width - 10, lineY),
      Paint()
        ..color = base.withAlpha(bright ? 110 : 80)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    final Paint tick = Paint()
      ..color = base.withAlpha(170)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final double x in stops) {
      canvas.drawLine(Offset(x, lineY - 4), Offset(x, lineY + 4), tick);
    }

    final Color knobColor = !enabled
        ? AppColors.iconIdle.withAlpha(120)
        : (previewing ? AppColors.textSecondary : AppColors.textPrimary);
    canvas.drawCircle(
      Offset(knobX, lineY),
      4.5,
      Paint()
        ..color = knobColor
        ..style = PaintingStyle.fill,
    );
    // The faint ring is a KEPT position — a preview never glows (the house
    // reserves glow for active states).
    if (enabled && !previewing) {
      canvas.drawCircle(
        Offset(knobX, lineY),
        7,
        Paint()
          ..color = Colors.white.withAlpha(34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_ContinuumPainter old) =>
      old.knobX != knobX ||
      old.enabled != enabled ||
      old.previewing != previewing ||
      old.bright != bright ||
      old.stops.length != stops.length;
}

/// A tune row's toggle (Snap window · Keep pitch) — the settings switch's
/// shape at panel scale, so the two never read as different controls.
class TuneSwitch extends StatelessWidget {
  const TuneSwitch({
    super.key,
    required this.label,
    required this.on,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!on) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.4,
                  color: !enabled
                      ? AppColors.textSecondary.withAlpha(110)
                      : (on ? AppColors.textPrimary : AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 26,
                height: 15,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: on && enabled
                      ? AppColors.accent
                      : const Color(0xFF3A3A3C),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
