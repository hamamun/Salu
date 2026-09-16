import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/salu_marks.dart' show markStrokeFor;
import 'mini_metrics.dart';

/// The mini bar's volume wheel (mini.md §3 Group 4 · §11 v4 — "wheel means
/// wheel").
///
/// A thin ring dial, 20 px inside the row's 22 px slot: a dim track ring, a
/// level arc filling clockwise from 12 o'clock, and a tiny tick at the head
/// of the arc. **Wheel ±5 % only** — no click, no drag, and no number on the
/// dial: the exact value rides the title swap (§6) and the hover tooltip,
/// exactly as the full window's [VolumeBar] prints it inside its own fill.
///
/// The wheel is not a [SaluIconButton] — it has no tap — but it obeys the
/// same recipe for motion: the mark itself glides `iconIdle → textPrimary`
/// in ~120 ms and grows to 1.06× while the pointer rests on it. Never a
/// background box. Muted (or 0 %) dims the whole dial to the quiet 35 % and
/// leaves the arc empty.
///
/// Rolling is handled by the sound group around this widget, so the speaker
/// beside it answers the wheel too (§3 — "rolling over the speaker or the
/// ring both work").
class VolumeWheel extends StatefulWidget {
  const VolumeWheel({super.key});

  @override
  State<VolumeWheel> createState() => _VolumeWheelState();
}

class _VolumeWheelState extends State<VolumeWheel> {
  final PlayerService _player = PlayerService.instance;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _player.volumeLevel,
        _player.isMuted,
      ]),
      builder: (BuildContext context, Widget? _) {
        final bool muted = _player.isMuted.value;
        final double level = _player.volumeLevel.value;
        final bool silent = muted || level < 1;
        final double frac =
            silent ? 0.0 : (level / 100).clamp(0.0, 1.0).toDouble();
        final Color ink = _hovered ? AppColors.textPrimary : AppColors.iconIdle;
        // The muted dial keeps its shape and drops its voice.
        final Color quiet = ink.withAlpha(90); // ~35 %

        return Tooltip(
          message:
              'Volume ${muted ? 0 : level.round().clamp(0, 100)} % — wheel ±5 %',
          waitDuration: const Duration(milliseconds: 600),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _hovered ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: SizedBox(
                width: MiniMetrics.wheelBox,
                height: MiniMetrics.wheelBox,
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(MiniMetrics.wheelDial),
                    painter: _WheelPainter(
                      track: silent
                          ? AppColors.barTrack.withAlpha(90)
                          : AppColors.barTrack,
                      // The level arc sits at ~75 % ink at rest, full ink
                      // under the pointer (the preview's own recipe).
                      arc: silent ? quiet : ink.withAlpha(_hovered ? 255 : 190),
                      head: silent ? quiet : AppColors.barThumb,
                      stroke: markStrokeFor(MiniMetrics.wheelDial),
                      frac: frac,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Track ring + level arc (clockwise from 12 o'clock) + the head tick.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.track,
    required this.arc,
    required this.head,
    required this.stroke,
    required this.frac,
  });

  final Color track;
  final Color arc;
  final Color head;
  final double stroke;

  /// 0–1 level; 0 draws no arc and no tick (muted / silent).
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset center = size.center(Offset.zero);
    final double radius = s * 0.35;

    // The dial's own body — always there, even in silence.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (frac <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 12 o'clock, filling clockwise
      2 * math.pi * frac,
      false,
      Paint()
        ..color = arc
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // The head tick — a tiny solid bead riding the arc's end.
    final double angle = -math.pi / 2 + 2 * math.pi * frac;
    canvas.drawCircle(
      Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ),
      s * 0.055,
      Paint()
        ..color = head
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.track != track ||
      old.arc != arc ||
      old.head != head ||
      old.stroke != stroke ||
      old.frac != frac;
}
