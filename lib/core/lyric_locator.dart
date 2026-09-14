import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'lyric_parser.dart';
import 'media_utils.dart';

/// Sibling `.lrc` discovery (lrc.md L10 / L10a / L23).
///
/// SALU never "opens" a lyrics file — it finds it next to the audio,
/// regardless of how the audio landed (Open File…, Open Folder…, or
/// drag & drop). The `.lrc` is never queued and never a drop target.
class LyricLocator {
  LyricLocator._();

  /// Exact `song.lrc` first, then any `song.<lang>.lrc` (first in
  /// natural order). `null` when nothing matches.
  static String? findSidecar(String audioPath) {
    if (audioPath.contains('://')) return null;
    final String canonical = MediaUtils.canonicalPath(audioPath);
    final String dir = p.dirname(canonical);
    final String base = p.basenameWithoutExtension(canonical);
    if (base.isEmpty) return null;

    Directory folder;
    try {
      folder = Directory(dir);
      if (!folder.existsSync()) return null;
    } catch (_) {
      return null;
    }

    final String exactName = '$base.lrc'.toLowerCase();
    final RegExp lang = RegExp(
      '^${RegExp.escape(base)}\\.([A-Za-z]{2,3})\\.lrc\$',
      caseSensitive: false,
    );

    String? exact;
    final List<String> langs = <String>[];
    try {
      for (final FileSystemEntity e in folder.listSync(followLinks: false)) {
        if (e is! File) continue;
        final String name = p.basename(e.path);
        if (name.toLowerCase() == exactName) {
          exact = e.path;
          continue;
        }
        if (lang.hasMatch(name)) langs.add(e.path);
      }
    } catch (_) {
      return null;
    }

    if (exact != null) return MediaUtils.canonicalPath(exact);
    if (langs.isEmpty) return null;
    langs.sort(
      (String a, String b) =>
          MediaUtils.naturalCompare(p.basename(a), p.basename(b)),
    );
    return MediaUtils.canonicalPath(langs.first);
  }

  /// Reads and parses the sidecar. `null` when the file is missing,
  /// unreadable, or has no timed lines (a header-only file is not
  /// "lyrics available").
  static LyricDocument? load(String audioPath) {
    final String? sidecar = findSidecar(audioPath);
    if (sidecar == null) return null;
    try {
      final File file = File(sidecar);
      if (!file.existsSync()) return null;
      final List<int> bytes = file.readAsBytesSync();
      final String text = _decode(bytes);
      final LyricDocument doc = LrcParser.parse(text);
      return doc.isEmpty ? null : doc;
    } catch (_) {
      return null;
    }
  }

  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}
