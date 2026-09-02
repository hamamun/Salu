import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';

/// The edge-to-edge video canvas (Phase 2 · Step 4).
///
/// Renders raw `mpv` engine frames through [VideoController]. The video is
/// scaled with [BoxFit.contain] so the aspect ratio is never distorted, and
/// letterbox bars use SALU's deep dark gray (never pure black UI, but the
/// video stage itself sits on #121212 for a cinematic look).
class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerService service = PlayerService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.hasMedia,
      builder: (BuildContext context, bool hasMedia, Widget? child) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The mpv canvas — always mounted so the engine stays warm.
            Video(
              controller: service.videoController,
              fit: BoxFit.contain,
              fill: AppColors.videoBackdrop,
              // SALU builds its own IINA-style OSC in Phase 3 — the stock
              // media_kit controls are disabled entirely.
              controls: NoVideoControls,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontFamilyFallback: AppTheme.fontFamilyFallback,
                  fontSize: 38,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
            ),
            // Empty state — shown until the first media is loaded.
            if (!hasMedia) const _EmptyState(),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/images/salu_logo.png',
              width: 120,
              height: 120,
              filterQuality: FilterQuality.high,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                return const Icon(
                  Icons.play_circle_outline,
                  size: 96,
                  color: AppColors.textSecondary,
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'SALU',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 6,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Drop a video or audio file anywhere to start playing',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
