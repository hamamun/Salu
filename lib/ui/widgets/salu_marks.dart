import 'dart:math' as math;

import 'package:flutter/material.dart';

/// SALU's custom icon family (see follow.md · hard rule 6).
///
/// Thin, monochrome, geometric marks — drawn by hand like the dot-grid
/// settings mark, never taken from a stock icon set. Every mark reads its
/// color from the ambient [IconTheme], so [SaluIconButton]'s hover recipe
/// (gray → white glide) lights them up automatically.
///
/// Family so far:
///   · six dots       — Settings            (dot_grid_icon.dart)
///   · thin plus      — Open media          [PlusMark] (rotates 45° to ×)
///   · film frame     — Open File           [FilmFrameMark]
///   · stacked frames — Open Folder         [StackedFramesMark]
///   · link           — Open URL            [LinkMark]
///   · solid triangle — Play                [PlayMark]
///   · triangle + tag — Play & Save         [PlaySaveMark]
///   · pencil         — Edit (inline)       [PencilMark]
///   · bin            — Delete              [TrashMark]
///   · tick           — Done (inline edit)  [TickMark]
///   · three rules    — Drag handle         [GripMark]
///   · ragged rules   — Playlist (Now Row)  [NowRowMark]
///   · ¾ arc + arrow  — Repeat              [RepeatMark] (arc: RestartMark's)
///   · crossing rules — Shuffle             [ShuffleMark]
///   · circle + stem  — Search (magnifier)  [MagnifierMark]
///   · stem + rungs   — Group by            [GroupByMark] (stable — never morphs)
///   · three rules    — Flat grouping       [FlatMark]
///   · brackets       — Category grouping   [CategoryMark]
///   · speech bubble  — Language grouping   [LanguageMark]
///   · globe          — Country grouping    [CountryMark]
///   · bookmark       — Favourite           [BookmarkMark] (outline / [filled])
///   · chevron        — Reveal / twist      [RevealChevronMark] · [GroupTwistMark]

/// Shared stroke weight so the whole family reads as one hand (public so
/// the transport marks share it — see transport_marks.dart).
double markStrokeFor(double size) => (size * 0.085).clamp(1.4, 2.2).toDouble();

Color markInk(BuildContext context) =>
    IconTheme.of(context).color ?? Colors.white;

/// The Open mark: a thin plus. The parent rotates it 45° into an × while
/// the open pill is showing — one mark, two states.
class PlusMark extends StatelessWidget {
  const PlusMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PlusPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Offset c = size.center(Offset.zero);
    final double r = size.width * 0.42;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Open File — a single thin film frame: a rounded rectangle with two
/// sprocket notches on each vertical edge. Says "media", not "document".
class FilmFrameMark extends StatelessWidget {
  const FilmFrameMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FilmFramePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _FilmFramePainter extends CustomPainter {
  const _FilmFramePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Rect frame = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.18,
      size.width * 0.76,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(size.width * 0.12)),
      paint,
    );

