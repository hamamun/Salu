/// Mode C's field contract (lrc.md L29–L33) — pure Dart, no I/O,
/// unit-testable (see `test/audio_tag_fields_test.dart`).
///
/// The lock: **collect everything, render the standard set.** mpv's tag
/// map is read whole (lrc.md §3.7 — never `filtered-metadata`) and lands in
/// [AudioTrackInfo.rawTags] untouched; what the canvas *shows* is decided
/// here, by canonical field, with the junk filtered out by rule instead of
/// by luck. The rest of the data is parked for `info.md`, not thrown away.
library;

/// What mode C renders under the album art — four rows, always:
/// Title, Artist, Album, and one dot-separated context line
/// (Genre · Year · Track). A missing field is simply not drawn; nothing
/// here is allowed to change the layout's height (L30).
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.title,
    required this.minimal,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.track,
    this.rawTags = const <String, String>{},
  });

  /// Title line — never empty: the file name fills any gap (L4).
  final String title;

  /// The no-metadata state (L33): [title] is the file name and nothing
  /// else is drawn. Reached when the file carries none of the six
  /// standard fields — a `Comment`, an `Encoder` string or a replaygain
  /// PRIV frame is not metadata a listener is owed.
  final bool minimal;

  final String? artist;
  final String? album;

  /// Context-line parts, in render order, already cleaned. Empty list in
  /// [minimal] mode.
  List<String> get contextParts => <String>[
        if (genre != null) genre!,
        if (year != null) year!,
        if (track != null) track!,
      ];

  /// Every tag mpv reported for this file, keys and values exactly as the
  /// engine gave them — primaries included, junk included. Parked for
  /// `info.md`; the canvas must not read it.
  final Map<String, String> rawTags;
}

/// The six spellings every container uses for the same field, matched
/// case-insensitively on exact keys: ID3v2 delivers `title`, a Vorbis
/// comment `TITLE`, MP4 atoms arrive already renamed by libavformat
/// (`©nam` → `title`), ASF keeps `Title`. First non-empty hit wins, in the
/// order written — so the canonical name always beats a legacy alias.
const List<String> _titleKeys = <String>['title', 'tit2', 'titt', 'inam'];
const List<String> _artistKeys = <String>[
  'artist', 'tpe1', 'iart', 'author', 'performer',
];
const List<String> _albumKeys = <String>['album', 'talb', 'iprd'];
const List<String> _genreKeys = <String>['genre', 'tcon', 'gnre', 'ignr'];
const List<String> _dateKeys = <String>[
  'date', 'year', 'tdrc', 'tyer', 'tdrl', 'origyear',
];
const List<String> _trackKeys = <String>[
  'track', 'tracknumber', 'trck', 'trkn', 'ttrk',
];
const List<String> _trackTotalKeys = <String>[
  'totaltracks', 'tracktotal', 'numpairs',
];

/// Build the mode-C field set from [tags], falling back to
/// [fallbackTitle] (the file name) when the title tag is absent (L4).
AudioTrackInfo buildAudioTrackInfo(
  Map<String, String> tags, {
  required String fallbackTitle,
}) {
  final String title = _canvasValue(_lookup(tags, _titleKeys));
  final String artist = _canvasValue(_lookup(tags, _artistKeys));
  final String album = _canvasValue(_lookup(tags, _albumKeys));
  final String genre = _genreOf(_lookup(tags, _genreKeys));
  final String year = _yearOf(_lookup(tags, _dateKeys));
  final String track = _trackOf(
    _lookup(tags, _trackKeys),
    _lookup(tags, _trackTotalKeys),
  );

  // L33 — no standard field at all → the minimal state. Judged on what the
  // FILE carries, so the fallback title never counts as metadata.
  final bool minimal = title.isEmpty &&
      artist.isEmpty &&
      album.isEmpty &&
      genre.isEmpty &&
      year.isEmpty &&
      track.isEmpty;

  // A field that merely repeats one already shown says nothing new;
  // `ALBUM == TITLE` is a common ripper habit and reads as a bug.
  final Set<String> shown = <String>{
    if (title.isNotEmpty) title.toLowerCase(),
  };
  final String? artistOut = _fresh(artist, shown);
  final String? albumOut = _fresh(album, shown);
  final String? genreOut = _fresh(genre, shown);
  final String? yearOut = _fresh(year, shown);
  final String? trackOut = _fresh(track, shown);

  return AudioTrackInfo(
    title: title.isEmpty ? fallbackTitle : title,
    minimal: minimal,
    artist: artistOut,
    album: albumOut,
    genre: genreOut,
    year: yearOut,
    track: trackOut,
    rawTags: Map<String, String>.unmodifiable(tags),
  );
}

