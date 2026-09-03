import 'package:flutter/material.dart';

/// SALU's settings mark — six thin dots in two lines of three.
///
/// Used in the title bar (caption button) and again in the settings
/// window header, so the window is always recognizable by the mark
/// that opened it.
class DotGridIcon extends StatelessWidget {
  const DotGridIcon({
    super.key,
    required this.color,
    this.size = 18,
  });

  /// Width of the whole mark (height is derived: two lines of dots).
  final double size;

  /// Dot color — keep it monochrome per the design rules.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double dot = (size * 0.17).clamp(1.6, 4.0).toDouble();
    final Widget dotWidget = Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
