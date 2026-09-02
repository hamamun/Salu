import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/lyrics_parser.dart';
import '../../core/media_utils.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/lyrics_view.dart';

/// Music Mode overlay (Phase 3 · Step 7).
///
/// Shown when the loaded media has no video stream (MP3/FLAC/…). Displays
/// album art + extracted metadata in the center of the canvas. Phase 7 ·
/// Step 2: when a synced `.lrc` sidecar exists, the scrolling lyrics panel
/// slides in next to the album art.
class MusicModeOverlay extends StatefulWidget {
  const MusicModeOverlay({super.key});

  @override
  State<MusicModeOverlay> createState() => _MusicModeOverlayState();
}

class _MusicModeOverlayState extends State<MusicModeOverlay> {
  String? _title;
  String? _artist;
  String? _album;
  String? _year;
  String? _coverPath;
  String? _loadedUri;

  static const Set<String> _coverNames = <String>{
    'cover', 'folder', 'front', 'album', 'albumart', 'artwork',
  };
  static const Set<String> _imageExts = <String>{
    '.jpg', '.jpeg', '.png', '.webp', '.bmp',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        PlayerService.instance.isMusicMode,
        PlayerService.instance.hasMedia,
        LyricsController.instance,
      ]),
      builder: (BuildContext context, Widget? child) {
        final PlayerService player = PlayerService.instance;
        final bool show = player.isMusicMode.value && player.hasMedia.value;
        if (!show) return const SizedBox.shrink();

        final String? uri = player.currentMediaUri;
        if (uri != null && uri != _loadedUri) {
          _loadedUri = uri;
          WidgetsBinding.instance.addPostFrameCallback((_) => _load(uri));
        }

        // IINA music mode: a dedicated play/pause control centered under the
        // artwork. The art + text block is IgnorePointer-wrapped so the rest
        // of the canvas keeps the classic "click anywhere to toggle"
        // behaviour while the button itself stays live.
        final Widget metaColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _AlbumArt(path: _coverPath),
                  const SizedBox(height: 28),
                  Text(
                    _title ?? player.currentTitle.value ?? 'Unknown Track',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textSecondary),
                  ),
                  if (_album != null && _album!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '${_album!}${(_year != null && _year!.isNotEmpty) ? ' · $_year' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _MusicPlayPause(player: player),
          ],
        );

        // The play/pause button is the only interactive element inside the
        // meta column (see _MusicPlayPause); everything around it lets the
        // click fall through to the canvas-level play/pause gesture.
        if (!LyricsController.instance.visible) {
          return Center(child: metaColumn);
        }

        // Phase 7: album art shifts left, the scrolling lyrics take the
        // right half of the canvas. Only the lyrics panel and the button
        // are interactive — clicking anywhere else falls through.
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              metaColumn,
              const SizedBox(width: 48),
              LyricsView(width: _lyricsWidth(context), height: _lyricsHeight(context)),
            ],
          ),
        );
      },
    );
  }

  double _lyricsWidth(BuildContext context) {
    final double screen = MediaQuery.of(context).size.width;
    return (screen * 0.34).clamp(340.0, 520.0).toDouble();
  }

  double _lyricsHeight(BuildContext context) {
    final double screen = MediaQuery.of(context).size.height;
    return (screen - 210).clamp(280.0, 520.0).toDouble();
  }

  Future<void> _load(String uri) async {
    final String path = uri.replaceFirst(RegExp(r'^file:///'), '');
    final String? cover = _findCover(path);
    final PlayerService player = PlayerService.instance;

    final String? title = await player.getMpvProperty('metadata/by-key/Title');
    final String? artist = await player.getMpvProperty('metadata/by-key/Artist');
    final String? album = await player.getMpvProperty('metadata/by-key/Album');
    final String? year = await player.getMpvProperty('metadata/by-key/Date');

    if (!mounted) return;
    setState(() {
      _coverPath = cover;
      _title = (title != null && title.isNotEmpty)
          ? title
          : MediaUtils.displayName(path);
      _artist = (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist';
      _album = (album != null && album.isNotEmpty) ? album : p.basename(p.dirname(path));
      _year = year;
    });
  }

  String? _findCover(String mediaPath) {
    try {
      final Directory dir = Directory(p.dirname(mediaPath));
      if (!dir.existsSync()) return null;
      final List<FileSystemEntity> entries = dir.listSync().whereType<File>().toList();

      // Preferred: an image whose name is a known cover-art keyword.
      for (final FileSystemEntity e in entries) {
        final String name = p.basenameWithoutExtension(e.path).toLowerCase();
        if (_coverNames.contains(name) && _imageExts.contains(p.extension(e.path).toLowerCase())) {
          return e.path;
        }
      }
      // Fallback: the first image file in the folder.
      for (final FileSystemEntity e in entries) {
        if (_imageExts.contains(p.extension(e.path).toLowerCase())) {
          return e.path;
        }
      }
    } catch (error) {
      debugPrint('[SALU] cover scan failed: $error');
    }
    return null;
  }
}

/// Circular play/pause button under the album art (IINA music-mode style).
class _MusicPlayPause extends StatelessWidget {
  const _MusicPlayPause({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player.playing,
      builder: (BuildContext context, Widget? child) {
        final bool playing = player.playing.value;
        return Material(
          color: AppColors.glass,
          shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(player.playOrPause()),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration placeholder = BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
    );
    if (path == null) {
      return Container(
        width: 200,
        height: 200,
        decoration: placeholder,
        child: const Icon(Icons.music_note_rounded,
            size: 72, color: AppColors.textSecondary),
      );
    }
    return Container(
      width: 200,
      height: 200,
      decoration: placeholder,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(path!),
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
            return const Icon(Icons.music_note_rounded,
                size: 72, color: AppColors.textSecondary);
          },
        ),
      ),
    );
  }
}
