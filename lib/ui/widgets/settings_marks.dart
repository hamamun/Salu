import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'salu_marks.dart' show markInk, markStrokeFor;

/// Candidate sketches for SALU's Settings mark (2026-09-28) — the seven
/// proposals from the icon review, drawn in the family's stroke language
/// (follow.md rule 6): thin, monochrome, geometric, round-capped, color
/// from the ambient [IconTheme] so [SaluIconButton]'s gray → white glide
/// lights them like every other mark.
///
/// Candidates:
///   · [KnobMark]          — hi-fi rotary knob (circle + pointer)
///   · [HubMark]           — hub & spokes (where everything converges)
///   · [SpiritLevelMark]   — spirit level (calibration, the house is level)
///   · [BalanceMark]       — hanging balance (the house weighs its choices)
///   · [DialFaceMark]      — instrument dial face (index ring)
///   · [DipBankMark]       — DIP-switch bank (the settings plate inside)
///   · [SelectorRingMark]  — six dots on a dial (six dots, dial plate)
///   · [CascadeMark]       — six dots in a 3-2-1 cascade (six dots, evolved)
///
/// Each mark takes an optional [motion] — the §2 recipe's hover phase:
/// 0 = at rest, 1 = fully engaged. Marks with no useful hover motion
/// ignore it (the lighting alone is the motion). Nothing is ever drawn
/// behind a mark; motion is carried by the mark itself.
///
/// None of these is wired into the app yet — pick one, then it replaces
/// [DotGridIcon] in the title bar and the settings header together.

