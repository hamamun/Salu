import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/player_service.dart';
import '../../theme/app_theme.dart';

/// Toggle for the Media Inspector (HUD).
class MediaHudController extends ChangeNotifier {
  MediaHudController._();

  static final MediaHudController instance = MediaHudController._();

  bool _visible = false;

  bool get visible => _visible;

  void toggle() {
    _visible = !_visible;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }
}

/// The Media Inspector (Phase 3 · Step 7): a small semi-transparent overlay
/// with live mpv engine stats. Toggled strictly via the 'i' OSC button.
class MediaHud extends StatefulWidget {
  const MediaHud({super.key});

  @override
  State<MediaHud> createState() => _MediaHudState();
}

class _MediaHudState extends State<MediaHud> {
  String? _videoCodec;
  String? _audioCodec;
  String? _fps;
  String? _droppedFrames;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    MediaHudController.instance.addListener(_onToggle);
  }

  @override
  void dispose() {
    MediaHudController.instance.removeListener(_onToggle);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onToggle() {
    if (!mounted) return;
    if (MediaHudController.instance.visible) {
      _refreshMpvStats();
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        _refreshMpvStats();
      });
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _refreshMpvStats() async {
    final PlayerService player = PlayerService.instance;
    final String? vc = await player.getMpvProperty('video-codec');
    final String? ac = await player.getMpvProperty('audio-codec');
    final String? fps = await player.getMpvProperty('container-fps');
    final String? drops = await player.getMpvProperty('frame-drop-count');
    if (!mounted) return;
    setState(() {
      _videoCodec = vc;
      _audioCodec = ac;
      _fps = fps;
      _droppedFrames = drops;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        MediaHudController.instance,
        PlayerService.instance.videoParams,
        PlayerService.instance.audioParams,
        PlayerService.instance.audioBitrate,
        PlayerService.instance.activeHwdec,
      ]),
      builder: (BuildContext context, Widget? child) {
        if (!MediaHudController.instance.visible) {
          return const SizedBox.shrink();
        }
        final PlayerService player = PlayerService.instance;
        final VideoParams? vp = player.videoParams.value;
        final AudioParams? ap = player.audioParams.value;
        final String resolution = player.width.value != null
            ? '${player.width.value}×${player.height.value}'
            : (vp?.w != null ? '${vp!.w}×${vp.h}' : '—');
        final double? bitrate = player.audioBitrate.value;

        return IgnorePointer(
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 56, left: 20),
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Media Inspector',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _row('Video codec', _videoCodec),
                  _row('Resolution', resolution),
                  _row('Frame rate', _fps),
                  _row('Dropped frames', _droppedFrames),
                  _row('Audio codec', _audioCodec),
                  _row(
                    'Audio bitrate',
                    bitrate == null ? '—' : '${bitrate.toStringAsFixed(0)} kbps',
                  ),
                  _row('Sample rate', ap?.sampleRate?.toString()),
                  _row('Hardware decoding', player.activeHwdec.value ?? '…'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
