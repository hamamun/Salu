import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The floating value chip shared by the two bars (timeline + volume).
///
/// Semantics (identical for both bars): the chip names the value UNDER
/// THE CURSOR; a bar's in-bar label names the CURRENT value — they
/// coincide while dragging. The chip floats BELOW its bar, over the
/// video; it never reflows anything around it.
class HoverChip extends StatelessWidget {
  const HoverChip({
    super.key,
    required this.label,
    this.width = 96,
  });

  /// The value text (formatted time or percent).
  final String label;

  /// Chip width — 96 for the timeline's `hh:mm:ss`, narrower for the
  /// volume's `62%`.
  final double width;

  static const double height = 20;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.chipBackground,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
