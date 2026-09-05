import 'dart:async';

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
///   · off    — ([enabled] false) the mark simply dims and stops
///              answering the cursor; it is never boxed, greyed out with
///              a shape, or hidden — and its tooltip still names it
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
    this.enabled = true,
    this.onHoldRepeat,
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

  /// When false the mark dims, ignores hover/press and does not fire
  /// [onTap]. Nothing is drawn around it — it just goes quiet.
  final bool enabled;

  /// Press-and-hold mode (the seek marks): when set, the button fires
  /// [onHoldRepeat] the instant the pointer goes down, then keeps firing
  /// every [holdRepeatInterval] while held — a physical held button. The
  /// 0.90× press-scale stays down for the whole hold. Takes the place of
  /// [onTap] for this button (pass a no-op there).
  final VoidCallback? onHoldRepeat;

  /// Repeat cadence while held.
  static const Duration holdRepeatInterval = Duration(milliseconds: 300);

  @override
  State<SaluIconButton> createState() => _SaluIconButtonState();
}

class _SaluIconButtonState extends State<SaluIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _stopHold();
    widget.onHoldRepeat?.call();
    _holdTimer = Timer.periodic(
      SaluIconButton.holdRepeatInterval,
      (_) => widget.onHoldRepeat?.call(),
    );
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled;
    final bool lit = on && (_hovered || widget.active);
    final double scale =
        !on ? 1.0 : (_pressed ? 0.90 : (_hovered ? 1.06 : 1.0));
    // Disabled marks rest lower than iconIdle — dimmed, never boxed out.
    final Color rest =
        on ? AppColors.iconIdle : AppColors.iconIdle.withAlpha(95);

    Widget mark = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: rest,
          end: lit ? AppColors.textPrimary : rest,
        ),
        duration: const Duration(milliseconds: 120),
        builder: (BuildContext context, Color? color, Widget? _) {
          final Color c = color ?? rest;
          return IconTheme.merge(
            data: IconThemeData(color: c),
            child: widget.child,
          );
        },
      ),
    );

    // Faint static glow — active state only (follow.md rule).
    if (widget.active && on) {
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
      onEnter: (_) {
        if (on) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
        _stopHold();
      }),
      child: widget.onHoldRepeat != null
          ? Listener(
              // Hold-repeat mode (seek marks): fire on pointer-down, then
              // every 300 ms while held. Raw pointer events, no arena.
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                if (!on) return;
                setState(() => _pressed = true);
                _startHold();
              },
              onPointerUp: (_) {
                _stopHold();
                if (_pressed) setState(() => _pressed = false);
              },
              onPointerCancel: (_) {
                _stopHold();
                if (_pressed) setState(() => _pressed = false);
              },
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(child: mark),
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: on ? (_) => setState(() => _pressed = true) : null,
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: on ? widget.onTap : null,
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
