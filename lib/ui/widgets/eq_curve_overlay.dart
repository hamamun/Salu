import 'package:flutter/material.dart';

import '../../core/tune/tune_model.dart';
import '../../core/tune_service.dart';
import '../../theme/app_theme.dart';
import 'eq_curve_painter.dart';
import 'tune_sliders.dart';

// The painter and the glide live in the widgets the panel also uses, so the
// mini curve and the on-video curve can never disagree about either.

/// The curve on the video (eq_imp.md §1.8) — the third, rare use of the
/// monochrome mark: the mark itself, blown up.
///
/// A faint equalizer curve drawn across the whole frame, in one quiet
/// translucent white like film grain, so soft it is barely there. It lives in
/// Flutter rather than as an mpv filter — a documented deviation from the
/// spec's `curves` sketch, and a better one: a `--vf` filter WOULD darken the
/// picture on pause, exactly what §1.8 forbids, while a painter over the
/// surface cannot.
///
/// Never on a live channel (§12's safe-by-design rule), never over the
/// chrome, never a filled block, never a warning colour, never a legend, and
/// never when the curve is Flat (there is nothing to draw). It sits in a
/// `Stack` BELOW the chrome layer, ignores every pointer, and takes no focus.
class EqCurveOverlay extends StatelessWidget {
  const EqCurveOverlay({super.key, this.opacity = 0.18});

  /// How present the line is. The video's average luminance would be the
  /// honest way to pick this (§7a); for v1 it is one remembered constant —
  /// quiet enough to read as grain, visible enough to read as a shape.
  final double opacity;

  static const Duration _fade = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final TuneService tune = TuneService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        tune.curveOnVideo,
        tune.available,
        tune.eq,
      ]),
      builder: (BuildContext context, Widget? _) {
        final EqCurve curve = tune.eq.value;
        final bool show =
            tune.curveOnVideo.value && tune.available.value && !curve.isFlat;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: show ? opacity.clamp(0.0, 1.0).toDouble() : 0,
            duration: _fade,
            // The same 320 ms as the panel's curve and the OSD card (§1.8:
            // "while the change happens, the curve can glide over ~300 ms").
            child: GlideList(
              values: curve.gains,
              jumpThreshold: 1.5,
              duration: const Duration(milliseconds: 320),
              builder: (BuildContext context, List<double> shown) {
                return CustomPaint(
                  painter: EqCurvePainter(
                    gains: shown,
                    ink: AppColors.textPrimary,
                    fill: true,
                    // No zero rule on the picture: the film has its own
                    // horizon, and a line across it is a second UI.
                    showAxis: false,
                    strokeWidth: 2.2,
                    padding: 84,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
