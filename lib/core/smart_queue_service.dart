import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'media_utils.dart';
import 'natural_sort.dart';

/// Folder auto-play & smart queuing (Phase 5 · Step 2).
///
/// Opening `Episode_1.mp4` should silently line up the rest of the folder —
/// naturally sorted — behind it, exactly like IINA does.
class SmartQueueService {
  SmartQueueService._();

  /// Never queue absurdly large folders (a 5000-file music library would
  /// choke the playlist UI).
  static const int maxQueueSize = 500;

  /// Lists the playable media inside [folderPath], naturally sorted.
  ///
  /// [audioOnly]/[videoOnly] narrow the scan so opening an MP3 doesn't drag
  /// the movie sitting next to it into the queue.
  static List<String> scanFolder(
    String folderPath, {
    bool audioOnly = false,
    bool videoOnly = false,
  }) {
    try {
      final Iterable<String> files = Directory(folderPath)
          .listSync(followLinks: false)
          .whereType<File>()
          .map((File f) => f.path)
          .where((String path) {
        if (audioOnly) return MediaUtils.isAudio(path);
        if (videoOnly) return MediaUtils.isVideo(path);
        return MediaUtils.isMedia(path);
      });
      final List<String> sorted =
          NaturalSort.sorted(files, key: (String path) => p.basename(path));
      return sorted.length > maxQueueSize
          ? sorted.sublist(0, maxQueueSize)
          : sorted;
    } catch (error) {
      debugPrint('[SALU] folder scan failed for "$folderPath": $error');
      return const <String>[];
    }
  }

  /// Builds the queue for a single opened [filePath]: every sibling media
  /// file of the same kind, naturally sorted, with [filePath] included.
  ///
  /// Returns just `[filePath]` when there is nothing else to queue.
  static List<String> queueForFile(String filePath) {
    if (!MediaUtils.isMedia(filePath)) return <String>[filePath];
    if (!File(filePath).existsSync()) return <String>[filePath];

    final String folder = p.dirname(filePath);
    final bool audio = MediaUtils.isAudio(filePath);
    final List<String> siblings = scanFolder(
      folder,
      audioOnly: audio,
      videoOnly: !audio,
    );
    if (siblings.length <= 1) return <String>[filePath];

    // Make sure the opened file is part of the queue even if the scan
    // missed it (case differences, symlinks…).
    final bool contains = siblings.any((String s) => _samePath(s, filePath));
    if (!contains) {
      siblings.add(filePath);
      siblings.sort((String a, String b) =>
          NaturalSort.compare(p.basename(a), p.basename(b)));
    }
    return siblings;
  }

  /// Index of [filePath] inside [queue], or 0 when it isn't present.
  static int indexOf(List<String> queue, String filePath) {
    for (int i = 0; i < queue.length; i++) {
      if (_samePath(queue[i], filePath)) return i;
    }
    return 0;
  }

  /// Finds a sidecar file (subtitle, `.lrc`…) next to [mediaPath] with one of
  /// [extensions], e.g. `movie.mp4` → `movie.srt`.
  static String? findSidecar(String mediaPath, Set<String> extensions) {
    try {
      final String base = p.withoutExtension(mediaPath);
      for (final String ext in extensions) {
        final File candidate = File('$base$ext');
        if (candidate.existsSync()) return candidate.path;
      }
    } catch (_) {
      // Non-file URIs (network streams) simply have no sidecar.
    }
    return null;
  }

  static bool _samePath(String a, String b) =>
      p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase();
}
