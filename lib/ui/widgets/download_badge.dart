import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/web/web_download_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// The download badge — one widget, two stages: the address bar's right
/// corner (Chrome's download-button slot, beside the held-back pop-up
/// badge) and the title bar's caption row, where it carries the signal
/// into Player mode — a download started in the browser keeps running
/// while you watch, and this is the only place left that can say so.
///
/// It is on screen only while it has something to say ([hasBadge]):
/// something is still travelling, or something finished and nobody has
/// opened the shelf since. The mark itself is the family's
/// [DownloadMark]; the ring around it is the tab strip's own loading-ring
/// language — determinate when the server gave a size, a spinner when it
/// did not. Nothing is ever filled in behind it (follow.md · §2).
class DownloadBadge extends StatelessWidget {
  const DownloadBadge({
    super.key,
    required this.onTap,
    this.size = 26,
    this.markSize = 13,
    this.active = false,
  });

  final VoidCallback onTap;

  /// Square hit target — 26 □ in the address bar (the pop-up badge's
  /// size), 30 □ up in the caption row.
  final double size;

  final double markSize;

  /// Lit while the shelf is open (the same `active` the ♥ hub uses).
  final bool active;

  /// The ring sits outside the mark, so the button's child is a little
  /// larger than the mark itself.
  static const double _ringPad = 5;

  @override
  Widget build(BuildContext context) {
    final WebDownloadService svc = WebDownloadService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        svc.items,
        svc.running,
        svc.unseen,
      ]),
      builder: (BuildContext context, Widget? _) {
        if (!svc.hasBadge) return const SizedBox.shrink();
        final int live = svc.running.value;
        // The newest travelling row drives the ring — the badge reports
        // the download you are most likely waiting for.
        WebDownloadItem? head;
        for (final WebDownloadItem i in svc.items.value) {
          if (i.isRunning) {
            head = i;
            break;
          }
        }
        // The count widens the mark, so the hit box widens with it —
        // a fixed square would clip the second digit (and paint the
        // overflow stripes over the omnibox).
        final Size hit = Size(
          markSize + _ringPad * 2 + (live > 1 ? 18 : 0),
          size,
        );
        return SaluIconButton(
          size: size,
          hitSize: hit,
          active: active,
          onTap: onTap,
          tooltip: 'Downloads',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: markSize + _ringPad * 2,
                height: markSize + _ringPad * 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    if (live > 0)
                      Positioned.fill(child: _Ring(progress: head?.progress)),
                    DownloadMark(size: markSize),
                  ],
                ),
              ),
              // A count only when there is more than one: a single
              // download is already the ring's whole story.
              if (live > 1) ...<Widget>[
                const SizedBox(width: 3),
                Builder(
                  builder: (BuildContext context) => Text(
                    '$live',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: IconTheme.of(context).color ??
                          AppColors.iconIdle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The ring around a travelling download: a hairline sweep from twelve
/// o'clock for the share that has landed, or the tab strip's spinner
/// while the size is still unknown. Painted in the mark's own ink, so
/// the hover recipe lights the ring and the mark together.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  /// `null` = the server never gave a size.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final Color ink = IconTheme.of(context).color ?? AppColors.iconIdle;
    final double? f = progress;
    if (f == null) {
      return Padding(
        padding: const EdgeInsets.all(0.5),
        child: CircularProgressIndicator(
          strokeWidth: 1.4,
          color: ink,
        ),
      );
    }
    // `num.clamp` answers `num`, not `double` — the painter wants the
    // real thing (the same `.toDouble()` the browser's ruler uses).
    return CustomPaint(
      painter: _RingPainter(ink, f.clamp(0.0, 1.0).toDouble()),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.ink, this.fraction);

  final Color ink;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (fraction <= 0) return;
    final Paint paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final Rect rect = Rect.fromLTWH(
      paint.strokeWidth / 2,
      paint.strokeWidth / 2,
      size.width - paint.strokeWidth,
      size.height - paint.strokeWidth,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ink != ink || old.fraction != fraction;
}
