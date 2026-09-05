import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'salu_marks.dart' show markInk, markStrokeFor;

/// SALU's transport control marks (see follow.md · §1.6 and the outline §1).
///
/// Thin, monochrome, geometric — the same stroke language as the marks in
/// `salu_marks.dart` (shared `markStrokeFor` / `markInk` helpers), so
/// [SaluIconButton]'s hover recipe lights them up exactly like the rest
/// of the family.
///
/// The line's own legend:
///   · single chevron      `>`    — play
///   · two bars            `II`   — pause
///   · hollow square       `□`    — stop
///   · bar + double chevron `\|<<` / `>>\|` — skip ITEM (previous / next)
///   · double chevron only `<<` / `>>`      — skip TIME (seek back / fwd)
///   · speaker + arcs      `⊂))`  — sound (1 arc < 50 %, 2 arcs ≥ 50 %,
///                                  slash + no arcs when muted / 0 %)
///   · ¾ arc + arrowhead   `↻`    — Restart (Resume toast only)
///
/// Every mark reads its color from the ambient [IconTheme].

// ── The one chevron painter (>, <<, >>, |<<, >>|) ───────────────────────────

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({
    required this.ink,
    required this.stroke,
    required this.count,
    required this.bar,
    required this.left,
  });

  final Color ink;
  final double stroke;

  /// 1 = play chevron, 2 = double chevron (seek / skip).
  final int count;

  /// Whether a vertical bar rides at the pointing end (skip-item marks).
  final bool bar;

  /// Pointing direction: `false` = right (`>`, `>>`, `>>|`),
  /// `true` = left (`<<`, `|<<`).
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double s = size.width;

    // Right-pointing geometry, mirrored around the vertical center line
    // for the left-pointing marks.
    canvas.save();
    if (left) {
      canvas
        ..translate(s, 0)
        ..scale(-1, 1);
    }

    if (count == 1) {
      // Single play chevron: apex right of center (optically balanced).
      final double apex = s * 0.66;
      final double back = s * 0.34;
      final double dy = s * 0.28;
      final Path chevron = Path()
        ..moveTo(back, s * 0.5 - dy)
        ..lineTo(apex, s * 0.5)
        ..lineTo(back, s * 0.5 + dy);
      canvas.drawPath(chevron, paint);
    } else {
      // Double chevron. With a bar (skip item) the pair shifts left to
      // make room; without one (skip time) it centers.
      final double apex1 = bar ? s * 0.42 : s * 0.46;
      final double apex2 = bar ? s * 0.74 : s * 0.82;
      final double back1 = apex1 - s * 0.24;
      final double back2 = apex2 - s * 0.24;
      final double dy = s * 0.28;
      final Path pair = Path()
        ..moveTo(back1, s * 0.5 - dy)
        ..lineTo(apex1, s * 0.5)
        ..lineTo(back1, s * 0.5 + dy)
        ..moveTo(back2, s * 0.5 - dy)
        ..lineTo(apex2, s * 0.5)
        ..lineTo(back2, s * 0.5 + dy);
      canvas.drawPath(pair, paint);
    }

    if (bar) {
      // The item-skip bar at the pointing (right) edge.
      canvas.drawLine(
        Offset(s * 0.90, s * 0.24),
        Offset(s * 0.90, s * 0.76),
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.ink != ink ||
      old.stroke != stroke ||
      old.count != count ||
      old.bar != bar ||
      old.left != left;
}

// ── Pause: two short vertical rules ────────────────────────────────────────

class _PausePainter extends CustomPainter {
  const _PausePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final double s = size.width;
    canvas.drawLine(
      Offset(s * 0.36, s * 0.24),
      Offset(s * 0.36, s * 0.76),
      paint,
    );
    canvas.drawLine(
      Offset(s * 0.64, s * 0.24),
      Offset(s * 0.64, s * 0.76),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PausePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

// ── Stop: a hollow rounded square (stroke only) ────────────────────────────

class _StopPainter extends CustomPainter {
  const _StopPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final double s = size.width;
    final Rect square = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.5),
      width: s * 0.58,
      height: s * 0.58,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, Radius.circular(s * 0.13)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_StopPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

// ── Speaker: horn body + level arcs (slash when silent) ────────────────────

class _SpeakerPainter extends CustomPainter {
  const _SpeakerPainter({
    required this.ink,
    required this.stroke,
    required this.arcs,
    required this.muted,
  });

  final Color ink;
  final double stroke;

  /// 0 = no arcs (silent), 1 = low, 2 = loud.
  final int arcs;

  /// Muted: a slash crosses the horn, no arcs.
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;

    // Horn: small body + flare, one stroked outline.
    final Path horn = Path()
      ..moveTo(s * 0.12, s * 0.40)
      ..lineTo(s * 0.28, s * 0.40)
      ..lineTo(s * 0.44, s * 0.23)
      ..lineTo(s * 0.44, s * 0.77)
      ..lineTo(s * 0.28, s * 0.60)
      ..lineTo(s * 0.12, s * 0.60)
      ..close();
    canvas.drawPath(horn, paint);

    if (muted) {
      // Slash across the horn's mouth — the universal "silent" cross.
      canvas.drawLine(
        Offset(s * 0.56, s * 0.30),
        Offset(s * 0.88, s * 0.70),
        paint,
      );
      return;
    }

    // Level arcs: 1 arc below 50 %, 2 arcs at 50 % and up.
    final Offset c = Offset(s * 0.50, s * 0.5);
    for (int i = 0; i < arcs; i++) {
      final double r = s * (0.20 + 0.16 * i);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 3.1,
        2 * math.pi / 3.1,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) =>
      old.ink != ink ||
      old.stroke != stroke ||
      old.arcs != arcs ||
      old.muted != muted;
}

// ── Restart: a ¾ arc with a small arrowhead (toast only) ───────────────────

class _RestartPainter extends CustomPainter {
  const _RestartPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);
    final double r = s * 0.32;

    // ¾ arc: starts low-left, sweeps clockwise, ends pointing right-down.
    const double start = 3 * math.pi / 4;
    const double sweep = 3 * math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      paint,
    );

    // Arrowhead at the arc's end (angle π/4), pointing along the sweep.
    const double endAngle = start + sweep;
    final Offset tip = Offset(
      c.dx + r * math.cos(endAngle),
      c.dy + r * math.sin(endAngle),
    );
    final Offset tangent = Offset(
      -math.sin(endAngle),
      math.cos(endAngle),
    );
    final Offset normal = Offset(tangent.dy, -tangent.dx) * (s * 0.11);
    final Path head = Path()
      ..moveTo(tip.dx - tangent.dx * s * 0.16 + normal.dx,
          tip.dy - tangent.dy * s * 0.16 + normal.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - tangent.dx * s * 0.16 - normal.dx,
          tip.dy - tangent.dy * s * 0.16 - normal.dy);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_RestartPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

// ── Public mark widgets ────────────────────────────────────────────────────

/// Play — a single right-pointing chevron.
class PlayChevronMark extends StatelessWidget {
  const PlayChevronMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        count: 1,
        bar: false,
        left: false,
      ),
    );
  }
}