/// Hi-fi rotary knob: a thin circle with a radial pointer at 1 o'clock.
/// Settings as the back-panel knob of a media machine.
///
/// Hover: the pointer swings 25° clockwise and stays — "you touched it".
class KnobMark extends StatelessWidget {
  const KnobMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; turns the pointer 25° further clockwise.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _KnobPainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);
    final double r = s * 0.34;

    canvas.drawCircle(c, r, paint);

    // Pointer: 1 o'clock at rest (30° right of 12), +25° on hover.
    final double angle =
        -math.pi / 2 + math.pi / 6 + motion * (25 * math.pi / 180);
    canvas.drawLine(
      c,
      Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Hub & spokes: a small ring with four diagonal spokes that stop short
/// of the edge. Settings is where every subsystem converges.
///
/// Hover: the hub ticks 15° like a selector stepping to the next detent.
class HubMark extends StatelessWidget {
  const HubMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; rotates the spokes 15°.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HubPainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _HubPainter extends CustomPainter {
  const _HubPainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);

    canvas.drawCircle(c, s * 0.22, paint);

    // Four spokes on the diagonals (never axis-aligned — that is the plus),
    // growing straight out of the ring: a hub, never a sparkle.
    final double spin = motion * math.pi / 12;
    for (int i = 0; i < 4; i++) {
      final double a = math.pi / 4 + i * math.pi / 2 + spin;
      canvas.drawLine(
        Offset(
          c.dx + s * 0.22 * math.cos(a),
          c.dy + s * 0.22 * math.sin(a),
        ),
        Offset(
          c.dx + s * 0.42 * math.cos(a),
          c.dy + s * 0.42 * math.sin(a),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HubPainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Spirit level: a hairline capsule with one small bubble resting slightly
/// off-center. Not "preferences" — calibration: the house is level.
///
/// Hover: the bubble slides to dead center — "click, it's set".
class SpiritLevelMark extends StatelessWidget {
  const SpiritLevelMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; slides the bubble from off-center to center.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter:
          _SpiritLevelPainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _SpiritLevelPainter extends CustomPainter {
  const _SpiritLevelPainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;

    // Capsule body — one stroked outline, height 0.40 s so the capsule
    // radius is 0.20 s (a true pill, like GlassCapsule's silhouette).
    final Rect body = Rect.fromLTWH(s * 0.06, s * 0.30, s * 0.88, s * 0.40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(s * 0.20)),
      paint,
    );

    // Calibration ticks at the vial's center — they keep the mark a
    // level, not a toggle switch, at caption size.
    canvas.drawLine(
      Offset(s * 0.5, s * 0.335),
      Offset(s * 0.5, s * 0.415),
      paint,
    );
    canvas.drawLine(
      Offset(s * 0.5, s * 0.585),
      Offset(s * 0.5, s * 0.665),
      paint,
    );

    // Bubble: filled dot (DotGrid-family dots are always filled).
    final double bx = s * (0.38 + 0.12 * motion);
    canvas.drawCircle(Offset(bx, s * 0.5), s * 0.075, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_SpiritLevelPainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Hanging balance: a short hanger, a tilted beam, and two pan dots on
/// short strings — the house weighing its choices.
///
/// Hover: the beam tilts, then levels — the scale finding its rest.
/// (Reads as a beam + suspended pans, never as Group-by's stem + rungs.)
class BalanceMark extends StatelessWidget {
  const BalanceMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; goes from 6° tilt at rest to dead level.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BalancePainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _BalancePainter extends CustomPainter {
  const _BalancePainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Paint fill = Paint()..color = ink;

    // Hanger: always vertical, meets the beam at its center.
    final Offset pivot = Offset(s * 0.5, s * 0.295);
    canvas.drawLine(Offset(s * 0.5, s * 0.12), pivot, paint);

    // Beam + strings + pans rotate as one piece around the pivot.
    // Rest: left pan lower (negative angle, y-down); hover: level.
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate((motion - 1) * 6 * math.pi / 180);
    canvas.drawLine(Offset(-s * 0.39, 0), Offset(s * 0.39, 0), paint);
    canvas.drawLine(Offset(-s * 0.39, 0), Offset(-s * 0.39, s * 0.09), paint);
    canvas.drawLine(Offset(s * 0.39, 0), Offset(s * 0.39, s * 0.09), paint);
    canvas.drawCircle(Offset(-s * 0.39, s * 0.15), s * 0.065, fill);
    canvas.drawCircle(Offset(s * 0.39, s * 0.15), s * 0.065, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BalancePainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Instrument dial face: a thin ring with index ticks at 12 / 3 / 6 / 9
/// touching it from inside, 12 o'clock carrying the long index. The
/// precision panel of the machine, not the control.
///
/// Hover: the index tick drops inward — the dial "taking a reading".
class DialFaceMark extends StatelessWidget {
  const DialFaceMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; lengthens the 12 o'clock index inward.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DialFacePainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _DialFacePainter extends CustomPainter {
  const _DialFacePainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);
    final double r = s * 0.34;

    canvas.drawCircle(c, r, paint);

    for (int i = 0; i < 4; i++) {
      final double a = -math.pi / 2 + i * math.pi / 2;
      final double inner = (i == 0) ? s * (0.16 - 0.08 * motion) : s * 0.24;
      canvas.drawLine(
        Offset(c.dx + inner * math.cos(a), c.dy + inner * math.sin(a)),
        Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DialFacePainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// DIP-switch bank: a hairline plate with three little faders at mixed
/// up / down positions. The settings plate inside the machine — AV-rack
/// hardware, not software furniture.
///
/// Hover: the right switch flips down.
class DipBankMark extends StatelessWidget {
  const DipBankMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; flips the third switch from up to down.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DipBankPainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _DipBankPainter extends CustomPainter {
  const _DipBankPainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Paint fill = Paint()..color = ink;

    final Rect body = Rect.fromLTWH(s * 0.07, s * 0.22, s * 0.86, s * 0.56);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(s * 0.06)),
      paint,
    );

    for (int i = 0; i < 3; i++) {
      final double x = s * (0.29 + 0.21 * i);
      canvas.drawLine(Offset(x, s * 0.36), Offset(x, s * 0.64), paint);
    }

    // Nubs: up · down · up (the third flips on hover).
    canvas.drawCircle(Offset(s * 0.29, s * 0.40), s * 0.055, fill);
    canvas.drawCircle(Offset(s * 0.50, s * 0.60), s * 0.055, fill);
    canvas.drawCircle(Offset(s * 0.71, s * (0.40 + 0.20 * motion)), s * 0.055,
        fill);
  }

  @override
  bool shouldRepaint(_DipBankPainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Selector ring: six dots on a dial — the current six-dot mark rearranged
/// into rotary-switch detent positions. Continuity with a new reading.
///
/// Hover: the ring steps 15° to the next detent.
class SelectorRingMark extends StatelessWidget {
  const SelectorRingMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Hover phase 0 → 1; steps the ring 15°.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter:
          _SelectorRingPainter(markInk(context), markStrokeFor(size), motion),
    );
  }
}

class _SelectorRingPainter extends CustomPainter {
  const _SelectorRingPainter(this.ink, this.stroke, this.motion);

  final Color ink;
  final double stroke;
  final double motion;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);
    final Paint fill = Paint()..color = ink;

    final double spin = motion * math.pi / 12;
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + i * math.pi / 3 + spin;
      canvas.drawCircle(
        Offset(
          c.dx + s * 0.36 * math.cos(a),
          c.dy + s * 0.36 * math.sin(a),
        ),
        s * 0.085,
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectorRingPainter old) =>
      old.ink != ink || old.stroke != stroke || old.motion != motion;
}

/// Cascade: the same six dots in a 3-2-1 pyramid — the house mark, evolved
/// rather than replaced. It keeps [DotGridIcon]'s dot size exactly.
///
/// No hover motion: this one is identity, not control — it just lights
/// with the shared recipe like [DotGridIcon] does today.
class CascadeMark extends StatelessWidget {
  const CascadeMark({super.key, this.size = 20, this.motion = 0});

  final double size;

  /// Ignored — kept so every candidate shares one signature.
  final double motion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CascadePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _CascadePainter extends CustomPainter {
  const _CascadePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint fill = Paint()..color = ink;

    const List<double> rows = <double>[0.26, 0.52, 0.78];
    for (int row = 0; row < rows.length; row++) {
      final int count = 3 - row;
      for (int i = 0; i < count; i++) {
        final double x = s * (0.5 + (i - (count - 1) / 2) * 0.28);
        canvas.drawCircle(Offset(x, s * rows[row]), s * 0.085, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_CascadePainter old) =>
      old.ink != ink || old.stroke != stroke;
}
