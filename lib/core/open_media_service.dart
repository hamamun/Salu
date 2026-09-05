import 'dart:async';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';

import 'drop_handler.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'url_library_service.dart';

/// The three actions behind SALU's Open control (pill: file · folder · url).
///
/// UI widgets call these and stay dumb; every decision about what to play
/// and how lives here or in [PlayerService].
class OpenMediaService {
  OpenMediaService._();

  static final List<fs.XTypeGroup> _mediaTypeGroups = <fs.XTypeGroup>[
    const fs.XTypeGroup(
      label: 'Media',
      extensions: <String>[
        // Video.
        'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v',
        'mpg', 'mpeg', 'ts', 'm2ts', 'mts', 'vob', '3gp', 'ogv',
        'rm', 'rmvb', 'asf', 'divx',
        // Audio.
        'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'wma',
        'alac', 'aiff', 'ape', 'dsf', 'mka',
        // Playlists.
        'm3u', 'm3u8',
      ],
    ),
    const fs.XTypeGroup(label: 'All files'),
  ];

  /// Open File… — native Windows explorer, multi-select. One file plays
  /// directly; several become a queue starting at the first.
  static Future<void> openFiles() async {
    final List<fs.XFile> files =
        await fs.openFiles(acceptedTypeGroups: _mediaTypeGroups);
    if (files.isEmpty) return;
    final List<String> paths = files
        .map((fs.XFile f) => f.path)
        .where((String p) =>
            MediaUtils.isMedia(p) || MediaUtils.isPlaylist(p))
        .toList();
    if (paths.isEmpty) return;
    final PlayerService player = PlayerService.instance;
    if (paths.length == 1) {
      await player.openPath(paths.first);
    } else {
      await player.openPaths(paths);
    }
  }

  /// Open Folder… — native folder picker; scans the folder for media,
  /// queues everything alphabetically and plays the first item.
  static Future<void> openFolder() async {
    final String? dir = await fs.getDirectoryPath();
    if (dir == null || dir.isEmpty) return;
    final List<String> media = DropHandler.scanFolderForMedia(dir);
    if (media.isEmpty) return;
    final PlayerService player = PlayerService.instance;
    if (media.length == 1) {
      await player.openPath(media.first);
    } else {
      await player.openPaths(media);
    }
    debugPrint('[SALU] opened ${media.length} file(s) from folder');
  }

  /// Plays a network URL and quietly records the outcome in the URL
  /// library (status dot: alive / dead), if that URL is saved.
  static Future<void> playUrl(String url) async {
    final String target = url.trim();
    if (target.isEmpty) return;
    _watchHealth(target);
    await PlayerService.instance.openPath(target);
  }

  /// One-shot health probe: whichever comes first within a 20-second
  /// window — a real duration / advancing position (alive) or an mpv
  /// error that smells like a network failure (dead). Silent otherwise.
  static void _watchHealth(String url) {
    final PlayerService player = PlayerService.instance;
    final List<StreamSubscription<Object?>> subs =
        <StreamSubscription<Object?>>[];
    Timer? timeout;
    bool done = false;

    void finish(UrlHealth? health) {
      if (done) return;
      done = true;
      for (final StreamSubscription<Object?> s in subs) {
        s.cancel();
      }
      timeout?.cancel();
      if (health != null) {
        UrlLibraryService.instance.markHealth(url, health);
      }
    }

    subs.add(player.player.stream.duration.listen((Duration d) {
      if (d > Duration.zero) finish(UrlHealth.alive);
    }));
    // Live streams may never report a duration — motion also means alive.
    subs.add(player.player.stream.position.listen((Duration p) {
      if (p > const Duration(seconds: 1)) finish(UrlHealth.alive);
    }));
    subs.add(player.player.stream.error.listen((String message) {
      final String m = message.toLowerCase();
      if (m.contains('fail') ||
          m.contains('error') ||
          m.contains('refused') ||
          m.contains('not found') ||
          m.contains('unrecognized') ||
          m.contains('timed out') ||
          m.contains('unable')) {
        finish(UrlHealth.dead);
      }
    }));
    timeout = Timer(const Duration(seconds: 20), () => finish(null));
  }
}
