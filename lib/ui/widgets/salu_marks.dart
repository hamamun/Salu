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
///   · now row        — Playlist            [NowRowMark] (three ragged
///                      rules; the playing third carries a solid chevron)
///   · loop arc       — Repeat              [RepeatMark] (quiet = off,
///                      bead at the centre = repeat one)
///   · crossing rules — Shuffle             [ShuffleMark]
///   · magnifier      — Search / filter     [SearchMark]
///   · ×              — Clear the text      [CrossMark]
///   · window + arrow — Undock / Dock back  [UndockMark] / [DockMark]
///   · group          — Group by (stable)   [GroupByMark]; the four modes
///                      ride its pill       [GroupModeMark]
///   · bookmark       — Favourite           [BookmarkMark] (filled = on)

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

// ═════════════════════════════════════════════════════════════════════════
// Playlist & panel marks (playlist_imp.md §2, §4.4, §10)
// ═════════════════════════════════════════════════════════════════════════

/// Playlist — three ragged rules; the row that is playing carries the
/// family's solid chevron at its head. The chevron's row reports position
/// in thirds (playlist_imp.md §2). Never used near the transport cluster.
class NowRowMark extends StatelessWidget {
  const NowRowMark({super.key, this.size = 20, this.now = 0});

  final double size;

  /// 0…2 = the row carrying the chevron; `-1` = nothing queued.
  final int now;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _NowRowPainter(markInk(context), markStrokeFor(size), now),
      );
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

/// Repeat — the family's ¾ arc + arrowhead (RestartMark's geometry).
/// `quiet` = off (55 % ink, still hoverable) · full = all · [bead] = one:
/// a solid bead at the arc's centre — never a numeral (rules 1 & 6).
class RepeatMark extends StatelessWidget {
  const RepeatMark({
    super.key,
    this.size = 18,
    this.quiet = false,
    this.bead = false,
  });

  final double size;

  /// Off state: the arc drops to the quiet ink.
  final bool quiet;

  /// Repeat-one: a solid bead at the arc's centre.
  final bool bead;

  @override
  Widget build(BuildContext context) {
    final Color ink = markInk(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _RepeatPainter(
        quiet ? ink.withAlpha(140) : ink,
        ink,
        markStrokeFor(size),
        bead,
      ),
    );
  }
}

class _RepeatPainter extends CustomPainter {
  const _RepeatPainter(this.ink, this.beadInk, this.stroke, this.bead);

  final Color ink;
  final Color beadInk;
  final double stroke;
  final bool bead;

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

    // Arrowhead at the arc's end, pointing along the sweep.
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

    if (bead) {
      // Repeat one: a solid bead at the arc's centre.
      canvas.drawCircle(
        c,
        s * 0.08,
        Paint()
          ..color = beadInk
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RepeatPainter old) =>
      old.ink != ink ||
      old.beadInk != beadInk ||
      old.stroke != stroke ||
      old.bead != bead;
}

/// Shuffle — two crossing rules with arrowheads at their right ends.
/// Must cross and carry heads so it can never be read as the transport's
/// `<<` / `>>`. [quiet] = suspended by repeat one (a kept setting whose
/// effect is paused — 55 % ink, no glow, nothing is silently reset).
class ShuffleMark extends StatelessWidget {
  const ShuffleMark({super.key, this.size = 18, this.quiet = false});

  final double size;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    Color ink = markInk(context);
    if (quiet) ink = ink.withAlpha(140);
    return CustomPaint(
      size: Size.square(size),
      painter: _ShufflePainter(ink, markStrokeFor(size)),
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

    // Two crossing rules: left pair bends, right pair runs to the heads.
    final Path rules = Path()
      ..moveTo(s * 0.14, s * 0.36)
      ..lineTo(s * 0.32, s * 0.36)
      ..lineTo(s * 0.54, s * 0.64)
      ..lineTo(s * 0.70, s * 0.64)
      ..moveTo(s * 0.14, s * 0.64)
      ..lineTo(s * 0.32, s * 0.64)
      ..lineTo(s * 0.54, s * 0.36)
      ..lineTo(s * 0.70, s * 0.36);
    canvas.drawPath(rules, paint);

    // Arrowheads at both right ends.
    final Path heads = Path()
      ..moveTo(s * 0.72, s * 0.30)
      ..lineTo(s * 0.84, s * 0.36)
      ..lineTo(s * 0.72, s * 0.42)
      ..moveTo(s * 0.72, s * 0.58)
      ..lineTo(s * 0.84, s * 0.64)
      ..lineTo(s * 0.72, s * 0.70);
    canvas.drawPath(heads, paint);
  }

