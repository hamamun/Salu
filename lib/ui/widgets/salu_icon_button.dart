import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// SALU's ONE icon-interaction recipe (see follow.md · §2).
///
/// Every clickable icon in the app is built on this widget so the whole
/// player answers the cursor with a single, consistent feel:
///
///   · rest   — the mark sits at [AppColors.iconIdle] (soft gray)
///   · hover  — the mark itself lights up to full white (~120 ms) and
///              grows to 1.06× — NO shape is ever drawn behind it
///   · press  — the mark sinks to 0.90× while the button is down and
///              springs back on release — no ripple, no flash
///   · active — (toggles) the mark stays full white with a faint static
///              glow; glow is reserved for active states, never hover
///
/// The child receives its color through an [IconTheme] override, so both
/// stock [Icon]s and SALU's custom-painted marks (which read
/// `IconTheme.of(context).color`) light up the same way.
class SaluIconButton extends StatefulWidget {
  const SaluIconButton({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
    this.size = 34,
    this.active = false,
  });

  /// The mark itself — an [Icon] or a custom-painted SALU mark.
  final Widget child;

  final VoidCallback onTap;

  /// OS-convention tooltip (names the control — never teaches).
  final String? tooltip;

  /// Square hit-target side length.
  final double size;

  /// Toggled-on state: full white + faint static glow.
  final bool active;

  @override
  State<SaluIconButton> createState() => _SaluIconButtonState();
}

class _SaluIconButtonState extends State<SaluIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool lit = _hovered || widget.active;
    final double scale = _pressed ? 0.90 : (_hovered ? 1.06 : 1.0);

    Widget mark = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: AppColors.iconIdle,
          end: lit ? AppColors.textPrimary : AppColors.iconIdle,
        ),
        duration: const Duration(milliseconds: 120),
        builder: (BuildContext context, Color? color, Widget? _) {
          final Color c = color ?? AppColors.iconIdle;
          return IconTheme.merge(
            data: IconThemeData(color: c),
            child: widget.child,
          );
        },
      ),
    );

    // Faint static glow — active state only (follow.md rule).
    if (widget.active) {
      mark = DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x26FFFFFF),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: mark,
      );
    }

    Widget result = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(child: mark),
        ),
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip != null) {
      result = Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: result,
      );
    }
    return result;
  }
}
