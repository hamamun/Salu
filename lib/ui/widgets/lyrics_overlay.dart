import 'package:flutter/material.dart';

import '../../core/lyric_service.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';

/// Mode A (lrc.md L11 / L28): full-window karaoke overlay. The current
/// line is highlighted with as much context as the window fits; every
/// rendered line is a tap target that seeks to its timestamp. No OSD —
/// the jump is the feedback.
class LyricsOverlay extends StatelessWidget {
  const LyricsOverlay({super.key});

  // The tile metrics mirror _LyricLineTile (font × 1.35 leading + the
  // tile's vertical padding × 2) so the fit count below is a close
  // estimate of how many lines the window holds. It is only an estimate:
  // real text can land a hair taller than `fontSize × 1.35` (font
  // metrics, Windows DPI scaling, or a long line that wraps), so the
  // column additionally sits in a centered scroll region — if the
  // estimate is ever a few pixels too tall the block scrolls instead of
  // overflowing (the yellow/black stripes + RenderFlex exception).
  static const double _currentTile = 24 * 1.35 + 20; // 52.4
  static const double _nearTile = 16 * 1.35 + 12; // 33.6 (distance 1)
  static const double _farTile = 14 * 1.35 + 12; // 30.9 (distance ≥ 2)

  static double _tileHeightForDistance(int distance) =>
      distance == 1 ? _nearTile : _farTile;

  /// The context count the window height allows — never a fixed 2+1+2:
  /// a tall window shows many lines above and below, a short one the
  /// current line alone.
  static int _contextFor(double height) {
    // The canvas is always bounded in practice; an unbounded constraint
    // would spin the fit loop forever, so fall back to the old 2+1+2.
    if (!height.isFinite || height <= 0) return 2;
    double remaining = height - _currentTile;
    int k = 0;
    while (true) {
      // The first pair on each side is the distance-1 (16 px) tile;
      // everything beyond it is the 14 px one.
      final double pair = k == 0 ? _nearTile * 2 : _farTile * 2;
      if (remaining < pair) break;
      remaining -= pair;
      k++;
    }
    return k;
  }

  @override
  Widget build(BuildContext context) {
    final LyricService lyrics = LyricService.instance;
    return ColoredBox(
      color: AppColors.videoBackdrop,
      child: SizedBox.expand(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            lyrics.document,
            lyrics.currentIndex,
          ]),
          builder: (BuildContext context, Widget? _) {
            final LyricDocument? doc = lyrics.document.value;
            if (doc == null || doc.isEmpty) return const SizedBox.expand();
            final int current = lyrics.currentIndex.value;
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final int last = doc.lines.length - 1;
                final int k = _contextFor(box.maxHeight);
                // When playback has not yet reached the first line (current < 0),
                // line 0 sits at the middle of the screen ready for the first
                // word, with k upcoming lines below and empty space above.
                final int active =
                    (current < 0 ? 0 : current).clamp(0, last).toInt();
                final int from = (active - k).clamp(0, last).toInt();
                final int to = (active + k).clamp(0, last).toInt();

                // Balance missing context lines above and below the active line
                // so that the active line (or line 0 before vocals begin)
                // remains centered in the window rather than drifting to an edge.
                double missingHeightAbove = 0;
                for (int d = (active - from) + 1; d <= k; d++) {
                  missingHeightAbove += _tileHeightForDistance(d);
                }

                double missingHeightBelow = 0;
                for (int d = (to - active) + 1; d <= k; d++) {
                  missingHeightBelow += _tileHeightForDistance(d);
                }

                // Tiles are sized by distance from the active line so that
                // the active line remains centered with up to k lines context
                // above and below. The scroll view is the overflow safety net.
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          box.maxHeight.isFinite ? box.maxHeight : 0.0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (missingHeightAbove > 0)
                                SizedBox(height: missingHeightAbove),
                              for (int i = from; i <= to; i++)
                                _LyricLineTile(
                                  line: doc.lines[i],
                                  current: i == current,
                                  distance: (i - active).abs(),
                                ),
                              if (missingHeightBelow > 0)
                                SizedBox(height: missingHeightBelow),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LyricLineTile extends StatefulWidget {
  const _LyricLineTile({
    required this.line,
    required this.current,
    required this.distance,
  });

  final LyricLine line;
  final bool current;
  final int distance;

  @override
  State<_LyricLineTile> createState() => _LyricLineTileState();
}

class _LyricLineTileState extends State<_LyricLineTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool current = widget.current;
    final bool isCenter = widget.distance == 0;
    final double size = isCenter
        ? 24
        : (widget.distance <= 1 ? 16 : 14);
    final FontWeight weight = current ? FontWeight.w600 : FontWeight.w400;
    final Color rest = current
        ? AppColors.textPrimary
        : (widget.distance <= 1
            ? AppColors.textSecondary
            : AppColors.textSecondary.withAlpha(140));
    final Color color = _hovered ? AppColors.textPrimary : rest;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // L28: a real seek, no OSD card. The jump is the feedback.
          PlayerService.instance.seekTo(widget.line.timestamp);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: isCenter ? 10 : 6),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              height: 1.35,
              color: color,
            ),
            child: Text(
              widget.line.text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