/// Pause — two short vertical rules.
class PauseMark extends StatelessWidget {
  const PauseMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PausePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

/// Stop — a hollow rounded square (a closed square reads heavier, so its
/// optical size is smaller than its siblings').
class StopMark extends StatelessWidget {
  const StopMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StopPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

/// Previous item — bar + double chevron pointing left.
class PreviousMark extends StatelessWidget {
  const PreviousMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        count: 2,
        bar: true,
        left: true,
      ),
    );
  }
}

/// Next item — double chevron + bar pointing right.
class NextMark extends StatelessWidget {
  const NextMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        count: 2,
        bar: true,
        left: false,
      ),
    );
  }
}

/// Seek backward in time — double chevron only, pointing left.
class SeekBackMark extends StatelessWidget {
  const SeekBackMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        count: 2,
        bar: false,
        left: true,
      ),
    );
  }
}

/// Seek forward in time — double chevron only, pointing right.
class SeekForwardMark extends StatelessWidget {
  const SeekForwardMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChevronPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        count: 2,
        bar: false,
        left: false,
      ),
    );
  }
}

/// Sound — a tiny speaker whose arcs follow the level:
/// slash + no arcs when muted or 0 %, one arc below 50 %, two at 50 %+.
class SpeakerMark extends StatelessWidget {
  const SpeakerMark({super.key, this.size = 20, this.level = 100, this.muted = false});

  final double size;

  /// Current volume 0–100 (ignored while [muted]).
  final double level;

  final bool muted;

  @override
  Widget build(BuildContext context) {
    final bool silent = muted || level < 1;
    final int arcs = silent ? 0 : (level < 50 ? 1 : 2);
    return CustomPaint(
      size: Size.square(size),
      painter: _SpeakerPainter(
        ink: markInk(context),
        stroke: markStrokeFor(size),
        arcs: arcs,
        muted: silent,
      ),
    );
  }
}

/// Restart — a ¾ arc with an arrowhead. Lives only inside the Resume toast.
class RestartMark extends StatelessWidget {
  const RestartMark({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RestartPainter(markInk(context), markStrokeFor(size)),
    );
  }
}
