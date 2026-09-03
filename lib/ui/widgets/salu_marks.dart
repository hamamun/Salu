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
