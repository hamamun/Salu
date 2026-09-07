import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'folder_autoload_service.dart';
import 'media_utils.dart';
import 'player_service.dart';

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
  static Future<String?> handleDroppedPaths(List<String> paths) async {
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

    // 2. Expand folders into their contained media files and sort the
    //    batch into the folder's own order (one gesture = one block, §5).
    final List<String> mediaPaths = collectPlayable(paths);

    if (mediaPaths.isEmpty) {
      return subtitles.isNotEmpty ? 'Subtitle loaded' : null;
    }

    // 3. Play: single file plays directly, multiple files become a queue.
    if (mediaPaths.length == 1) {
      await service.openPath(mediaPaths.first);
      // Folder auto-load (autoload_imp.md §2): a single dropped file may
      // grow its own folder queue behind the playing file. Never fires
      // on a batch, and never on the append path (panel-open drops).
      unawaited(FolderAutoloadService.instance
          .maybeExpand(mediaPaths.first));
    } else {
      await service.openPaths(mediaPaths);
    }
    debugPrint('[SALU] opened ${mediaPaths.length} media file(s) via drop');
    return mediaPaths.length == 1
        ? 'Playing ${MediaUtils.displayName(mediaPaths.first)}'
        : 'Queued ${mediaPaths.length} files';
  }

  /// Shallow-scans a folder for playable media, natural episode order
  /// (folder first, then the name — `ep2` before `ep10`, playlist_imp.md
  /// §5's one-gesture = one-block rule). Shared by drag-and-drop, the
  /// Open Folder… picker and folder auto-load.
  ///
  /// [kind] narrows the scan to one kind (autoload_imp.md §1 lock 4:
  /// video → videos only, audio → audio only); omitted keeps the
  /// original video+audio behaviour every existing caller relies on.
  static List<String> scanFolderForMedia(String folderPath,
      {MediaKind? kind}) {
    try {
      final bool Function(String) accept = switch (kind) {
        MediaKind.video => MediaUtils.isVideo,
        MediaKind.audio => MediaUtils.isAudio,
        null => MediaUtils.isMedia,
      };
      final List<String> found = Directory(folderPath)
          .listSync()
          .whereType<File>()
          .map((File f) => f.path)
          .where(accept)
          .toList();
      found.sort(MediaUtils.naturalPathCompare);
      return found;
    } catch (error) {
      debugPrint('[SALU] folder scan failed: $error');
      return const <String>[];
    }
  }

  /// Expands folders into their contained media and sorts the whole batch
  /// into the folder's own order (folder first, then name, natural).
  /// The shell's multi-select array order is never trusted (§5).
  static List<String> collectPlayable(List<String> paths) {
    final List<String> mediaPaths = <String>[];
    for (final String path in paths) {
      if (FileSystemEntity.isDirectorySync(path)) {
        mediaPaths.addAll(scanFolderForMedia(path));
      } else if (MediaUtils.isMedia(path) || MediaUtils.isPlaylist(path)) {
        mediaPaths.add(path);
      }
    }
    mediaPaths.sort(MediaUtils.naturalPathCompare);
    return mediaPaths;
  }

  /// Appends a dropped batch to the (open) playlist panel — the queue is
  /// never replaced, the current item is untouched. Folders are expanded
  /// and the batch sorted (§5); only the inside of the appended block is
  /// ordered. Returns `true` when anything was appended.
  static Future<bool> appendDroppedToQueue(List<String> paths) async {
    // 1. Attach any dropped subtitle files if media is active.
    final List<String> subtitles =
        paths.where(MediaUtils.isSubtitle).toList();
    if (subtitles.isNotEmpty && PlayerService.instance.hasMedia.value) {
      for (final String subtitle in subtitles) {
        await PlayerService.instance.loadExternalSubtitle(subtitle);
      }
    }

    // 2. Expand folders and collect playable media files.
    final List<String> mediaPaths = collectPlayable(paths);
    if (mediaPaths.isEmpty) return subtitles.isNotEmpty;
    await PlayerService.instance.appendToQueue(mediaPaths);
    debugPrint('[SALU] appended ${mediaPaths.length} file(s) to the queue');
    return true;
  }
}
