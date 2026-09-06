import 'dart:io';

import 'package:flutter/foundation.dart';

import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// Basic drag-and-drop routing (Phase 2 · Step 5).
///
/// Rules implemented now:
///  • Drop video/audio file(s) → play instantly (extras are queued).
///  • Drop a `.srt`/`.ass` file → attach as subtitle to the current media.
///  • Drop a folder → scan it for media, queue everything, play the first.
///
/// The full  -grade intelligence (playlist-panel-aware drops, natural
/// episode sorting, smart queuing) lands in Phase 5 on top of this.
class DropHandler {
  DropHandler._();

  /// Handles a list of dropped file-system paths. Returns a short
  /// human-readable summary of what happened (used by the drop overlay),
  /// or `null` if nothing usable was dropped.
  ///
  /// [append] is the playlist panel's verb (playlist_imp.md §7 step 11):
  /// drops INSIDE the panel append to the end of the queue; drops on the
  /// canvas replace (the existing verb). There is no "drop to insert".
  static Future<String?> handleDroppedPaths(
    List<String> paths, {
    bool append = false,
  }) async {
    if (paths.isEmpty) return null;
    final PlayerService service = PlayerService.instance;

    // 1. Subtitles first — attach every dropped subtitle file.
    final List<String> subtitles =
        paths.where(MediaUtils.isSubtitle).toList();
    if (subtitles.isNotEmpty && service.hasMedia.value) {
      for (final String subtitle in subtitles) {
        await service.loadExternalSubtitle(subtitle);
      }
      if (paths.length == subtitles.length) {
        return 'Subtitle loaded';
      }
    }

    // 2. Expand folders into their contained media files.
    final List<String> mediaPaths = <String>[];
    for (final String path in paths) {
      if (FileSystemEntity.isDirectorySync(path)) {
        mediaPaths.addAll(scanFolderForMedia(path));
      } else if (MediaUtils.isMedia(path) || MediaUtils.isPlaylist(path)) {
        mediaPaths.add(path);
      }
    }

    if (mediaPaths.isEmpty) {
      return subtitles.isNotEmpty ? 'Subtitle loaded' : null;
    }

    // 3. Panel drop = append to the END of the queue (M3h); while idle
    // the append simply starts the queue from the top.
    if (append) {
      await service.appendToQueue(
        <QueueItem>[
          for (final String p in mediaPaths) QueueItem.forPath(p),
        ],
      );
      debugPrint(
          '[SALU] appended ${mediaPaths.length} media file(s) via panel drop');
      return 'Queued ${mediaPaths.length} files';
    }

    // 3b. Canvas drop = replace: single file plays directly, multiple
    // files become a queue.
    if (mediaPaths.length == 1) {
      await service.openPath(mediaPaths.first);
    } else {
      await service.openPaths(mediaPaths);
    }
    debugPrint('[SALU] opened ${mediaPaths.length} media file(s) via drop');
    return mediaPaths.length == 1
        ? 'Playing ${MediaUtils.displayName(mediaPaths.first)}'
        : 'Queued ${mediaPaths.length} files';
  }

  /// Shallow-scans a folder for playable media, alphabetically sorted.
  /// Shared by drag-and-drop and the Open Folder… picker.
  /// (Natural episode-order sorting arrives with Phase 5's smart queue.)
  static List<String> scanFolderForMedia(String folderPath) {
    try {
      final List<String> found = Directory(folderPath)
          .listSync()
          .whereType<File>()
          .map((File f) => f.path)
          .where(MediaUtils.isMedia)
          .toList()
        ..sort((String a, String b) =>
            a.toLowerCase().compareTo(b.toLowerCase()));
      return found;
    } catch (error) {
      debugPrint('[SALU] folder scan failed: $error');
      return const <String>[];
    }
  }
}
