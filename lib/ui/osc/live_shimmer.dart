import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The live shimmer sweep (playlist_imp.md §10.8a–c): a soft light band
/// gliding left→right across an inert surface. It is the ONE live signal
/// of SALU — the timeline carries it while the chrome is visible, the
/// bottom hairline carries it while the chrome is auto-hidden; they hand
/// off and never both show (M31).
///
/// `bright` is the packaging/loading variant (narrower, brighter — M31b
/// needs it at the 2 px hairline); the receiving variant is a wide,
/// quiet drift. A stall or pause stops the drift (the `receiving` flag
/// in `PlayerService` is the single source of truth, M31/§10.8c).
/// Display-only, motion only — the hairline keeps its existing pointer-
/// absorbing Listener (M31c).
class LiveSweep extends StatefulWidget {
  const LiveSweep({
    super.key,
    required this.bright,
    this.brightness = 0.22,
  });

  final bool bright;

  /// Alpha scale for the band peak (timeline: ~0.22 quiet; hairline:
  /// ~0.55 bright, M31b).
  final double brightness;

  @override
  State<LiveSweep> createState() => _LiveSweepState();
}

class _LiveSweepState extends State<LiveSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.bright ? 900 : 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (BuildContext context, Widget? _) {
        return CustomPaint(
          painter: LiveSweepPainter(_sweep.value, widget.bright,
              widget.brightness),
        );
      },
    );
  }
}

/// Paints one sweep frame at phase [t] (0..1): bright = narrow strong
/// band; quiet = wide soft band.
class LiveSweepPainter extends CustomPainter {
  const LiveSweepPainter(this.t, this.bright, this.brightness);

  final double t;
  final bool bright;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final double band = bright ? size.width * 0.16 : size.width * 0.42;
    final double insetY = size.height > 14 ? 6 : 0;
    final Rect rect = Rect.fromLTWH(
      -(band / 2) + (size.width + band) * t,
      insetY,
      band,
      size.height - insetY * 2,
    );
    final Paint paint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          AppColors.barThumb.withAlpha(0),
          AppColors.barThumb.withAlpha((brightness * 255).round()),
          AppColors.barThumb.withAlpha(0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(LiveSweepPainter old) =>
      old.t != t || old.bright != bright || old.brightness != brightness;
}