    // Two sprocket ticks per side, just inside the vertical edges.
    final double tick = size.width * 0.10;
    for (final double fy in <double>[0.40, 0.60]) {
      final double y = size.height * fy;
      canvas.drawLine(Offset(frame.left, y),
          Offset(frame.left + tick, y), paint);
      canvas.drawLine(Offset(frame.right - tick, y),
          Offset(frame.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_FilmFramePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Open Folder — two thin frames, slightly offset: a collection of media,
/// without ever drawing a Windows folder.
class StackedFramesMark extends StatelessWidget {
  const StackedFramesMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StackedFramesPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _StackedFramesPainter extends CustomPainter {
  const _StackedFramesPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint front = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Paint back = Paint()
      ..color = ink.withAlpha(140) // ~55% — the back frame sits quieter.
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Radius r = Radius.circular(size.width * 0.10);

    // Back frame — up-right, quieter.
    final Rect backRect = Rect.fromLTWH(
      size.width * 0.26,
      size.height * 0.14,
      size.width * 0.60,
      size.height * 0.50,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(backRect, r), back);

    // Front frame — down-left, full ink.
    final Rect frontRect = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.34,
      size.width * 0.60,
      size.height * 0.50,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(frontRect, r), front);
  }

  @override
  bool shouldRepaint(_StackedFramesPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Open URL — a thin two-ring chain link, tilted 45°. Deliberately a link
/// and not a globe: this control plays direct streams, it does not browse.
class LinkMark extends StatelessWidget {
  const LinkMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LinkPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _LinkPainter extends CustomPainter {
  const _LinkPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Offset c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.7853981633974483); // −45°

    final double w = size.width * 0.46; // Capsule width.
    final double h = size.height * 0.30; // Capsule height.
    final double overlap = size.width * 0.10;
    final Radius r = Radius.circular(h / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(-w / 2 + overlap, 0), width: w, height: h),
        r,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w / 2 - overlap, 0), width: w, height: h),
        r,
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Play — a right-pointing triangle, filled.
///
/// The Open-URL window's primary action. follow.md forbids drawing any
/// shape behind an icon, so emphasis can only live in the mark itself:
/// Play is the solid one, [PlaySaveMark] beside it stays hollow. Corners
/// are softened with a round-joined stroke of the family weight instead of
/// a hard geometric point.
class PlayMark extends StatelessWidget {
  const PlayMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PlayPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _PlayPainter extends CustomPainter {
  const _PlayPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Path triangle = Path()
      ..moveTo(size.width * 0.28, size.height * 0.18)
      ..lineTo(size.width * 0.82, size.height * 0.50)
      ..lineTo(size.width * 0.28, size.height * 0.82)
      ..close();

    canvas.drawPath(
      triangle,
      Paint()
        ..color = ink
        ..style = PaintingStyle.fill,
    );
    // Same path stroked with round joins — rounds the three points.
    canvas.drawPath(
      triangle,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PlayPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Play & Save — the same triangle, hollow, with a small tag (bookmark)
/// tucked at its lower right: play it AND keep it in the saved seven.
/// Hollow on purpose — the solid [PlayMark] next to it stays the primary.
class PlaySaveMark extends StatelessWidget {
  const PlaySaveMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PlaySavePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _PlaySavePainter extends CustomPainter {
  const _PlaySavePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // The triangle, pushed up-left to make room for the tag.
    final Path triangle = Path()
      ..moveTo(size.width * 0.14, size.height * 0.10)
      ..lineTo(size.width * 0.62, size.height * 0.38)
      ..lineTo(size.width * 0.14, size.height * 0.66)
      ..close();
    canvas.drawPath(triangle, paint);

    // The tag: a small bookmark with a notched foot, lower right.
    final Path tag = Path()
      ..moveTo(size.width * 0.58, size.height * 0.52)
      ..lineTo(size.width * 0.58, size.height * 0.92)
      ..lineTo(size.width * 0.745, size.height * 0.775)
      ..lineTo(size.width * 0.91, size.height * 0.92)
      ..lineTo(size.width * 0.91, size.height * 0.52)
      ..close();
    canvas.drawPath(tag, paint);
  }

  @override
  bool shouldRepaint(_PlaySavePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Edit — a thin pencil on the family's 45° diagonal (the same tilt as
/// [LinkMark]), body plus tip, nothing else.
class PencilMark extends StatelessWidget {
  const PencilMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PencilPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _PencilPainter extends CustomPainter {
  const _PencilPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final Offset c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.7853981633974483); // +45° — the pencil points down-left.

    final double s = size.width;
    final double halfW = s * 0.13;

    // Body — a slim rounded barrel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-halfW, -s * 0.38, halfW, s * 0.14),
        Radius.circular(s * 0.05),
      ),
      paint,
    );

    // Tip — a short wedge below the barrel.
    final Path tip = Path()
      ..moveTo(-halfW, s * 0.14)
      ..lineTo(0, s * 0.42)
      ..lineTo(halfW, s * 0.14);
    canvas.drawPath(tip, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PencilPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Delete — a thin bin: lid rule, small handle, tapered body. Geometric,
/// never the stock filled trash can.
class TrashMark extends StatelessWidget {
  const TrashMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TrashPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _TrashPainter extends CustomPainter {
  const _TrashPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final double w = size.width;
    final double h = size.height;

    // Lid.
    canvas.drawLine(
        Offset(w * 0.14, h * 0.28), Offset(w * 0.86, h * 0.28), paint);

    // Handle.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h * 0.28)
        ..lineTo(w * 0.38, h * 0.15)
        ..lineTo(w * 0.62, h * 0.15)
        ..lineTo(w * 0.62, h * 0.28),
      paint,
    );

    // Tapered body.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.23, h * 0.28)
        ..lineTo(w * 0.29, h * 0.85)
        ..lineTo(w * 0.71, h * 0.85)
        ..lineTo(w * 0.77, h * 0.28),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TrashPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Done — a plain tick, used to commit the inline row editor.
class TickMark extends StatelessWidget {
  const TickMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TickPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.18, size.height * 0.52)
        ..lineTo(size.width * 0.42, size.height * 0.76)
        ..lineTo(size.width * 0.82, size.height * 0.26),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Drag handle — three short rules (≡). Deliberately NOT a dot grid: six
/// dots already mean Settings in this family.
class GripMark extends StatelessWidget {
  const GripMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GripPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _GripPainter extends CustomPainter {
  const _GripPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (final double fy in <double>[0.30, 0.50, 0.70]) {
      final double y = size.height * fy;
      canvas.drawLine(
          Offset(size.width * 0.24, y), Offset(size.width * 0.76, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Playlist — three ragged rules; the row that is playing carries the
/// family's solid play chevron at its head (playlist_imp.md §2).
///
/// The chevron's row reports the queue's position in thirds: with the
/// queue empty ([now] = −1) the three rules stay quiet and no chevron is
/// drawn. Raggedness is load-bearing — three EQUAL rules would read as
/// the ≡ drag handle (hard rule 6), so the ends must stay 0.86 / 0.68 /
/// 0.78. Never used near the transport cluster (§1.2 R4).
class NowRowMark extends StatelessWidget {
  const NowRowMark({super.key, this.size = 20, this.now = -1});

  final double size;

  /// 0…2 = the rule (third) that carries the chevron; −1 = nothing queued.
  final int now;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _NowRowPainter(markInk(context), markStrokeFor(size), now),
    );
  }
}

class _NowRowPainter extends CustomPainter {
  const _NowRowPainter(this.ink, this.stroke, this.now);

  final Color ink;
  final double stroke;
  final int now;

  static const List<double> _ys = <double>[0.28, 0.52, 0.76];
  static const List<double> _ends = <double>[0.86, 0.68, 0.78];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint quiet = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Paint line = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Paint fill = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;
    final Paint round = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _ys.length; i++) {
      if (i == now) continue; // the playing row is drawn last, full ink
      final double y = h * _ys[i];
      canvas.drawLine(Offset(w * 0.16, y), Offset(w * _ends[i], y), quiet);
    }
    if (now < 0) return; // empty queue — no chevron, nothing full-ink

    final double y = h * _ys[now];
    final Path head = Path()
      ..moveTo(w * 0.16, y - h * 0.08)
      ..lineTo(w * 0.30, y)
      ..lineTo(w * 0.16, y + h * 0.08)
      ..close();
    canvas.drawPath(head, fill);
    canvas.drawPath(head, round); // softens the points, as PlayMark does
    canvas.drawLine(Offset(w * 0.38, y), Offset(w * _ends[now], y), line);
  }

  @override
  bool shouldRepaint(_NowRowPainter old) =>
      old.ink != ink || old.stroke != stroke || old.now != now;
}

/// Repeat — the family's ¾-arc + arrowhead (geometry identical to the
/// transport Restart mark), reporting the repeat state by modification:
/// quiet (off, [quiet] = true) · full (all) · full + a solid bead at the
/// arc's centre (one). Never a numeral (rules 1 & 6).
class RepeatMark extends StatelessWidget {
  const RepeatMark({super.key, this.size = 18, this.quiet = false, this.bead = false});

  final double size;

  /// Off state — the arc sits at the quiet 55 % ink (still hoverable).
  final bool quiet;

  /// Repeat-one state — a solid bead at the arc's centre.
  final bool bead;

  @override
  Widget build(BuildContext context) {
    final Color ink = markInk(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _RepeatPainter(
        quiet ? ink.withAlpha(140) : ink,
        markStrokeFor(size),
        bead ? ink : null,
      ),
    );
  }
}

class _RepeatPainter extends CustomPainter {
  const _RepeatPainter(this.ink, this.stroke, this.beadInk);

  final Color ink;
  final double stroke;

  /// Full ink when the bead is shown, `null` without one.
  final Color? beadInk;

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

    // ¾ arc: starts low-left, sweeps clockwise, ends pointing right-down
    // (the exact Restart geometry).
    const double start = 3 * math.pi / 4;
    const double sweep = 3 * math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      paint,
    );

    // Arrowhead at the arc's end, pointing along the sweep.
    const double endAngle = start + sweep;
    final Offset tip = Offset(
      c.dx + r * math.cos(endAngle),
      c.dy + r * math.sin(endAngle),
    );
    final Offset tangent = Offset(-math.sin(endAngle), math.cos(endAngle));
    final Offset normal = Offset(tangent.dy, -tangent.dx) * (s * 0.11);
    final Path head = Path()
      ..moveTo(tip.dx - tangent.dx * s * 0.16 + normal.dx,
          tip.dy - tangent.dy * s * 0.16 + normal.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - tangent.dx * s * 0.16 - normal.dx,
          tip.dy - tangent.dy * s * 0.16 - normal.dy);
    canvas.drawPath(head, paint);

    // Repeat-one bead at the arc's centre.
    final Color? bead = beadInk;
    if (bead != null) {
      canvas.drawCircle(
        c,
        s * 0.09,
        Paint()
          ..color = bead
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RepeatPainter old) =>
      old.ink != ink || old.stroke != stroke || old.beadInk != beadInk;
}

/// Shuffle — two crossing rules with arrowheads at their right ends.
/// Must cross and carry heads so it can never be read as the transport's
/// `<<` / `>>`. While suspended (repeat-one active) [quiet] drops the
/// whole mark to the quiet 55 % ink and the header loses its glow.
class ShuffleMark extends StatelessWidget {
  const ShuffleMark({super.key, this.size = 18, this.quiet = false});

  final double size;

  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final Color ink = markInk(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _ShufflePainter(
        quiet ? ink.withAlpha(140) : ink,
        markStrokeFor(size),
      ),
    );
  }
}

class _ShufflePainter extends CustomPainter {
  const _ShufflePainter(this.ink, this.stroke);

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

    // Two rules that cross near the middle: the upper arm falls to the
    // right, the lower arm rises to the right.
    final Offset topStart = Offset(s * 0.16, s * 0.30);
    final Offset topEnd = Offset(s * 0.62, s * 0.58);
    final Offset bottomStart = Offset(s * 0.16, s * 0.70);
    final Offset bottomEnd = Offset(s * 0.62, s * 0.42);
    canvas.drawLine(topStart, topEnd, paint);
    canvas.drawLine(bottomStart, bottomEnd, paint);

    // Arrowhead at each right end, along its rule's direction.
    _drawHead(canvas, paint, s, topEnd, (topEnd - topStart) / (topEnd - topStart).distance);
    _drawHead(canvas, paint, s, bottomEnd,
        (bottomEnd - bottomStart) / (bottomEnd - bottomStart).distance);
  }

  static void _drawHead(
      Canvas canvas, Paint paint, double s, Offset tip, Offset unit) {
    // A chevron-V: two strokes from the tip back along the rule, splayed
    // by halfWidth on each side.
    final Offset back = tip - unit * (s * 0.18);
    final Offset n = Offset(unit.dy, -unit.dx) * (s * 0.075);
    final Path head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + n.dx, back.dy + n.dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx - n.dx, back.dy - n.dy);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_ShufflePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Search — a thin magnifier: a small circle with a short handle falling
/// from its lower-right rim. The header field's own wordless label (no
/// placeholder text — rule 1); the same mark also renders the panel's
/// no-match state alone at a larger size.
class MagnifierMark extends StatelessWidget {
  const MagnifierMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MagnifierPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _MagnifierPainter extends CustomPainter {
  const _MagnifierPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;

    // Lens: a ring centred slightly up-left of the box's middle.
    final Offset c = Offset(s * 0.40, s * 0.40);
    final double r = s * 0.24;
    canvas.drawCircle(c, r, paint);

    // Handle: from the ring's lower-right rim down toward the box corner.
    const double a = math.pi / 4; // 45°, down-right
    canvas.drawLine(
      Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)),
      Offset(c.dx + (r + s * 0.20) * math.cos(a),
          c.dy + (r + s * 0.20) * math.sin(a)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MagnifierPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Group by — the channel header's slot-1 mark (playlist_imp.md §10.2).
///
/// One STABLE mark plus a four-option pill below it: the mark never
/// morphs into four different glyphs (the family's grammar is *one
/// mark, modified*). A stem with a bead and two pairs of rungs. While a
/// search flattens the list [quiet] drops it to the quiet ink — the
/// grouping is suspended, not forgotten (§10.3).
class GroupByMark extends StatelessWidget {
  const GroupByMark({super.key, this.size = 18, this.quiet = false});

  final double size;

  /// Suspended state — the mark sits at the quiet ink (still hoverable).
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final Color ink = markInk(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _GroupByPainter(
        quiet ? ink.withAlpha(140) : ink,
        markStrokeFor(size),
      ),
    );
  }
}

class _GroupByPainter extends CustomPainter {
  const _GroupByPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    Offset p(double x, double y) => Offset(s * x / 24, s * y / 24);
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Stem + rungs.
    canvas.drawLine(p(5, 4), p(5, 18), paint);
    canvas.drawLine(p(5, 7), p(10, 7), paint);
    canvas.drawLine(p(5, 17), p(10, 17), paint);
    canvas.drawLine(p(13, 7), p(19, 7), paint);
    canvas.drawLine(p(13, 17), p(17, 17), paint);
    // Bead crowning the stem.
    canvas.drawCircle(
      p(5, 4),
      s * 1.4 / 24,
      Paint()
        ..color = ink
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_GroupByPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Flat — the pill's "no grouping" option: three plain rules.
class FlatMark extends StatelessWidget {
  const FlatMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FlatPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _FlatPainter extends CustomPainter {
  const _FlatPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    Offset p(double x, double y) => Offset(s * x / 24, s * y / 24);
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(4, 6), p(20, 6), paint);
    canvas.drawLine(p(4, 12), p(15, 12), paint);
    canvas.drawLine(p(4, 18), p(18, 18), paint);
  }

  @override
  bool shouldRepaint(_FlatPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Category — the pill's category option: two brackets joined by a rung.
class CategoryMark extends StatelessWidget {
  const CategoryMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CategoryPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _CategoryPainter extends CustomPainter {
  const _CategoryPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    Offset p(double x, double y) => Offset(s * x / 24, s * y / 24);
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(p(4, 5), p(10, 5), paint);
    canvas.drawLine(p(4, 19), p(10, 19), paint);
    canvas.drawLine(p(7, 5), p(7, 19), paint);
    canvas.drawLine(p(7, 12), p(15, 12), paint);
    canvas.drawLine(p(15, 7), p(20, 7), paint);
    canvas.drawLine(p(15, 17), p(20, 17), paint);
    canvas.drawLine(p(15, 7), p(15, 17), paint);
  }

  @override
  bool shouldRepaint(_CategoryPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Language — the pill's language option: a speech bubble with two
/// quiet rules inside.
class LanguageMark extends StatelessWidget {
  const LanguageMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LanguagePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _LanguagePainter extends CustomPainter {
  const _LanguagePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    Offset p(double x, double y) => Offset(s * x / 24, s * y / 24);
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // Bubble: a rounded rect with a tail falling from its lower edge.
    final Path bubble = Path()
      ..moveTo(s * 5 / 24, s * 5 / 24)
      ..lineTo(s * 19 / 24, s * 5 / 24)
      ..arcToPoint(p(21, 7), radius: Radius.circular(s * 2 / 24))
      ..lineTo(s * 21 / 24, s * 14 / 24)
      ..arcToPoint(p(19, 16), radius: Radius.circular(s * 2 / 24))
      ..lineTo(s * 11 / 24, s * 16 / 24)
      ..lineTo(s * 6 / 24, s * 20 / 24)
      ..lineTo(s * 6 / 24, s * 16 / 24)
      ..lineTo(s * 5 / 24, s * 16 / 24)
      ..arcToPoint(p(3, 14), radius: Radius.circular(s * 2 / 24))
      ..lineTo(s * 3 / 24, s * 7 / 24)
      ..arcToPoint(p(5, 5), radius: Radius.circular(s * 2 / 24))
      ..close();
    canvas.drawPath(bubble, paint);
    // Two quiet rules inside.
    final Paint quiet = Paint()
      ..color = ink.withAlpha(153) // ~60% — the bubble's own text lines.
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(7, 9), p(17, 9), quiet);
    canvas.drawLine(p(7, 13), p(13, 13), quiet);
  }

  @override
  bool shouldRepaint(_LanguagePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Country — the pill's country option: a globe (ring + meridian + equator).
class CountryMark extends StatelessWidget {
  const CountryMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CountryPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _CountryPainter extends CustomPainter {
  const _CountryPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(s * 12 / 24, s * 12 / 24);
    canvas.drawCircle(c, s * 9 / 24, paint);
    canvas.drawOval(
      Rect.fromCenter(
        center: c,
        width: s * 8 / 24,
        height: s * 18 / 24,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(s * 3 / 24, s * 12 / 24),
      Offset(s * 21 / 24, s * 12 / 24),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CountryPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Favourite — the bookmark, not a star (playlist_imp.md §10.3). A
/// five-point star at 15 px turns to mush; a bookmark is two verticals
/// and a notch. [filled] + always visible = saved; outline + hover-only
/// = one tap away from saved.
class BookmarkMark extends StatelessWidget {
  const BookmarkMark({super.key, this.size = 15, this.filled = false});

  final double size;

  /// Saved state — solid, always visible.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BookmarkPainter(
        markInk(context),
        markStrokeFor(size),
        filled,
      ),
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  const _BookmarkPainter(this.ink, this.stroke, this.filled);

  final Color ink;
  final double stroke;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Path tag = Path()
      ..moveTo(s * 7 / 24, s * 4 / 24)
      ..lineTo(s * 17 / 24, s * 4 / 24)
      ..lineTo(s * 17 / 24, s * 20 / 24)
      ..lineTo(s * 12 / 24, s * 16.5 / 24)
      ..lineTo(s * 7 / 24, s * 20 / 24)
      ..close();
    if (filled) {
      canvas.drawPath(
        tag,
        Paint()
          ..color = ink
          ..style = PaintingStyle.fill,
      );
    }
    // Same path stroked with round joins — rounds the corners, as
    // PlayMark does (and draws the outline when not filled).
    canvas.drawPath(
      tag,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BookmarkPainter old) =>
      old.ink != ink || old.stroke != stroke || old.filled != filled;
}

/// Reveal chevron — the list-edge mark pointing at the playing channel
/// hiding above ([up]) or below it (playlist_imp.md §10.6).
class RevealChevronMark extends StatelessWidget {
  const RevealChevronMark({super.key, this.size = 15, this.up = true});

  final double size;

  /// Points up (the channel hides above) or down (it hides below).
  final bool up;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RevealChevronPainter(markInk(context), markStrokeFor(size), up),
    );
  }
}

class _RevealChevronPainter extends CustomPainter {
  const _RevealChevronPainter(this.ink, this.stroke, this.up);

  final Color ink;
  final double stroke;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final Path chevron = up
        ? (Path()
          ..moveTo(s * 7 / 24, s * 15 / 24)
          ..lineTo(s * 12 / 24, s * 10 / 24)
          ..lineTo(s * 17 / 24, s * 15 / 24))
        : (Path()
          ..moveTo(s * 7 / 24, s * 9 / 24)
          ..lineTo(s * 12 / 24, s * 14 / 24)
          ..lineTo(s * 17 / 24, s * 9 / 24));
    canvas.drawPath(chevron, paint);
  }

  @override
  bool shouldRepaint(_RevealChevronPainter old) =>
      old.ink != ink || old.stroke != stroke || old.up != up;
}

/// Group twist — the accordion head's chevron: right when collapsed,
/// rotating 90° down as the group opens (160 ms, the preview's motion).
class GroupTwistMark extends StatelessWidget {
  const GroupTwistMark({super.key, this.size = 14, this.expanded = false});

  final double size;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.25 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: CustomPaint(
        size: Size.square(size),
        painter:
            _GroupTwistPainter(markInk(context), markStrokeFor(size)),
      ),
    );
  }
}

class _GroupTwistPainter extends CustomPainter {
  const _GroupTwistPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(s * 9 / 24, s * 7 / 24)
        ..lineTo(s * 14 / 24, s * 12 / 24)
        ..lineTo(s * 9 / 24, s * 17 / 24),
      Paint()
        ..color = ink
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_GroupTwistPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

// ── Captions family (cc.md §6 · D14) ────────────────────────────────────

/// CC — the Fetch button's mark (cc.md §6.1 / D14): a thin rounded frame
/// with two text rules inside, drawn in the family's stroke. Deliberately
/// NOT the channel line's speech bubble (LanguageMark) — a caption frame,
/// customised per follow.md rule 6.
class CcMark extends StatelessWidget {
  const CcMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.85),
      painter: _CcPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _CcPainter extends CustomPainter {
  const _CcPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // Thin rounded frame (the mock: rx 2.6 of a 20×17 box).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.06, h * 0.07, w * 0.94, h * 0.93),
        Radius.circular(w * 0.13),
      ),
      paint,
    );
    // Two caption rules: full-width first, shortened second.
    canvas.drawLine(Offset(w * 0.27, h * 0.36), Offset(w * 0.74, h * 0.36), paint);
    canvas.drawLine(Offset(w * 0.27, h * 0.63), Offset(w * 0.55, h * 0.63), paint);
  }

  @override
  bool shouldRepaint(_CcPainter old) => old.ink != ink || old.stroke != stroke;
}

/// Load subtitle — the panel's Load mark (§6.4): the mock's 19×16 frame
/// with two interior dividers (a subtitle file's column look), same
/// stroke as the family.
class LoadSubMark extends StatelessWidget {
  const LoadSubMark({super.key, this.size = 19});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 16 / 19),
      painter: _LoadSubPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _LoadSubPainter extends CustomPainter {
  const _LoadSubPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final Paint quiet = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.06, h * 0.075, w * 0.94, h * 0.925),
        Radius.circular(w * 0.126),
      ),
      paint,
    );
    // Interior dividers at ~35% and ~65%, quieter than the frame.
    canvas.drawLine(Offset(w * 0.35, h * 0.10), Offset(w * 0.35, h * 0.90), quiet);
    canvas.drawLine(Offset(w * 0.65, h * 0.10), Offset(w * 0.65, h * 0.90), quiet);
  }

  @override
  bool shouldRepaint(_LoadSubPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Save — the search window's tray mark (§6.5): arrow down into an open
/// tray, the mock's exact silhouette.
class SaveMark extends StatelessWidget {
  const SaveMark({super.key, this.size = 19});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 17 / 19),
      painter: _SavePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _SavePainter extends CustomPainter {
  const _SavePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // Arrow: shaft + chevron into the tray.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.09)
        ..lineTo(w * 0.5, h * 0.61)
        ..moveTo(w * 0.295, h * 0.39)
        ..lineTo(w * 0.5, h * 0.62)
        ..lineTo(w * 0.705, h * 0.39),
      paint,
    );
    // Open tray below.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.095, h * 0.71)
        ..lineTo(w * 0.095, h * 0.85)
        ..quadraticBezierTo(w * 0.095, h * 0.93, w * 0.17, h * 0.93)
        ..lineTo(w * 0.83, h * 0.93)
        ..quadraticBezierTo(w * 0.905, h * 0.93, w * 0.905, h * 0.85)
        ..lineTo(w * 0.905, h * 0.71),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SavePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Save & Load — the search window's tray + play mark (§6.5): the Save
/// tray on the left, a filled play flag at its right edge (the mock's
/// exact composition), so the two actions sit one family apart.
class SaveLoadMark extends StatelessWidget {
  const SaveLoadMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 17 / 24),
      painter: _SaveLoadPainter(markInk(context), markStrokeFor(size * 19 / 24)),
    );
  }
}

class _SaveLoadPainter extends CustomPainter {
  const _SaveLoadPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // The Save tray, compressed left (~55 % width).
    final double sw = w * 0.55;
    canvas.drawPath(
      Path()
        ..moveTo(sw * 0.5, h * 0.09)
        ..lineTo(sw * 0.5, h * 0.61)
        ..moveTo(sw * 0.1, h * 0.39)
        ..lineTo(sw * 0.5, h * 0.62)
        ..lineTo(sw * 0.9, h * 0.39),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(sw * 0.02, h * 0.71)
        ..lineTo(sw * 0.02, h * 0.85)
        ..quadraticBezierTo(sw * 0.02, h * 0.93, sw * 0.16, h * 0.93)
        ..lineTo(w * 0.5, h * 0.93),
      paint,
    );
    // The play flag — filled like PlayMark, at the tray's right edge.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.66, h * 0.26)
        ..lineTo(w * 0.9, h * 0.49)
        ..lineTo(w * 0.66, h * 0.72)
        ..close(),
      Paint()
        ..color = ink
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_SaveLoadPainter old) =>
      old.ink != ink || old.stroke != stroke;
}
