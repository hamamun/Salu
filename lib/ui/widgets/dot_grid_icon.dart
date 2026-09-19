import 'package:flutter/material.dart';

import 'salu_marks.dart' show markInk;

/// SALU's settings mark — six thin dots in two lines of three.
///
/// Used in the title bar (caption button) and again in the settings
/// window header, so the window is always recognizable by the mark
/// that opened it.
class DotGridIcon extends StatelessWidget {
  const DotGridIcon({
    super.key,
    this.color,
    this.size = 18,
  });

  /// Width of the whole mark (height is derived: two lines of dots).
  final double size;

  /// Dot color — null reads the ambient [IconTheme], so the mark lights
  /// up under the shared icon recipe like the rest of the family. Keep
  /// it monochrome per the design rules.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = color ?? markInk(context);
    final double dot = (size * 0.17).clamp(1.6, 4.0).toDouble();
    final Widget dotWidget = Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
    );

    return SizedBox(
      width: size,
      height: size * 0.7,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[dotWidget, dotWidget, dotWidget],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[dotWidget, dotWidget, dotWidget],
          ),
        ],
      ),
    );
  }
}
