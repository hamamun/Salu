import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/audio_display_service.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/album_art_view.dart';
import '../widgets/lyrics_overlay.dart';

/// The edge-to-edge video canvas (Phase 2 · Step 4).
///
/// Renders raw `mpv` engine frames through [VideoController]. The video is
/// scaled with [BoxFit.contain] so the aspect ratio is never distorted, and
/// letterbox bars use SALU's deep dark gray (never pure black UI, but the
/// video stage itself sits on #121212 for a cinematic look).
///
/// For **local audio** the canvas is one of three exclusive modes
/// (lrc.md §2 / L15): lyrics (Flutter) > visualizer (mpv) > metadata +
/// album art (Flutter). Video is untouched — it keeps the plain mpv
/// canvas and subtitles.
///
/// The empty state (before the first media, and while STOPPED — the
/// queue is parked and the canvas returns to the initial window) shows
/// identity only: logo + wordmark, no instruction text (follow.md hard
/// rule 1 — the UI explains itself by design).
class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerService service = PlayerService.instance;
    final AudioDisplayService audio = AudioDisplayService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.hasMedia,
      builder: (BuildContext context, bool hasMedia, Widget? child) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The mpv canvas — mounted only when media is active so
            // ANGLE/D3D11 surfaces aren't created eagerly at startup.
            // For audio this is the visualizer (mode B) or a dark
            // frame that Flutter then covers (modes A and C).
            if (hasMedia)
              Video(
                controller: service.videoController,
                fit: BoxFit.contain,
                fill: AppColors.videoBackdrop,
                // SALU builds its own OSC — the stock media_kit controls
                // are disabled entirely.
                controls: NoVideoControls,
                // D16 (cc.md §5): mpv itself is the ONE subtitle
                // renderer; media_kit's Flutter overlay stays mounted
                // only so its state streams keep breathing (spec lock)
                // and is never shown. The old style block retired with
                // the overlay — the typography pass lives on mpv's side.
                subtitleViewConfiguration:
                    const SubtitleViewConfiguration(visible: false),
              ),
            if (hasMedia)
              ValueListenableBuilder<AudioCanvasMode>(
                valueListenable: audio.mode,
                builder:
                    (BuildContext context, AudioCanvasMode mode, Widget? _) {
                  return switch (mode) {
                    AudioCanvasMode.lyrics => const LyricsOverlay(),
                    AudioCanvasMode.metadata => const AlbumArtView(),
                    AudioCanvasMode.visualizer ||
                    AudioCanvasMode.none =>
                      const SizedBox.shrink(),
                  };
                },
              ),
            // Landing state — until the first media loads, and again
            // while stopped (the parked queue's canvas).
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
        ],
      ),
    );
  }
}
