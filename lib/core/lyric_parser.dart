// Direct `.lrc` parsing (lrc.md L8 / L9 / L24). Lyrics are not
// subtitles: this never produces SRT and never talks to mpv.
//
// Handles the real-world quirks the contract names:
//   · multiple timestamps on one line (`[00:10.00][00:20.00] line`)
//   · enhanced LRC word timing (`<00:10.00>` inline) — stripped
//   · header tags (`[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[offset:]`)
//   · blank lines and lines without timestamps
//   · `[offset:]` is APPLIED (milliseconds, signed) to every timestamp

/// One timed lyric line after `[offset:]` has been applied.
class LyricLine {
  const LyricLine({required this.timestamp, required this.text});

  /// When this line becomes current, already shifted by the file's
  /// `[offset:]`.
  final Duration timestamp;

  final String text;
}

/// A parsed `.lrc` document. [lines] is sorted by timestamp and never
/// includes header-only content.
class LyricDocument {
  const LyricDocument({
    this.title,
    this.artist,
    this.album,
    this.by,
    this.offset = Duration.zero,
    this.lines = const <LyricLine>[],
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? by;

  /// The file's declared `[offset:]`, already applied to [lines].
  final Duration offset;

  final List<LyricLine> lines;

  bool get isEmpty => lines.isEmpty;

  bool get isNotEmpty => lines.isNotEmpty;
}

/// Parses an LRC body. Encoding is the caller's job (the locator reads
/// the file as UTF-8 with a Latin-1 fallback).
class LrcParser {
  LrcParser._();

  /// Header tag names (lrc.md L9). Anything else in `[…]` that looks
  /// like `mm:ss` is a timestamp.
  static const Set<String> _headers = <String>{
    'ti',
    'ar',
    'al',
    'by',
    'offset',
    'length',
    're',
    've',
    'id',
  };

  static final RegExp _timestamp = RegExp(
    r'\[(?:(\d{1,2}):)?(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  static final RegExp _wordTime = RegExp(
    r'<(?:(\d{1,2}):)?(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>',
  );

  static final RegExp _header = RegExp(
    r'^\[([A-Za-z]+):([^\]]*)\]\s*$',
  );

  /// Parse [source] into a [LyricDocument]. Never throws — a broken
  /// file simply yields no lines.
  static LyricDocument parse(String source) {
    String body = source;
    if (body.startsWith('\uFEFF')) body = body.substring(1);

    String? title;
    String? artist;
    String? album;
    String? by;
    Duration offset = Duration.zero;
    final List<LyricLine> lines = <LyricLine>[];

    for (final String raw in body.split(RegExp(r'\r\n|\n|\r'))) {
      final String line = raw.trim();
      if (line.isEmpty) continue;

      final Match? header = _header.firstMatch(line);
      if (header != null) {
        final String key = header.group(1)!.toLowerCase();
        if (_headers.contains(key)) {
          final String value = header.group(2)!.trim();
          if (key == 'ti') {
            if (value.isNotEmpty) title = value;
          } else if (key == 'ar') {
            if (value.isNotEmpty) artist = value;
          } else if (key == 'al') {
            if (value.isNotEmpty) album = value;
          } else if (key == 'by') {
            if (value.isNotEmpty) by = value;
          } else if (key == 'offset') {
            offset = _parseOffset(value);
          }
          continue;
        }
      }

      final Iterable<RegExpMatch> stamps = _timestamp.allMatches(line);
      if (stamps.isEmpty) continue;

      // Text is everything after the run of leading timestamps.
      int textStart = 0;
      for (final RegExpMatch m in stamps) {
        if (m.start == textStart) {
          textStart = m.end;
        } else {
          break;
        }
      }
      String text = line.substring(textStart).trim();
      text = text.replaceAll(_wordTime, '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;

      for (final RegExpMatch m in stamps) {
        if (m.start >= textStart) break;
        final Duration? at = _parseTimestamp(m);
        if (at == null) continue;
        lines.add(LyricLine(timestamp: at, text: text));
      }
    }

    if (offset != Duration.zero) {
      for (int i = 0; i < lines.length; i++) {
        lines[i] = LyricLine(
          timestamp: lines[i].timestamp + offset,
          text: lines[i].text,
        );
      }
    }

    lines.sort((LyricLine a, LyricLine b) =>
        a.timestamp.compareTo(b.timestamp));

    return LyricDocument(
      title: title,
      artist: artist,
      album: album,
      by: by,
      offset: offset,
      lines: List<LyricLine>.unmodifiable(lines),
    );
  }

  /// Current-line lookup (lrc.md L12 / L20).
  ///
  /// mpv's `sub-delay`: positive = the text runs LATER than the audio.
  /// The Flutter overlay has to apply that itself — `sub-delay` only
  /// moves libass. Looking up at `position − subDelay` makes Z/X nudge
  /// lyrics the same way they nudge subtitles.
  static int indexAt(
    List<LyricLine> lines,
    Duration position, {
    double subDelaySeconds = 0,
  }) {
    if (lines.isEmpty) return -1;
    final int ms =
        position.inMilliseconds - (subDelaySeconds * 1000).round();
    int lo = 0;
    int hi = lines.length - 1;
    int ans = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (lines[mid].timestamp.inMilliseconds <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// `[offset:±N]` is milliseconds (the LRC spec). A bare number is
  /// accepted; junk yields zero so a broken header never kills the file.
  static Duration _parseOffset(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return Duration.zero;
    final double? n = double.tryParse(s);
    if (n == null || !n.isFinite) return Duration.zero;
    return Duration(milliseconds: n.round());
  }

  static Duration? _parseTimestamp(RegExpMatch m) {
    final int hours = int.tryParse(m.group(1) ?? '') ?? 0;
    final int minutes = int.tryParse(m.group(2) ?? '') ?? 0;
    final int seconds = int.tryParse(m.group(3) ?? '') ?? 0;
    final String frac = m.group(4) ?? '';
    int millis = 0;
    if (frac.isNotEmpty) {
      final String padded = frac.padRight(3, '0').substring(0, 3);
      millis = int.tryParse(padded) ?? 0;
    }
    if (seconds > 59) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }
}