  @override
  bool shouldRepaint(_ShufflePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Magnifier — names the filter field (no placeholder text, rule 1).
class SearchMark extends StatelessWidget {
  const SearchMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SearchPainter(markInk(context), markStrokeFor(size)),
      );
}

class _SearchPainter extends CustomPainter {
  const _SearchPainter(this.ink, this.stroke);

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
    canvas.drawCircle(Offset(s * 0.43, s * 0.43), s * 0.23, paint);
    canvas.drawLine(
      Offset(s * 0.60, s * 0.60),
      Offset(s * 0.83, s * 0.83),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SearchPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// The × — the shape the Open plus already rotates into; used as the
/// clear-text control inside the filter field.
class CrossMark extends StatelessWidget {
  const CrossMark({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _CrossPainter(markInk(context), markStrokeFor(size)),
      );
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final double s = size.width;
    canvas.drawLine(Offset(s * 0.28, s * 0.28), Offset(s * 0.72, s * 0.72), paint);
    canvas.drawLine(Offset(s * 0.72, s * 0.28), Offset(s * 0.28, s * 0.72), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Undock — a window with an arrow leaving it (the playlist becomes its
/// own window). Swaps with [DockMark] by state, the plus→× precedent.
class UndockMark extends StatelessWidget {
  const UndockMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _UndockPainter(markInk(context), markStrokeFor(size)),
      );
}

class _UndockPainter extends CustomPainter {
  const _UndockPainter(this.ink, this.stroke);

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

    // The window.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.10, s * 0.28, s * 0.70, s * 0.78),
        Radius.circular(s * 0.10),
      ),
      paint,
    );
    // The arrow leaving, up-right.
    canvas.drawLine(Offset(s * 0.56, s * 0.44), Offset(s * 0.86, s * 0.14), paint);
    final Path head = Path()
      ..moveTo(s * 0.74, s * 0.14)
      ..lineTo(s * 0.86, s * 0.14)
      ..lineTo(s * 0.86, s * 0.26);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_UndockPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Dock back — the same window with the arrow returning into it.
class DockMark extends StatelessWidget {
  const DockMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _DockPainter(markInk(context), markStrokeFor(size)),
      );
}

class _DockPainter extends CustomPainter {
  const _DockPainter(this.ink, this.stroke);

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

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.10, s * 0.28, s * 0.70, s * 0.78),
        Radius.circular(s * 0.10),
      ),
      paint,
    );
    // The arrow coming home, down-left.
    canvas.drawLine(Offset(s * 0.86, s * 0.14), Offset(s * 0.58, s * 0.42), paint);
    final Path head = Path()
      ..moveTo(s * 0.58, s * 0.30)
      ..lineTo(s * 0.58, s * 0.42)
      ..lineTo(s * 0.70, s * 0.42);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_DockPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Favourite — a two-verticals bookmark with a notch (never a star: a
/// five-point star at 15 px turns to mush). Outline until hovered;
/// [filled] = the channel IS a favourite and the mark stays visible.
class BookmarkMark extends StatelessWidget {
  const BookmarkMark({super.key, this.size = 16, this.filled = false});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter:
            _BookmarkPainter(markInk(context), markStrokeFor(size), filled),
      );
}

class _BookmarkPainter extends CustomPainter {
  const _BookmarkPainter(this.ink, this.stroke, this.filled);

