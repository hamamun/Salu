import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

import '../../core/app_prefs.dart';
import '../../core/media_utils.dart';
import '../../core/player_service.dart';
import '../../core/thumbnail_service.dart';
import '../../theme/app_theme.dart';
import '../managers/ui_visibility_manager.dart';
import 'osc_bar_anchor.dart';

/// The seek bar (Phase 3 · Step 3).
///
/// • Click anywhere → instant seek to that point.
/// • Drag → smooth scrub (seek commits on release).
/// • Hover → a floating preview box follows the cursor showing the target
///   timestamp and, for video, a real frame thumbnail. The thumbnail is
///   captured by a headless mpv instance ([ThumbnailService]) so the visible
///   playback position is never disturbed.
/// • Buffered region is drawn in a lighter shade behind the played region.
class TimelineSlider extends StatefulWidget {
  const TimelineSlider({super.key});

  @override
  State<TimelineSlider> createState() => _TimelineSliderState();
}

class _TimelineSliderState extends State<TimelineSlider> {
  final PlayerService _player = PlayerService.instance;
  final ThumbnailService _thumbs = ThumbnailService.instance;

  /// Fraction (0–1) being scrubbed; null when not dragging.
  double? _dragFraction;

  /// Fraction (0–1) the mouse currently hovers over; null when not hovering.
  double? _hoverFraction;

  // Hover thumbnail state.
  Timer? _hoverDebounce;
  int _requestId = 0;
  bool _thumbLoading = false;
  Uint8List? _thumbBytes;
  Duration? _thumbTime;

  /// Single reusable overlay entry for the floating hover preview.
  OverlayEntry? _previewEntry;

  @override
  void dispose() {
    _hoverDebounce?.cancel();
    _removePreview();
    super.dispose();
  }

