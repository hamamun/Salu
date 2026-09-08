import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ui/osd/osd_controller.dart';
import 'drop_handler.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'settings_service.dart';

/// Folder auto-load (binding spec: `autoload_imp.md`).
///
/// When exactly ONE local media file is loaded — Open File… resolving
/// to a single pick, a single-file drop, or Explorer's open-with — the
/// file's own folder is scanned and the matching files are queued
/// around the one playing. Two locked rules shape everything here:
///
///  * **Playback never waits.** The picked file opens exactly as Phase
///    A does; [maybeExpand] runs behind it and the picked media is
///    never reopened (lock 7 — the single sanctioned exception to
///    playlist_imp.md §1 lock 5's "a fresh load starts at row 0").
///  * **Nothing is ever guessed about content.** Matching is folder
///    membership (mode `allVideos`) or file-name shape (mode
///    `sameSeries`, §3.2). Level-3 similarity is dropped, permanently.
///
/// Every failure mode is a silent no-op: the picked file is already
/// playing, which was the point of the user's gesture.
class FolderAutoloadService {
  FolderAutoloadService._internal();

  /// The one and only auto-load service for the whole app.
  static final FolderAutoloadService instance =
      FolderAutoloadService._internal();

  /// autoload_imp.md §2's trigger — call right after the picked file's
  /// `openPath`, at any of the three single-file entry points and
  /// nowhere else (multi-picks, Open Folder…, URLs and `.m3u` files
  /// never reach here). Fire-and-forget (`unawaited`).
  Future<void> maybeExpand(String pickedPath) async {
    final FolderAutoloadMode mode =
        SettingsService.instance.folderAutoloadMode.value;
    if (mode == FolderAutoloadMode.off) return;

    // Locked exclusions (§1 lock 3): streams/URLs and playlist files
    // never trigger — a URL's folder doesn't exist and an .m3u already
    // IS the list.
    if (pickedPath.contains('://')) return;
    if (!MediaUtils.isMedia(pickedPath)) return;

    final PlayerService player = PlayerService.instance;
    final QueueService queue = QueueService.instance;

    // The queue `openPath` just installed must still stand as the
    // untouched singleton — anything else means the user has already
    // moved on, and growing would trample their intent.
    final String canon = MediaUtils.canonicalPath(pickedPath);
    if (_queueMovedOn(queue, canon)) return;

    // Locks 4 & 5: the picked file's own folder only (never recursive),
    // same kind only (a video never swallows the MP3s beside it — and
    // a track still picks up its album).
    final MediaKind kind =
        MediaUtils.isVideo(canon) ? MediaKind.video : MediaKind.audio;
    final String folder = p.dirname(canon);
    List<String> found =
        DropHandler.scanFolderForMedia(folder, kind: kind);

    // Lock 9: name shape only; no matches → NO fallback to whole folder
    // (that would be the surprise this mode exists to prevent).
    if (mode == FolderAutoloadMode.sameSeries) {
      final String shape = seriesShape(canon);
      found = found.where((String f) => seriesShape(f) == shape).toList();
    }
    if (found.length <= 1) return; // only itself → nothing to do

    final int pickedRow = found
        .indexWhere((String f) => MediaUtils.canonicalPath(f) == canon);
    if (pickedRow < 0) return;

    // Same singleton re-check, kept right before the (async) surgery
    // even though the scan above is synchronous today — the guard is
    // cheap and the race it fences is real.
    if (_queueMovedOn(queue, canon)) return;

    final bool grew = await player.insertAroundCurrent(
      before: found.sublist(0, pickedRow),
      after: found.sublist(pickedRow + 1),
    );
    if (!grew) return;

    // §4's whisper: one transient status card, never interactive.
    final String folderName = p.basename(folder);
    OsdController.instance.show(OsdAutoloadCard(
      count: found.length,
      audio: kind == MediaKind.audio,
      folder: folderName.isEmpty ? folder : folderName,
    ));
    debugPrint('[SALU] folder auto-load: ${found.length} item(s) queued '
        'around "$canon"');
  }

  /// True when the queue is no longer the untouched singleton the
  /// single-file load of [canon] installed.
  static bool _queueMovedOn(QueueService queue, String canon) =>
      queue.length != 1 || queue.items.value.first.url != canon;

  /// The name shape two files must share to count as "the same series"
  /// (autoload_imp.md §3.2): case-folded, separators (`space . _ -`)
  /// unified, every digit run collapsed to a single `#`. Deterministic
  /// and pure — `Show.S01E03` → `show_s#e#`, so it matches
  /// `Show S01E01` but never `Show.1080p` (`show_#p`).
  static String seriesShape(String path) {
    final String name = MediaUtils.displayName(path).toLowerCase();
    return name
        .replaceAll(RegExp(r'[\s._\-]+'), '_')
        .replaceAll(RegExp(r'\d+'), '#');
  }
}