  final Color ink;
  final double stroke;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Path mark = Path()
      ..moveTo(s * 0.26, s * 0.12)
      ..lineTo(s * 0.74, s * 0.12)
      ..lineTo(s * 0.74, s * 0.86)
      ..lineTo(s * 0.50, s * 0.68)
      ..lineTo(s * 0.26, s * 0.86)
      ..close();
    if (filled) {
      canvas.drawPath(
        mark,
        Paint()
          ..color = ink
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      mark,
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

/// Group by — the ONE stable mark for the header's first slot in channel
/// mode (playlist_imp.md §10.2 / M5: it never morphs per mode; the four
/// modes ride its pill as [GroupModeMark]s). A group bracket around rows.
class GroupByMark extends StatelessWidget {
  const GroupByMark({super.key, this.size = 18, this.quiet = false});

  final double size;

  /// Suspended (a search is flattening the list) — quiet ink, the same
  /// grammar shuffle borrows under repeat one.
  final bool quiet;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _GroupMarksPainter.category(
            quiet ? markInk(context).withAlpha(140) : markInk(context),
            markStrokeFor(size)),
      );
}

/// The group modes rode the group-by pill (flat · category · language ·
/// country). Used only inside the pill, never in the header slot itself.
enum GroupModeKind { flat, category, language, country }

class GroupModeMark extends StatelessWidget {
  const GroupModeMark({super.key, required this.kind, this.size = 18});

  final GroupModeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color ink = markInk(context);
    final double stroke = markStrokeFor(size);
    final _GroupMarksPainter painter = switch (kind) {
      GroupModeKind.flat => _GroupMarksPainter.flat(ink, stroke),
      GroupModeKind.category => _GroupMarksPainter.category(ink, stroke),
      GroupModeKind.language => _GroupMarksPainter.language(ink, stroke),
      GroupModeKind.country => _GroupMarksPainter.country(ink, stroke),
    };
    return CustomPaint(size: Size.square(size), painter: painter);
  }
}

class _GroupMarksPainter extends CustomPainter {
  const _GroupMarksPainter._(this.ink, this.stroke, this.kind);

  factory _GroupMarksPainter.flat(Color i, double s) =>
      _GroupMarksPainter._(i, s, GroupModeKind.flat);
  factory _GroupMarksPainter.category(Color i, double s) =>
      _GroupMarksPainter._(i, s, GroupModeKind.category);
  factory _GroupMarksPainter.language(Color i, double s) =>
      _GroupMarksPainter._(i, s, GroupModeKind.language);
  factory _GroupMarksPainter.country(Color i, double s) =>
      _GroupMarksPainter._(i, s, GroupModeKind.country);

  final Color ink;
  final double stroke;
  final GroupModeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final Paint quiet = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final double s = size.width;

    switch (kind) {
      case GroupModeKind.flat:
        // Three dot + rule rows.
        for (final double y in <double>[0.28, 0.50, 0.72]) {
          canvas.drawCircle(
            Offset(s * 0.17, s * y),
            s * 0.05,
            Paint()
              ..color = ink
              ..style = PaintingStyle.fill,
          );
          canvas.drawLine(Offset(s * 0.30, s * y), Offset(s * 0.86, s * y), paint);
        }
      case GroupModeKind.category:
        // Top rule, a bracket grouping two quiet rows.
        canvas.drawLine(Offset(s * 0.20, s * 0.26), Offset(s * 0.64, s * 0.26), paint);
        final Path bracket = Path()
          ..moveTo(s * 0.26, s * 0.40)
          ..lineTo(s * 0.20, s * 0.40)
          ..lineTo(s * 0.20, s * 0.78)
          ..lineTo(s * 0.26, s * 0.78);
        canvas.drawPath(bracket, paint);
        canvas.drawLine(Offset(s * 0.34, s * 0.52), Offset(s * 0.80, s * 0.52), quiet);
        canvas.drawLine(Offset(s * 0.34, s * 0.70), Offset(s * 0.72, s * 0.70), quiet);
      case GroupModeKind.language:
        // Speech bubble with two quiet lines.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.12, s * 0.16, s * 0.88, s * 0.64),
            Radius.circular(s * 0.14),
          ),
          paint,
        );
        final Path tail = Path()
          ..moveTo(s * 0.36, s * 0.64)
          ..lineTo(s * 0.36, s * 0.82)
          ..lineTo(s * 0.56, s * 0.64);
        canvas.drawPath(tail, paint);
        canvas.drawLine(Offset(s * 0.26, s * 0.34), Offset(s * 0.62, s * 0.34), quiet);
        canvas.drawLine(Offset(s * 0.26, s * 0.48), Offset(s * 0.74, s * 0.48), quiet);
      case GroupModeKind.country:
        // A flag.
        canvas.drawLine(Offset(s * 0.24, s * 0.12), Offset(s * 0.24, s * 0.88), paint);
        final Path flag = Path()
          ..moveTo(s * 0.24, s * 0.20)
          ..lineTo(s * 0.76, s * 0.20)
          ..lineTo(s * 0.62, s * 0.34)
          ..lineTo(s * 0.76, s * 0.48)
          ..lineTo(s * 0.24, s * 0.48)
          ..close();
        canvas.drawPath(flag, paint);
    }
  }

  @override
  bool shouldRepaint(_GroupMarksPainter old) =>
      old.ink != ink || old.stroke != stroke || old.kind != kind;
}
