import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'media_utils.dart';
import 'natural_sort.dart';
import 'player_service.dart';
import 'smart_queue_service.dart';

/// Where the user released the files.
enum DropZone {
  /// Anywhere over the video canvas → replace and play.
  mainScreen,

  /// Over the Playlist tab of the right panel → append silently.
  playlistPanel,
}

/// What SALU ended up doing with a drop — used for the OSD message.
class DropResult {
  const DropResult(this.message, {this.handled = true});

  static const DropResult ignored = DropResult('', handled: false);

  final String message;
  final bool handled;
}

/// Intelligent drag-and-drop routing (Phase 5 · Step 1).
///
/// IINA-style rules:
///  • Media file on the main screen  → clear the playlist and play it now.
///  • Media file on the playlist panel → append to the bottom, keep playing.
///  • `.srt` / `.ass` on the main screen → attach + enable as a subtitle.
///  • Folder → scan (naturally sorted), replace the playlist, play the first.
class DragDropHandler {
  DragDropHandler._();

  static Future<DropResult> handle(
    List<String> paths, {
    DropZone zone = DropZone.mainScreen,
  }) async {
    if (paths.isEmpty) return DropResult.ignored;
    final PlayerService service = PlayerService.instance;

    final List<String> subtitles = paths.where(MediaUtils.isSubtitle).toList();
    final List<String> folders = paths
        .where((String path) => FileSystemEntity.isDirectorySync(path))
        .toList();
    final List<String> files = paths
        .where((String path) =>
            !FileSystemEntity.isDirectorySync(path) &&
            (MediaUtils.isMedia(path) || MediaUtils.isPlaylist(path)))
        .toList();

    // 1 · Subtitles — attach every dropped subtitle to the current media.
    if (subtitles.isNotEmpty && folders.isEmpty && files.isEmpty) {
      if (!service.hasMedia.value) {
        return const DropResult('Play a video first to add subtitles');
      }
      for (final String subtitle in subtitles) {
        await service.loadExternalSubtitle(subtitle);
      }
      return DropResult(subtitles.length == 1
          ? 'Subtitle added: ${p.basename(subtitles.first)}'
          : 'Added ${subtitles.length} subtitles');
    }

    // 2 · Folders — expand into naturally sorted media queues.
    final List<String> folderMedia = <String>[];
    for (final String folder in folders) {
      folderMedia.addAll(SmartQueueService.scanFolder(folder));
    }

    final List<String> queue = <String>[
      ...NaturalSort.sorted(files, key: (String path) => p.basename(path)),
      ...folderMedia,
    ];

    if (queue.isEmpty) {
      // Subtitles may still have come along with an unplayable file.
      if (subtitles.isNotEmpty && service.hasMedia.value) {
        for (final String subtitle in subtitles) {
          await service.loadExternalSubtitle(subtitle);
        }
        return const DropResult('Subtitle added');
      }
      return const DropResult('Nothing playable in that drop');
    }

    // 3 · Playlist panel drops append without interrupting playback.
    if (zone == DropZone.playlistPanel && service.hasMedia.value) {
      await service.addAllToPlaylist(queue);
      return DropResult(queue.length == 1
          ? 'Added ${MediaUtils.displayName(queue.first)} to playlist'
          : 'Added ${queue.length} items to playlist');
    }

    // 4 · Main-screen drops replace the queue and start playing.
    if (queue.length == 1 && folders.isEmpty) {
      // Single file → let the smart queue line up the rest of its folder.
      await service.openPath(queue.first);
    } else {
      await service.openQueue(queue);
    }

    // Any subtitles dropped alongside the media get attached afterwards.
    for (final String subtitle in subtitles) {
      await service.loadExternalSubtitle(subtitle);
    }

    debugPrint('[SALU] drop opened ${queue.length} item(s) [$zone]');
    return DropResult(queue.length == 1
        ? 'Playing ${MediaUtils.displayName(queue.first)}'
        : 'Playing ${MediaUtils.displayName(queue.first)} · ${queue.length} queued');
  }
}
