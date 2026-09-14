import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/tune/tune_model.dart';
import '../../theme/app_theme.dart';

/// The EQ curve as a shape — ONE painter, drawn twice: small above the band
/// sliders ("a small curve line above the band sliders shows the EQ shape at
/// a glance", eq_imp.md §1.11) and full-screen on the picture itself
/// (§1.9's curve-on-video, "in a soft colour, like film grain").
///
/// The x axis is logarithmic in frequency, exactly like the band centres
/// it passes through: 20 Hz at the left edge, 20 kHz at the right. The y
/// axis is the ±12 dB grid.
class EqCurvePainter extends CustomPainter {
  const EqCurvePainter({
    required this.gains,
    this.ink,
    this.fill = false,
    this.showAxis = true,
    this.strokeWidth = 1.6,
    this.padding = 0,
  });

  final List<double> gains;

  /// The curve's colour — the panel reads the house ink, the overlay a
  /// translucent white that sits ON the picture without hiding it.
  final Color? ink;

  /// Paint the area between the curve and the zero line (soft glow look).
  final bool fill;

  /// The dotted zero rule (off for the on-video drawing, where the picture
  /// already has its own horizon).
  final bool showAxis;

  final double strokeWidth;

  /// Horizontal inset so the curve never touches the box edges.
  final double padding;

  static const double _minHz = 20;
  static const double _maxHz = 20000;

  static double freqToX(double hz, double width, double padding) {
    final double lo = math.log(_minHz) / math.ln10;
    final double hi = math.log(_maxHz) / math.ln10;
    final double f = clampRange((math.log(hz) / math.ln10 - lo) / (hi - lo), 0, 1);
    return padding + (width - padding * 2) * f;
  }

  static double gainToY(double db, double height) {
    final double mid = height / 2;
    final double half = height / 2 * 0.88;
    return mid - clampRange(db, kEqGainMin, kEqGainMax) / kEqGainMax * half;
  }

  /// The curve through the 10 band points, with a flat lead-in and lead-out
  /// so the shape reads as a response, not a polyline.
  Path responsePath(double width, double height) {
    final List<Offset> pts = <Offset>[
      Offset(0, gainToY(0, height)),
    ];
    for (int i = 0; i < kEqBandCount; i++) {
      pts.add(Offset(
        freqToX(kEqBandFreqs[i], width, padding),
        gainToY(i < gains.length ? gains[i] : 0, height),
      ));
    }
    pts.add(Offset(width, gainToY(0, height)));
    final Path path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final Offset a = pts[i - 1], b = pts[i];
      final double mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color color = ink ?? AppColors.iconIdle;
    final Path path = responsePath(size.width, size.height);
    if (fill) {
      final Path area = Path.from(path)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height / 2)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..color = color.withAlpha(28)
          ..style = PaintingStyle.fill,
      );
    }
    if (showAxis) {
      canvas.drawLine(
        Offset(padding, size.height / 2),
        Offset(size.width - padding, size.height / 2),
        Paint()
          ..color = color.withAlpha(60)
          ..strokeWidth = 1,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(EqCurvePainter old) =>
      old.strokeWidth != strokeWidth ||
      old.fill != fill ||
      old.showAxis != showAxis ||
      old.ink != ink ||
      !listEquals(old.gains, gains);
}
