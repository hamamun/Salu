import 'package:flutter/material.dart';

import '../widgets/salu_marks.dart' show markInk, markStrokeFor;

/// The mini bar's two own marks — the toggle that shrinks SALU to its
/// 32 px strip, and the glyph that brings the full window back
/// (mini.md §3 item 4 / §4 / §9).
///
/// Both are drawn in the family's stroke (`markStrokeFor`, `markInk`) like
/// every other SALU mark, so the hover recipe lights them exactly the way
/// it lights the caption glyphs and the transport row they sit beside.
/// Nothing here is a mini-specific redraw of an existing mark: the seven
/// transport marks stay `transport_marks.dart`'s own (§3).

/// The full-mode toggle: a wide, thin rounded strip — the bar itself.
/// Sits immediately left of the Settings glyph in the title strip (§4).
class MiniBarMark extends StatelessWidget {
  const MiniBarMark({super.key, this.size = 18, this.color});

  final double size;

  /// Ink override; the ambient [IconTheme]'s color is used when null
  /// (the family's own rule).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MiniBarPainter(
        color ?? markInk(context),
        markStrokeFor(size),
      ),
    );
  }
}

class _MiniBarPainter extends CustomPainter {
  const _MiniBarPainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Rect strip = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.5),
      width: s * 0.78,
      height: s * 0.30,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(strip, Radius.circular(s * 0.10)),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MiniBarPainter old) =>
      old.ink != ink || old.stroke != stroke;
}

/// The mini bar's Restore glyph (§3 item 4): two corner brackets pointing
/// outward — the preview's own path, geometry for geometry
/// (`design/mini-bar-preview/index.html`). The bar's only "caption"
/// control, and the primary way out of mini (§4).
class MiniRestoreMark extends StatelessWidget {
  const MiniRestoreMark({super.key, this.size = 18, this.color});

  final double size;

  /// Ink override; the ambient [IconTheme]'s color is used when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MiniRestorePainter(
        color ?? markInk(context),
        markStrokeFor(size),
      ),
    );
  }
}

class _MiniRestorePainter extends CustomPainter {
  const _MiniRestorePainter(this.ink, this.stroke);

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    canvas.drawPath(
      Path()
        // Upper left, pointing away from the middle.
        ..moveTo(s * 0.43, s * 0.24)
        ..lineTo(s * 0.25, s * 0.24)
        ..lineTo(s * 0.25, s * 0.42)
        // Lower right, the mirror of it.
        ..moveTo(s * 0.57, s * 0.76)
        ..lineTo(s * 0.75, s * 0.76)
        ..lineTo(s * 0.75, s * 0.58),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MiniRestorePainter old) =>
      old.ink != ink || old.stroke != stroke;
}
