import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'smart_queue_service.dart';

/// One timestamped line of a `.lrc` document (Phase 7 · Step 1).
///
/// [time] is the *raw* stamp written in the file. [LyricsDocument] applies
/// the `[offset:…]` tag on top of it when the player needs the moment the
/// line should actually be displayed.
class LyricsLine {
  const LyricsLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

/// A fully parsed `.lrc` file: metadata tags + chronologically sorted lines.
class LyricsDocument {
  const LyricsDocument({
    required this.lines,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.author = '',
    this.offset = Duration.zero,
  });

  /// Synced lyric lines, sorted by [LyricsLine.time] (ascending).
  final List<LyricsLine> lines;

  /// `[ti:]`, `[ar:]`, `[al:]`, `[by:]` metadata (may be empty).
  final String title;
  final String artist;
  final String album;
  final String author;

  /// `[offset:+ms]` — a positive value shifts the display of every line
  /// *earlier* by that amount (the LRC de-facto convention).
  final Duration offset;

  bool get isEmpty => lines.isEmpty;

  bool get isNotEmpty => lines.isNotEmpty;

  /// The moment [line] should be shown, [offset] already folded in.
  Duration displayTime(LyricsLine line) => line.time - offset;

  /// Index of the line currently being sung at [position], or `-1` when the
  /// song has not reached the first stamp yet. Binary search — cheap even
  /// for thousand-line karaoke files.
  int activeIndexAt(Duration position) {
    if (lines.isEmpty) return -1;
    final Duration probe = position + offset;
    int lo = 0;
    int hi = lines.length - 1;
    int ans = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (lines[mid].time <= probe) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

/// Standard `.lrc` parser (Phase 7 · Step 1).
///
/// Supported syntax — the whole de-facto LRC grammar:
///  * `[mm:ss.xx] text` — stamp with centiseconds (`.x`/`.xx`/`.xxx` also OK)
///  * `[mm:ss.xx][mm:ss.xx] text` — one line repeated at several stamps
///  * `[ti:][ar:][al:][by:][au:]` — metadata tags (ignored lines otherwise)
///  * `[offset:+500]` — global millisecond shift
class LyricsParser {
  LyricsParser._();

  /// Extensions the smart-matcher looks for beside the audio file.
  static const Set<String> lyricsExtensions = <String>{'.lrc'};

  static final RegExp _stamp =
      RegExp(r'^\[(\d{1,4}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _meta = RegExp(r'^\[([a-zA-Z][a-zA-Z0-9_]*):([^\]]*)\]$');

  /// Parses a complete `.lrc` document. Never throws — malformed lines are
  /// silently skipped, exactly like most players do.
  static LyricsDocument parse(String source) {
    final List<LyricsLine> lines = <LyricsLine>[];
    String title = '';
    String artist = '';
    String album = '';
    String author = '';
    int offsetMs = 0;

    for (final String rawLine in const LineSplitter().convert(source)) {
      String line = rawLine.trim();
      if (line.isEmpty) continue;

      // Collect every leading [mm:ss.xx] stamp, then the rest is the text.
      final List<int> stamps = <int>[];
      while (true) {
        final RegExpMatch? match = _stamp.firstMatch(line);
        if (match == null) break;
        stamps.add(_stampToMs(match));
        line = line.substring(match.end).trim();
      }

      if (stamps.isNotEmpty) {
        if (line.isEmpty) continue; // Pure spacer line.
        for (final int ms in stamps) {
          lines.add(LyricsLine(
            time: Duration(milliseconds: ms),
            text: line,
          ));
        }
        continue;
      }

      // Metadata tags only matter when the line has no stamps.
      final RegExpMatch? meta = _meta.firstMatch(line);
      if (meta == null) continue; // Untimed plain text — ignored.
      final String key = meta.group(1)!.toLowerCase();
      final String value = meta.group(2)!.trim();
      switch (key) {
        case 'ti':
          title = value;
        case 'ar':
          artist = value;
        case 'al':
          album = value;
        case 'by':
        case 'au':
          author = value;
        case 'offset':
          offsetMs = int.tryParse(value.replaceAll('+', '')) ?? 0;
      }
    }

    lines.sort((LyricsLine a, LyricsLine b) => a.time.compareTo(b.time));
    return LyricsDocument(
      lines: lines,
      title: title,
      artist: artist,
      album: album,
      author: author,
      offset: Duration(milliseconds: offsetMs),
    );
  }

  /// Converts `[mm:ss.x]` groups into milliseconds. One digit after the dot
  /// counts tenth-of-a-second, two digits hundredths, three plain ms.
  static int _stampToMs(RegExpMatch match) {
    final int minutes = int.parse(match.group(1)!);
    final int seconds = int.parse(match.group(2)!);
    final String? frac = match.group(3);
    int ms = 0;
    if (frac != null) {
      final int value = int.parse(frac);
      ms = switch (frac.length) {
        1 => value * 100,
        2 => value * 10,
        _ => value,
      };
    }
    return minutes * 60000 + seconds * 1000 + ms;
  }

  /// Phase 7 · Step 1 "Smart Matching": `song.mp3` → `song.lrc` sitting in
  /// the same folder (reuses the Phase 5 sidecar locator).
  static String? findSidecarLyrics(String mediaPath) =>
      SmartQueueService.findSidecar(mediaPath, lyricsExtensions);

  /// Loads the sidecar for [mediaPath], or returns `null` when there is no
  /// `.lrc` next to it (or it cannot be read).
  static LyricsDocument? loadForMediaSync(String mediaPath) {
    final String? sidecar = findSidecarLyrics(mediaPath);
    if (sidecar == null) return null;
    try {
      // Tiny text files — a synchronous read beats an isolate round-trip.
      final LyricsDocument doc = parse(File(sidecar).readAsStringSync());
      return doc.isEmpty ? null : doc;
    } catch (error) {
      debugPrint('[SALU] lyrics parse failed for "$sidecar": $error');
      return null;
    }
  }
}

/// Global holder of the lyrics for the media currently loaded (Phase 7).
///
/// [PlayerService] pokes [onMediaOpened] whenever a new queue item starts;
/// the widget layer ([LyricsView]) listens to this notifier.
class LyricsController extends ChangeNotifier {
  LyricsController._();

  static final LyricsController instance = LyricsController._();

  LyricsDocument? _document;
  String? _mediaUri;
  bool _hiddenByUser = false;
  int _generation = 0;

  LyricsDocument? get document => _document;

  String? get mediaUri => _mediaUri;

  bool get hasLyrics => _document != null;

  /// True when the scrolling lyrics panel should be shown over Music Mode.
  bool get visible => hasLyrics && !_hiddenByUser;

  /// Called by [PlayerService] on every new media item. Silently looks for a
  /// `.lrc` sidecar (song.mp3 → song.lrc) and swaps the live document.
  void onMediaOpened(String uri) {
    _mediaUri = uri;
    _document = null;
    _hiddenByUser = false;
    _generation++;
    final int gen = _generation;
    unawaited(_load(uri, gen));
    notifyListeners();
  }

  Future<void> _load(String uri, int generation) async {
    try {
      final String path = SmartQueueService.toLocalPath(uri);
      final LyricsDocument? doc = LyricsParser.loadForMediaSync(path);
      if (generation != _generation || _mediaUri != uri) return;
      if (doc != null) _document = doc;
      notifyListeners();
    } catch (error) {
      debugPrint('[SALU] lyrics load failed: $error');
    }
  }

  /// Hides the panel for the current track (the lyrics stay loaded so the
  /// view can be reopened instantly).
  void hide() {
    if (!_hiddenByUser) {
      _hiddenByUser = true;
      notifyListeners();
    }
  }

  void show() {
    if (_hiddenByUser) {
      _hiddenByUser = false;
      notifyListeners();
    }
  }

  void toggle() => _hiddenByUser ? show() : hide();

  /// Clears everything (media stopped / app shutdown).
  void clear() {
    _generation++;
    _document = null;
    _mediaUri = null;
    _hiddenByUser = false;
    notifyListeners();
  }

  /// Convenience: filename of the sidecar that produced the current doc.
  String get lyricsFileName {
    final String? uri = _mediaUri;
    if (uri == null) return '';
    final String? sidecar =
        LyricsParser.findSidecarLyrics(SmartQueueService.toLocalPath(uri));
    return sidecar == null ? '' : p.basename(sidecar);
  }
}
