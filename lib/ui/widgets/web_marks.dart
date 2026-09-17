import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'salu_marks.dart';

/// The browser's own marks (web.md), drawn in the exact stroke language of
/// `salu_marks.dart` — thin, monochrome, geometric, colour from the
/// ambient [IconTheme] so [SaluIconButton]'s hover recipe lights them up
/// like every other control in SALU.
///
/// Family:
///   · house           — Home               [HomeMark]
///   · stem + head     — Back / Forward     [ArrowMark] (mirrored)
///   · ¾ arc + head    — Reload             [ReloadMark]
///   · five points     — Favourite star     [StarMark] (outline / filled —
///                       the two-state URL-bar mark web.md locks)
///   · heart           — Favourites hub     [HeartMark] (web.md's ♥ slot)
///   · crossed rules   — Close (tab ×)      [CloseMark]
///   · tabbed rect     — Folder             [FolderMark]
///   · circle + hands  — History row        [ClockMark]
///   · handle+bristles — Clear browsing data [BroomMark]
///   · body + shackle  — Site information   [PadlockMark] (closed = https,
///                       open = the line is not private)
///   · window + window — Held-back pop-ups  [PopupMark] (the address bar's
///                       badge — Chrome's blocked-pop-up icon, SALU-drawn)

/// Home — a house: roof rule, body, a small door.
class HomeMark extends StatelessWidget {
  const HomeMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HomePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _HomePainter extends CustomPainter {
  const _HomePainter(this.ink, this.stroke);

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
    canvas.drawPath(
      Path()
        ..moveTo(p(4, 11.5).dx, p(4, 11.5).dy)
        ..lineTo(p(12, 4.5).dx, p(12, 4.5).dy)
        ..lineTo(p(20, 11.5).dx, p(20, 11.5).dy),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(6, 10).dx, p(6, 10).dy)
        ..lineTo(p(6, 19.5).dx, p(6, 19.5).dy)
        ..lineTo(p(18, 19.5).dx, p(18, 19.5).dy)
        ..lineTo(p(18, 10).dx, p(18, 10).dy),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(10.2, 19.5).dx, p(10.2, 19.5).dy)
        ..lineTo(p(10.2, 14.5).dx, p(10.2, 14.5).dy)
        ..lineTo(p(13.8, 14.5).dx, p(13.8, 14.5).dy)
        ..lineTo(p(13.8, 19.5).dx, p(13.8, 19.5).dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HomePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Back / Forward — a stem with a chevron head at one end. [flipped]
/// mirrors it, so one mark serves both directions (one mark, modified).
class ArrowMark extends StatelessWidget {
  const ArrowMark({super.key, this.size = 16, this.flipped = false});

  final double size;

  /// true = points right (Forward); false = points left (Back).
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ArrowPainter(markInk(context), markStrokeFor(size), flipped),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.ink, this.stroke, this.flipped);

  final Color ink;
  final double stroke;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    Offset p(double x, double y) {
      final double px = flipped ? s * (24 - x) / 24 : s * x / 24;
      return Offset(px, s * y / 24);
    }

    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(p(6, 12), p(19, 12), paint);
    canvas.drawPath(
      Path()
        ..moveTo(p(11, 6.5).dx, p(11, 6.5).dy)
        ..lineTo(p(6, 12).dx, p(6, 12).dy)
        ..lineTo(p(11, 17.5).dx, p(11, 17.5).dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.ink != ink || old.stroke != stroke || old.flipped != flipped;
}

/// Reload — the family's arc + arrowhead (the player's Restart geometry,
/// rotated so its gap reads as "continue the cycle").
class ReloadMark extends StatelessWidget {
  const ReloadMark({super.key, this.size = 17});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ReloadPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _ReloadPainter extends CustomPainter {
  const _ReloadPainter(this.ink, this.stroke);

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

    const double start = -math.pi / 2 + math.pi / 4;
    const double sweep = 3 * math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      paint,
    );

    const double endAngle = start + sweep;
    final Offset tip = Offset(
      c.dx + r * math.cos(endAngle),
      c.dy + r * math.sin(endAngle),
    );
    final Offset tangent = Offset(-math.sin(endAngle), math.cos(endAngle));
    final Offset normal = Offset(tangent.dy, -tangent.dx) * (s * 0.11);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - tangent.dx * s * 0.16 + normal.dx,
            tip.dy - tangent.dy * s * 0.16 + normal.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - tangent.dx * s * 0.16 - normal.dx,
            tip.dy - tangent.dy * s * 0.16 - normal.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ReloadPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// The favourite star — web.md locks this control to TWO states, so the
/// mark carries the state: outline = not saved, filled = saved. Filled is
/// also stroked with round joins (the family's softening, as on PlayMark).
class StarMark extends StatelessWidget {
  const StarMark({super.key, this.size = 15, this.filled = false});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StarPainter(markInk(context), markStrokeFor(size), filled),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.ink, this.stroke, this.filled);

  final Color ink;
  final double stroke;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset c = Offset(s * 0.5, s * 0.5);
    final Path star = Path();
    for (int i = 0; i < 10; i++) {
      final double r = i.isEven ? s * 0.44 : s * 0.20;
      final double a = -math.pi / 2 + i * math.pi / 5;
      final Offset point =
          Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    if (filled) {
      canvas.drawPath(
        star,
        Paint()
          ..color = ink
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      star,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.ink != ink || old.stroke != stroke || old.filled != filled;
}

/// Heart — the favourites hub's mark (web.md's ♥ slot on the tab bar).
class HeartMark extends StatelessWidget {
  const HeartMark({super.key, this.size = 16, this.filled = false});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HeartPainter(markInk(context), markStrokeFor(size), filled),
    );
  }
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter(this.ink, this.stroke, this.filled);

  final Color ink;
  final double stroke;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Path heart = Path()
      ..moveTo(w * 0.5, h * 0.84)
      ..cubicTo(w * 0.06, h * 0.52, w * 0.14, h * 0.14, w * 0.5, h * 0.32)
      ..cubicTo(w * 0.86, h * 0.14, w * 0.94, h * 0.52, w * 0.5, h * 0.84)
      ..close();
    if (filled) {
      canvas.drawPath(
        heart,
        Paint()
          ..color = ink
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      heart,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) =>
      old.ink != ink || old.stroke != stroke || old.filled != filled;
}

/// Close — two crossed rules: the tab × and the cancel mark, the same
/// silhouette the Open plus becomes at 45°, so "close" is one family away.
class CloseMark extends StatelessWidget {
  const CloseMark({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ClosePainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final double a = size.width * 0.26;
    final double b = size.width * 0.74;
    canvas.drawLine(Offset(a, a), Offset(b, b), paint);
    canvas.drawLine(Offset(b, a), Offset(a, b), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Folder — a tabbed rectangle: the favourite panel's "Change folder"
/// shape, a plain rule-frame (SALU never draws Windows' folder).
class FolderMark extends StatelessWidget {
  const FolderMark({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FolderPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter(this.ink, this.stroke);

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
    canvas.drawPath(
      Path()
        ..moveTo(p(4, 8).dx, p(4, 8).dy)
        ..lineTo(p(9.5, 8).dx, p(9.5, 8).dy)
        ..lineTo(p(11.5, 10).dx, p(11.5, 10).dy)
        ..lineTo(p(20, 10).dx, p(20, 10).dy)
        ..lineTo(p(20, 18).dx, p(20, 18).dy)
        ..lineTo(p(4, 18).dx, p(4, 18).dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FolderPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Clock — the suggestion list's "from history" marker (a visited page).
class ClockMark extends StatelessWidget {
  const ClockMark({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ClockPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(s * 0.5, s * 0.5);
    canvas.drawCircle(c, s * 0.38, paint);
    canvas.drawLine(c, Offset(c.dx, c.dy - s * 0.22), paint);
    canvas.drawLine(c, Offset(c.dx + s * 0.16, c.dy + s * 0.10), paint);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Clear browsing data — a broom: 45° handle, brush bar, three bristles.
/// The web.md 🧹 slot outside the URL bar, drawn like the rest of the
/// family instead of the stock emoji.
class BroomMark extends StatelessWidget {
  const BroomMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BroomPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _BroomPainter extends CustomPainter {
  const _BroomPainter(this.ink, this.stroke);

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
    canvas.drawLine(p(19.5, 3.5), p(12, 11), paint);
    canvas.drawLine(p(8.5, 9.5), p(13.5, 14.5), paint);
    canvas.drawLine(p(9, 11.5), p(5.5, 15), paint);
    canvas.drawLine(p(10.5, 13), p(7.5, 16), paint);
    canvas.drawLine(p(12, 14.5), p(9.5, 17), paint);
  }

  @override
  bool shouldRepaint(_BroomPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// Site information — a padlock: the address bar's left-most mark
/// (Chrome's 🔒 slot). Closed = the page came over https; open = the line
/// is not private.
class PadlockMark extends StatelessWidget {
  const PadlockMark({super.key, this.size = 14, this.open = false});

  final double size;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PadlockPainter(markInk(context), markStrokeFor(size), open),
    );
  }
}

class _PadlockPainter extends CustomPainter {
  const _PadlockPainter(this.ink, this.stroke, this.open);

  final Color ink;
  final double stroke;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 7 / 24, s * 10.5 / 24, s * 17 / 24, s * 19 / 24),
        Radius.circular(s * 1.6 / 24),
      ),
      paint,
    );
    final Path shackle = Path()
      ..moveTo(s * 8.6 / 24, s * 10.5 / 24)
      ..lineTo(s * 8.6 / 24, s * 9 / 24)
      ..arcToPoint(
        Offset(s * 15.4 / 24, s * 9 / 24),
        radius: Radius.circular(s * 3.4 / 24),
      );
    if (open) {
      // The arm ends in the air — the page is not private.
      shackle.lineTo(s * 15.4 / 24, s * 7.6 / 24);
    } else {
      shackle.lineTo(s * 15.4 / 24, s * 10.5 / 24);
    }
    canvas.drawPath(shackle, paint);
    canvas.drawCircle(
      Offset(s * 12 / 24, s * 14.6 / 24),
      stroke * 0.85,
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_PadlockPainter old) =>
      old.ink != ink || old.stroke != stroke || old.open != open;
}

/// Held-back pop-ups — two overlapping window rects: the badge in the
/// address bar's right corner (Chrome's blocked-pop-up icon, SALU-drawn).
class PopupMark extends StatelessWidget {
  const PopupMark({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PopupPainter(markInk(context), markStrokeFor(size)),
    );
  }
}

class _PopupPainter extends CustomPainter {
  const _PopupPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 4 / 24, s * 5 / 24, s * 14.5 / 24, s * 13.5 / 24),
        Radius.circular(s * 1.6 / 24),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 9.5 / 24, s * 10.5 / 24, s * 20 / 24, s * 19 / 24),
        Radius.circular(s * 1.6 / 24),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PopupPainter old) =>
      old.ink != ink || old.stroke != stroke;
}
