import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerExitEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent;
import 'package:flutter/material.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import 'hover_chip.dart';

/// SALU's volume bar (outline · §3) — the timeline's thin sibling.
///
/// One thin HORIZONTAL bar (never vertical — it lies in the control row
/// exactly like the timeline lies in Row 1, fill growing left → right):
/// **140 × 14 px**, breathing to 16 px on hover inside its fixed 34 px
/// hit box, so nothing around it ever moves. No `0`/`100` endpoints —
/// the current value sits INSIDE the bar (`62%`, 10 px tabular), pinned
/// to the right edge of the fill; when the fill is too short to hold it
/// (muted / 0 %) it rests at the left edge.
///
/// Quiet at rest (`iconIdle` tone), brightens to `textPrimary` while
/// hovering or dragging; the fill brightens one notch too. Hover chip =
/// the timeline's chip ([HoverChip]): value under the cursor. Mouse
/// wheel: ±5 % per notch. Drag is horizontal only; dragging rightward
/// out of silence unmutes.
///
/// The SAME widget is reused read-only (120 × 14, no interactions)
/// inside the OSD volume card so the two can never drift apart.
class VolumeBar extends StatefulWidget {
  const VolumeBar({
    super.key,
    this.width = 140,
    this.readOnly = false,
  });

  /// Bar width — 140 in the control row, 120 in the OSD volume card.
  final double width;

  /// Read-only copy for the OSD card: no pointer, no chip, no wheel.
  final bool readOnly;

  @override
  State<VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<VolumeBar> {
  final PlayerService _player = PlayerService.instance;

  bool _hovered = false;
  bool _dragging = false;

  /// Pointer x as a fraction of the bar (0..1) — drives the hover chip.
  double? _hoverFrac;

  double _fracAt(double dx, double w) =>
      _clamp01(w <= 0 ? 0 : dx / w);

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  void _apply(double dx, double w) {
    _player.setVolumeUI(_fracAt(dx, w) * 100);
  }

  void _onWheel(double dy) {
    _player.stepVolume(dy > 0 ? 5 : -5);
  }

  static const TextStyle _labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: 0.3,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    shadows: <Shadow>[Shadow(color: Color(0x99000000), blurRadius: 2)],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 34,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          return ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              _player.volumeLevel,
              _player.isMuted,
            ]),
            builder: (BuildContext context, Widget? _) {
              final bool muted = _player.isMuted.value;
              final double level = _player.volumeLevel.value;
              final double frac =
                  (muted ? 0.0 : level / 100).clamp(0.0, 1.0).toDouble();
              final bool active = !widget.readOnly && (_hovered || _dragging);
              final bool showChip = active && _hoverFrac != null;

              final Widget bar = _buildBar(
                w: w,
                frac: frac,
                level: level,
                muted: muted,
                bright: active,
              );

              if (widget.readOnly) {
                return Center(child: bar);
              }

              return MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() {
                  _hovered = false;
                  _hoverFrac = null;
                }),
                onHover: (PointerHoverEvent e) {
                  setState(() => _hoverFrac = _fracAt(e.localPosition.dx, w));
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (PointerDownEvent e) {
                    setState(() {
                      _dragging = true;
                      _hoverFrac = _fracAt(e.localPosition.dx, w);
                    });
                    _apply(e.localPosition.dx, w);
                  },
                  onPointerMove: (PointerMoveEvent e) {
                    if (!_dragging) return;
                    setState(
                        () => _hoverFrac = _fracAt(e.localPosition.dx, w));
                    _apply(e.localPosition.dx, w);
                  },
                  onPointerUp: (PointerUpEvent e) {
                    if (!_dragging) return;
                    setState(() => _dragging = false);
                    _apply(e.localPosition.dx, w); // final snap
                  },
                  onPointerCancel: (PointerCancelEvent e) {
                    if (_dragging) setState(() => _dragging = false);
                  },
                  onPointerSignal: (PointerSignalEvent event) {
                    if (event is PointerScrollEvent) {
                      _onWheel(event.scrollDelta.dy);
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Center(child: bar),
                      if (showChip)
                        Positioned(
                          top: 26,
                          left: (_hoverFrac! * w - 22).clamp(
                              0.0, (w - 44).clamp(0.0, w)).toDouble(),
                          child: HoverChip(
                            label:
                                '${(_fracAt((_hoverFrac! * w), w) * 100).round()}%',
                            width: 44,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The bar body: track + translucent fill + the in-bar percent label
  /// pinned to the fill's right edge (left edge when the fill is too
  /// short to hold it — one rule covers muted / 0 % too).
  Widget _buildBar({
    required double w,
    required double frac,
    required double level,
    required bool muted,
    required bool bright,
  }) {
    final double barHeight = _hovered || _dragging ? 16 : 14;
    final Color track = bright
        ? Color.alphaBlend(const Color(0x14FFFFFF), AppColors.barTrack)
        : AppColors.barTrack;
    final Color fill = bright
        ? Color.alphaBlend(const Color(0x1AFFFFFF), AppColors.barFill)
        : AppColors.barFill;
    final Color label = bright ? AppColors.textPrimary : AppColors.iconIdle;
    final double fillEnd = w * frac;

    // `labelX = max(pad, fillEnd − labelWidth − pad)` — the label rides
    // the fill's end; a short fill parks it at the left edge, and it
    // never runs past the bar's right edge.
    const double labelWidth = 34; // measured for `100%` at 10 px
    const double pad = 7;
    final double labelX = (fillEnd - labelWidth - pad)
        .clamp(pad, w - labelWidth - pad)
        .toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: barHeight,
        width: w,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: track)),
            if (fillEnd > 0)
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: fillEnd,
                child: ColoredBox(color: fill),
              ),
            // The percent value rides inside the fill — never a
            // separate numeral outside the bar.
            Positioned(
              left: labelX,
              top: 0,
              bottom: 0,
              width: labelWidth,
              child: Center(
                child: Text(
                  '${(muted ? 0 : level.round()).clamp(0, 100)}%',
                  style: _labelStyle.copyWith(color: label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