  void _seekToFraction(double fraction) {
    final Duration d = _player.duration.value;
    if (d <= Duration.zero) return;
    final double f = fraction.clamp(0.0, 1.0).toDouble();
    _player.seek(Duration(milliseconds: (d.inMilliseconds * f).round()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _player.position,
        _player.duration,
        _player.buffered,
      ]),
      builder: (BuildContext context, Widget? child) {
        final Duration duration = _player.duration.value;
        final bool live = duration <= Duration.zero;
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            final double durationMs = duration.inMilliseconds.toDouble();
            final double positionMs = _player.position.value.inMilliseconds.toDouble();
            final double bufferedMs = _player.buffered.value.inMilliseconds.toDouble();

            final double fraction = live || durationMs <= 0
                ? 0
                : (_dragFraction ?? (positionMs / durationMs).clamp(0.0, 1.0).toDouble());
            final double bufferFraction = live || durationMs <= 0
                ? 0
                : (bufferedMs / durationMs).clamp(0.0, 1.0).toDouble();

            return MouseRegion(
              onHover: live
                  ? null
                  : (PointerHoverEvent e) {
                      setState(() {
                        _hoverFraction =
                            (e.localPosition.dx / width).clamp(0.0, 1.0).toDouble();
                      });
                      _scheduleThumbnail();
                    },
              onExit: live ? null : (_) => _onHoverEnd(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: live
                    ? null
                    : (TapDownDetails d) {
                        setState(() {
                          _dragFraction =
                              (d.localPosition.dx / width).clamp(0.0, 1.0).toDouble();
                        });
                        _seekToFraction(_dragFraction!);
                      },
                onTapUp: (_) => setState(() => _dragFraction = null),
                onTapCancel: () => setState(() => _dragFraction = null),
                onHorizontalDragStart: live
                    ? null
                    : (DragStartDetails d) {
                        UiVisibilityManager.instance.lockInteraction();
                        setState(() {
                          _dragFraction =
                              (d.localPosition.dx / width).clamp(0.0, 1.0).toDouble();
                        });
                      },
                onHorizontalDragUpdate: live
                    ? null
                    : (DragUpdateDetails d) => setState(() {
                          _dragFraction =
                              (d.localPosition.dx / width).clamp(0.0, 1.0).toDouble();
                        }),
                onHorizontalDragEnd: live
                    ? null
                    : (DragEndDetails d) {
                        final double? f = _dragFraction;
                        if (f != null) _seekToFraction(f);
                        setState(() => _dragFraction = null);
                        UiVisibilityManager.instance.unlockInteraction();
                      },
                onHorizontalDragCancel: () {
                  setState(() => _dragFraction = null);
                  UiVisibilityManager.instance.unlockInteraction();
                },
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Small in-track timestamp box for audio-only media
                      // (no frame to thumbnail, so no big floating box).
                      if (_hoverFraction != null && !live && !_player.hasVideo)
                        _buildAudioTimestamp(width, duration),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 26,
                        child: _buildTrack(width, fraction, bufferFraction),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Hover preview ──────────────────────────────────────────────────────

  void _scheduleThumbnail() {
    final double fraction = _hoverFraction!;
    final Duration duration = _player.duration.value;
    if (duration <= Duration.zero) return;
    final Duration hoverTime =
        Duration(milliseconds: (duration.inMilliseconds * fraction).round());
    _thumbTime = hoverTime;

    final String? uri = _player.currentMediaUri;
    final bool hasVideo = _player.hasVideo;

    _hoverDebounce?.cancel();

    if (hasVideo && uri != null) {
      setState(() {
        _thumbLoading = true;
        _thumbBytes = null;
      });
      _updatePreviewOverlay();
      final int id = ++_requestId;
      _hoverDebounce = Timer(const Duration(milliseconds: 180), () async {
        final Uint8List? bytes = await _thumbs.captureFrame(uri, hoverTime);
        if (!mounted || id != _requestId) return;
        setState(() {
          _thumbLoading = false;
          _thumbBytes = bytes;
        });
        _updatePreviewOverlay();
      });
    } else {
      // Audio-only media → the small in-track box handles the timestamp.
      _thumbBytes = null;
      _thumbLoading = false;
      _removePreview();
    }
  }

  void _onHoverEnd() {
    _hoverDebounce?.cancel();
    _requestId++;
    _thumbBytes = null;
    _thumbLoading = false;
    setState(() => _hoverFraction = null);
    _removePreview();
  }

  void _updatePreviewOverlay() {
    final double? fraction = _hoverFraction;
    final OverlayState? overlay = Overlay.maybeOf(context);
    final bool live = _player.duration.value <= Duration.zero;
    if (fraction == null || overlay == null || live || !_player.hasVideo) {
      _removePreview();
      return;
    }
    if (_previewEntry == null) {
      _previewEntry = OverlayEntry(builder: (BuildContext _) => _buildOverlayPreview());
      overlay.insert(_previewEntry!);
    } else {
      _previewEntry!.markNeedsBuild();
    }
  }

  void _removePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
  }

  /// Builds the floating preview, positioned relative to the OSC bar so it
  /// renders over the video area (above a bottom-anchored bar, below a
  /// top-anchored one) and is never clipped by the bar's rounded corners.
  Widget _buildOverlayPreview() {
    final double fraction = _hoverFraction ?? 0;
    const double previewWidth = 176.0;
    const double previewHeight = 121.0;

    final Size screen = MediaQuery.sizeOf(context);
    final RenderBox? sliderBox = context.findRenderObject() as RenderBox?;
    final RenderBox? barBox = oscBarKey.currentContext?.findRenderObject() as RenderBox?;

    double left;
    if (sliderBox != null && sliderBox.attached) {
      final Offset origin = sliderBox.localToGlobal(Offset.zero);
      left = origin.dx + sliderBox.size.width * fraction - previewWidth / 2;
    } else {
      left = (screen.width - previewWidth) / 2;
    }
    left = left.clamp(0.0, screen.width - previewWidth).toDouble();

    final bool topAnchored = AppPrefs.instance.oscLayout == OscLayout.top;
    double top;
    if (barBox != null && barBox.attached) {
      final Offset barOrigin = barBox.localToGlobal(Offset.zero);
      top = topAnchored
          ? barOrigin.dy + barBox.size.height + 10
          : barOrigin.dy - previewHeight - 10;
    } else {
      top = topAnchored ? 60 : screen.height - previewHeight - 60;
    }
    top = top.clamp(0.0, screen.height - previewHeight).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: previewWidth,
      height: previewHeight,
      child: IgnorePointer(child: _buildPreviewContent(previewWidth)),
    );
  }

  Widget _buildPreviewContent(double width) {
    final Duration time = _thumbTime ?? Duration.zero;
    final String label = MediaUtils.formatDuration(time);

    final Widget imageArea = _thumbBytes != null
        ? Image.memory(
            _thumbBytes!,
            width: width,
            height: 99,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          )
        : Container(
            width: width,
            height: 99,
            color: Colors.black,
            child: _thumbLoading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : null,
          );

    // 99px image + 22px timestamp = 121px, matching the overlay's height.
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE6262626),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: imageArea,
            ),
            Container(
              height: 22,
              alignment: Alignment.center,
              color: Colors.black54,
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small timestamp-only box directly above the cursor (audio files).
  Widget _buildAudioTimestamp(double width, Duration duration) {
    final double hoverX = width * _hoverFraction!;
    final double previewWidth = 84.0;
    final double left =
        (hoverX - previewWidth / 2).clamp(0.0, width - previewWidth).toDouble();
    final Duration hoverTime =
        Duration(milliseconds: (duration.inMilliseconds * _hoverFraction!).round());
    return Positioned(
      left: left,
      top: 0,
      child: Container(
        width: previewWidth,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          MediaUtils.formatDuration(hoverTime),
          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildTrack(double width, double fraction, double bufferFraction) {
    final bool interactive = _hoverFraction != null || _dragFraction != null;
    return Stack(
      alignment: Alignment.centerLeft,
      children: <Widget>[
        // Base track.
        Positioned(
          left: 0,
          right: 0,
          top: 11,
          bottom: 11,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // Buffered region.
        Positioned(
          left: 0,
          top: 11,
          bottom: 11,
          width: width * bufferFraction,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // Played region.
        Positioned(
          left: 0,
          top: 11,
          bottom: 11,
          width: width * fraction,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // Thumb (shown while hovering or scrubbing).
        if (interactive)
          Positioned(
            left: (width * fraction - 6).clamp(0.0, width - 12).toDouble(),
            top: 7,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
