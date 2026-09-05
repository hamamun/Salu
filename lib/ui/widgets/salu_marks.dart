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

/// Shared stroke weight so the whole family reads as one hand.
double _strokeFor(double size) => (size * 0.085).clamp(1.4, 2.2).toDouble();

Color _inkOf(BuildContext context) =>
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
      painter: _PlusPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _FilmFramePainter(_inkOf(context), _strokeFor(size)),
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
      painter: _StackedFramesPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _LinkPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _PlayPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _PlaySavePainter(_inkOf(context), _strokeFor(size)),
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
      painter: _PencilPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _TrashPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _TickPainter(_inkOf(context), _strokeFor(size)),
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
      painter: _GripPainter(_inkOf(context), _strokeFor(size)),
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
