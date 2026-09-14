import 'package:flutter/material.dart';

import '../../core/lyric_service.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';

/// Mode A (lrc.md L11 / L28): full-window karaoke overlay. The current
/// line is highlighted with a line or two of context; every rendered
/// line is a tap target that seeks to its timestamp. No OSD — the jump
/// is the feedback.
class LyricsOverlay extends StatelessWidget {
  const LyricsOverlay({super.key});

  static const int _context = 2;

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
            final int last = doc.lines.length - 1;
            final int from = (current < 0 ? 0 : current - _context)
                .clamp(0, last)
                .toInt();
            final int to = (current < 0 ? _context : current + _context)
                .clamp(0, last)
                .toInt();

            return Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = from; i <= to; i++)
                        _LyricLineTile(
                          line: doc.lines[i],
                          current: i == current,
                          distance: current < 0 ? 1 : (i - current).abs(),
                        ),
                    ],
                  ),
                ),
              ),
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
    final double size = current
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
          padding: EdgeInsets.symmetric(vertical: current ? 10 : 6),
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
