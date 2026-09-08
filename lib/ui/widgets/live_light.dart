import 'package:flutter/material.dart';

/// The still soft light — SALU's "live, no timeline" signal
/// (playlist_imp.md §10.8a · §10.8c · §10.10b, point 9 Final, option A).
///
/// A soft, *still* centre glow on an empty track: present while data
/// arrives, quietly fading away when the stream stalls. Nothing ever
/// moves — the change (light present → light gone) is the signal. No
/// text, no red dot, no "LIVE" badge (rules 1 and 6).
///
/// One widget drives both surfaces, so they can never disagree: the
/// 23 px timeline (centre near white .16) and the 2 px bottom hairline
/// (centre near .5 — 2 px needs the contrast). The hairline exists only
/// while the chrome is hidden and the timeline only while it is shown,
/// so the signal hands off and is never duplicated. The network-fetch
/// state (§10.10b) reuses the same light — no spinner, no words.
class StillSoftLight extends StatelessWidget {
  const StillSoftLight({
    super.key,
    required this.visible,
    this.peak = 0.16,
    this.radiusX = 0.52,
    this.radiusY = 1.2,
    this.fadeStop = 0.72,
  });

  /// Whether data is arriving — the light fades in/out over 600 ms.
  final bool visible;

  /// Centre brightness, 0..1 (timeline .16, hairline .5).
  final double peak;

  /// Ellipse radii as fractions of the box (timeline 52% × 120%,
  /// hairline 30% × 400% — the approved preview's geometry).
  final double radiusX;
  final double radiusY;

  /// Gradient stop where the glow reaches transparency (timeline .72,
  /// hairline .8).
  final double fadeStop;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: CustomPaint(
        painter: _StillSoftLightPainter(
          peak: peak,
          radiusX: radiusX,
          radiusY: radiusY,
          fadeStop: fadeStop,
        ),
      ),
    );
  }
}

class _StillSoftLightPainter extends CustomPainter {
  const _StillSoftLightPainter({
    required this.peak,
    required this.radiusX,
    required this.radiusY,
    required this.fadeStop,
  });

  final double peak;
  final double radiusX;
  final double radiusY;
  final double fadeStop;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    if (w <= 0 || h <= 0 || peak <= 0) return;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(radiusX * w, radiusY * h);
    final Paint paint = Paint()
      ..shader = RadialGradient(
        center: Offset.zero,
        radius: 1,
        colors: <Color>[
          Colors.white.withAlpha((peak * 255).round().clamp(0, 255).toInt()),
          Colors.white.withAlpha(0),
        ],
        stops: <double>[0, fadeStop.clamp(0.01, 1).toDouble()],
      ).createShader(const Rect.fromCircle(
        center: Offset.zero,
        radius: 1,
      ));
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StillSoftLightPainter old) =>
      old.peak != peak ||
      old.radiusX != radiusX ||
      old.radiusY != radiusY ||
      old.fadeStop != fadeStop;
}
