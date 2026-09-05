import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// SALU's frosted-glass capsule material — the Open pill's glass,
/// extracted so the OSD deck uses exactly the same surface (the two can
/// never drift apart).
///
/// `ClipRRect` + `BackdropFilter(blur 18)` + [AppColors.glass] + a
/// `surfaceOutline` hairline. The radius is a parameter: 21 keeps the
/// Open pill a pill, 10 makes the deck a deck.
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.radius,
    required this.child,
    this.height,
    this.padding,
    this.blur = 18,
  });

  /// Corner radius (21 = Open pill, 10 = OSD deck).
  final double radius;

  /// Fixed content height, when the surface has one.
  final double? height;

  /// Inner padding.
  final EdgeInsetsGeometry? padding;

  /// Blur sigma (18 by default, the pill's value).
  final double blur;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: br,
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          child: child,
        ),
      ),
    );
  }
}