/// First non-empty value under any of [aliases], case-insensitively.
String _lookup(Map<String, String> tags, List<String> aliases) {
  for (final String alias in aliases) {
    for (final MapEntry<String, String> entry in tags.entries) {
      if (entry.key.toLowerCase() == alias && entry.value.trim().isNotEmpty) {
        return entry.value;
      }
    }
  }
  return '';
}

/// One canvas-worthy line out of a raw tag value.
///
/// Multi-line values (an unsynced lyrics blob parked under a canvas key)
/// collapse to their first non-empty line — the reserved text block must
/// never depend on how many lines a tag happens to carry (L31). Values
/// holding control characters are binary payload, not text (`Id3v2
/// Priv.peak Value: lw\0\0`), and are dropped rather than rendered as
/// boxes.
String _canvasValue(String raw) {
  String value = raw.replaceAll('\r', '\n').replaceAll('\t', ' ').trim();
  if (value.isEmpty) return '';
  for (final String line in value.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      value = trimmed;
      break;
    }
  }
  for (final int rune in value.runes) {
    if (rune < 0x20 ||
        rune == 0x7f ||
        (rune >= 0x80 && rune <= 0x9f) ||
        rune == 0xFFFD) {
      return '';
    }
  }
  // A tag can hold megabytes; layout must not have to measure them.
  if (value.length > _maxCanvasValueLength) {
    value = value.substring(0, _maxCanvasValueLength);
  }
  return value.trimRight();
}

/// The length the canvas is willing to lay out before ellipsizing.
const int _maxCanvasValueLength = 160;

/// `Dance`, `(17)Dance` → `Dance`. A bare `17` is an ID3v1 genre index:
/// printing a number the viewer cannot decode is worse than printing
/// nothing, so it is dropped (the full 0–191 name table is parked in
/// `info.md` for a real file that needs it).
String _genreOf(String raw) {
  String value =
      _canvasValue(raw).replaceAll(RegExp(r'^\(\d{1,3}\)'), '');
  // Vorbis comments allow several genres; the first is the answer, the
  // rest are a ripper's tag-cloud.
  final List<String> parts = value.split(';');
  if (parts.isNotEmpty) value = parts.first.trim();
  if (RegExp(r'^\d{1,3}$').hasMatch(value)) return '';
  return value;
}

/// `2013-05-17`, `2013`, `(2013)` → `2013`. A run of four digits only reads
/// as a year when nothing else is glued to it — `20135` is a catalogue
/// number, not a year — and it has to sit in a sane range.
String _yearOf(String raw) {
  final String value = _canvasValue(raw);
  for (final RegExpMatch m in RegExp(r'\d{4}').allMatches(value)) {
    final bool gluedBefore =
        m.start > 0 && _isDigit(value.codeUnitAt(m.start - 1));
    final bool gluedAfter =
        m.end < value.length && _isDigit(value.codeUnitAt(m.end));
    if (gluedBefore || gluedAfter) continue;
    final int? year = int.tryParse(m.group(0)!);
    if (year != null && year >= 1400 && year <= 2100) return '$year';
  }
  return '';
}

bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

/// `3/12`, `3 of 12`, `3/0`, `3` → `3/12`, `3 of 12`, `3`, `3`. ID3 writes
/// the total as `0` when the album's length is unknown; a zero total is no
/// total. An explicit `totaltracks` tag fills in a bare number.
String _trackOf(String raw, String rawTotal) {
  final String value = _canvasValue(raw);
  if (value.isEmpty) return '';
  final _NumPair pair = _NumPair.parse(value);
  final String number = pair.number;
  if (number.isEmpty) return '';
  // A `0` total from the track tag itself is as good as absent, and then
  // an explicit `totaltracks` frame is what completes the pair.
  String total = _positiveCount(pair.total);
  if (total.isEmpty) total = _positiveCount(_canvasValue(rawTotal));
  return total.isEmpty ? number : '$number/$total';
}

String _positiveCount(String value) {
  final int? n = int.tryParse(value.trim());
  return (n != null && n > 0) ? '$n' : '';
}

/// The value, unless it repeats something already on screen.
String? _fresh(String value, Set<String> shown) {
  if (value.isEmpty) return null;
  final String key = value.toLowerCase();
  if (shown.contains(key)) return null;
  shown.add(key);
  return value;
}

/// A `number/total` pair read out of whatever text the tag holds.
class _NumPair {
  const _NumPair({required this.number, required this.total});

  final String number;
  final String total;

  factory _NumPair.parse(String value) {
    final RegExpMatch? pair = RegExp(
      r'(\d{1,4})\s*(?:/|\bof\b)\s*(\d{1,4})',
      caseSensitive: false,
    ).firstMatch(value);
    if (pair != null) {
      return _NumPair(number: pair.group(1)!, total: pair.group(2)!);
    }
    final RegExpMatch? solo = RegExp(r'^(\d{1,4})').firstMatch(value);
    return _NumPair(number: solo?.group(1) ?? '', total: '');
  }
}
