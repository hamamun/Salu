import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'lyric_service.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// Audio-canvas modes. `none` is everything that is not local audio —
/// video keeps the plain mpv canvas, untouched.
enum AudioCanvasMode { none, lyrics, metadata }

/// Audio metadata shown in mode C. [title] is never empty (lrc.md L4) —
/// the file name fills any gap; other fields are shown only when present.
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.title,
    this.artist,
    this.album,
    this.additional = const <String, String>{},
  });

  final String title;
  final String? artist;
  final String? album;

  /// Every other non-empty tag exposed by mpv for the current file.
  final Map<String, String> additional;
}

/// Cached cover-art bytes keyed by canonical path (lrc.md L27).
class _CoverEntry {
  const _CoverEntry({
    required this.bytes,
    required this.size,
    required this.modified,
  });

  final Uint8List? bytes;
  final int size;
  final DateTime modified;
}

/// Coordinates the audio canvas and its metadata/cover-art surface.
/// Lyrics take precedence over metadata; video keeps the plain mpv canvas.
class AudioDisplayService {
  AudioDisplayService._internal();

  static final AudioDisplayService instance = AudioDisplayService._internal();

  static const int _cacheCap = 32;
  /// How long to wait for the engine to actually hold THIS file before
  /// its tags may be read (25 × 120 ms ≈ 3 s).
  static const int _fileTries = 25;
  static const Duration _metaGap = Duration(milliseconds: 120);
  /// Settle polls once the file gate has passed — the new demuxer's
  /// header (and with it the tags, or their absence) lands within this
  /// many ticks for a local file.
  static const int _metaTries = 8;
  /// The mode the audio view reads. Nothing else in the file may imply
  /// a different combination (L15).
  final ValueNotifier<AudioCanvasMode> mode =
      ValueNotifier<AudioCanvasMode>(AudioCanvasMode.none);

  /// Metadata text. `null` while not on a local audio file.
  final ValueNotifier<AudioTrackInfo?> info =
      ValueNotifier<AudioTrackInfo?>(null);

  /// Embedded cover bytes, or `null` → the SALU-logo placeholder (L5).
  final ValueNotifier<Uint8List?> coverBytes = ValueNotifier<Uint8List?>(null);

  bool _watching = false;
  int _generation = 0;
  String? _path;

  final Map<String, _CoverEntry> _coverCache = <String, _CoverEntry>{};
  final List<String> _coverOrder = <String>[];

  NativePlayer? get _native {
    final PlatformPlayer? platform = PlayerService.instance.player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Attach clock-independent listeners. Safe to call more than once.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    LyricService.instance.shown.addListener(_recompute);
  }

  /// Same start-file trigger as [SubtitleService.onMediaLanded] (L26).
  void onMediaLanded(String uri, {required bool channelMode}) {
    startWatching();
    final int generation = ++_generation;
    if (channelMode ||
        uri.contains('://') ||
        QueueService.instance.isChannelList ||
        !MediaUtils.isAudio(uri)) {
      _path = null;
      _resetSurface();
      return;
    }
    final String path = MediaUtils.canonicalPath(uri);
    _path = path;
    // Never inherit the previous track's art or text (L26).
    coverBytes.value = null;
    info.value = AudioTrackInfo(title: MediaUtils.displayName(path));
    _recompute();
    unawaited(_loadCover(path, generation));
    unawaited(_loadText(path, generation));
  }

  void onStopped() {
    _generation++;
    _path = null;
    _resetSurface();
  }

  void _recompute() {
    final AudioCanvasMode next = _path == null
        ? AudioCanvasMode.none
        : (LyricService.instance.available.value &&
                LyricService.instance.shown.value
            ? AudioCanvasMode.lyrics
            : AudioCanvasMode.metadata);
    if (mode.value != next) mode.value = next;
  }

  void _resetSurface() {
    if (mode.value != AudioCanvasMode.none) {
      mode.value = AudioCanvasMode.none;
    }
    if (info.value != null) info.value = null;
    if (coverBytes.value != null) coverBytes.value = null;
  }

  /// Mode C's text — the tags, but only THIS file's tags.
  ///
  /// mpv's `metadata` property reads the CURRENT demuxer's tags, and
  /// the old demuxer is torn down BEFORE `path` flips to the new file
  /// (mpv asserts `demuxer == NULL` when it sets the new filename).
  /// So `path` matching this file is the gate: until it matches,
  /// whatever is readable belongs to the previous song — the stale
  /// title on a no-tag file — and after it matches, the previous
  /// song's tags are unreachable, so an empty read can only mean "this
  /// file has no tags" or "its header is still being parsed". A file
  /// whose load never takes (failed open, or we already moved on)
  /// keeps the file name that landed with it.
  ///
  /// The gate compares with [MediaUtils.samePath], never with `==`: on
  /// Windows media_kit hands mpv the `\\?\C:\…` long-path spelling, and
  /// mpv's `path` reports exactly what it was given. Plain string
  /// equality therefore never matched a local file — the gate timed out
  /// on every track and mode C kept showing the bare file name.
  Future<void> _loadText(String path, int generation) async {
    bool current = false;
    String seen = '';
    for (int i = 0; i < _fileTries; i++) {
      if (generation != _generation) return;
      final NativePlayer? native = _native;
      if (native != null) {
        try {
          seen = await native.getProperty('path');
          if (seen.isNotEmpty && MediaUtils.samePath(seen, path)) {
            current = true;
            break;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(_metaGap);
    }
    if (!current) {
      // Never read a previous file's tags. One debug line, so a
      // mismatch is diagnosable instead of silent — the file name that
      // landed with the track stays on screen.
      debugPrint('[SALU/audio] tags skipped for "$path" (engine path "$seen")');
      return;
    }
    // Settle: the new demuxer's tags (or their absence) land as soon
    // as its header is parsed. Poll like the old retry loop did — now
    // safe, because nothing stale can answer.
    Map<String, String> tags = <String, String>{};
    for (int i = 0; i < _metaTries; i++) {
      if (generation != _generation) return;
      tags = await _readTagMap();
      if (tags.isNotEmpty) break;
      await Future<void>.delayed(_metaGap);
    }
    if (generation != _generation) return;
    final String fallback = MediaUtils.displayName(path);
    final String title = _pickTag(tags, 'title');
    final String artist = _pickTag(tags, 'artist');
    final String album = _pickTag(tags, 'album');
    final Map<String, String> additional = <String, String>{};
    for (final MapEntry<String, String> entry in tags.entries) {
      if (_isPrimaryTag(entry.key)) continue;
      additional[entry.key] = entry.value;
    }
    info.value = AudioTrackInfo(
      title: title.isEmpty ? fallback : title,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
      additional: additional,
    );
  }

  /// The three fields the layout gives a line of their own (L2).
  static const List<String> _primaryKeys = <String>['title', 'artist', 'album'];

  static bool _isPrimaryTag(String key) =>
      _primaryKeys.contains(key.toLowerCase());

  /// First non-empty tag answering [key], matched case-insensitively:
  /// ID3v2 tags arrive lowercased (`title`), a FLAC Vorbis comment
  /// arrives uppercased (`TITLE`) — same field, same line.
  static String _pickTag(Map<String, String> tags, String key) {
    for (final MapEntry<String, String> entry in tags.entries) {
      if (entry.key.toLowerCase() == key && entry.value.isNotEmpty) {
        return entry.value;
      }
    }
    return '';
  }

  /// Every tag mpv exposes for the file the engine now holds.
  ///
  /// `metadata` is a `MPV_FORMAT_NODE_MAP`, and libmpv's manual is
  /// explicit that trying to retrieve it as a raw string does not work —
  /// media_kit's `getProperty` answers `''` for it, and for
  /// `filtered-metadata` too (which would additionally hide every tag
  /// outside mpv's `--display-tags` list). So the map is walked through
  /// its own documented string sub-properties instead:
  /// `metadata/list/count`, `metadata/list/N/key`, `metadata/list/N/value`.
  /// `metadata` — never the filtered map: mode C shows every available
  /// field (L2).
  Future<Map<String, String>> _readTagMap() async {
    final String countRaw = await _readProperty('metadata/list/count');
    final int count = int.tryParse(countRaw) ?? -1;
    if (count < 0) {
      // An engine build without the list sub-properties — fall back to
      // one string probe per common tag.
      return _probeTags();
    }
    final Map<String, String> tags = <String, String>{};
    for (int i = 0; i < count; i++) {
      final String key = await _readProperty('metadata/list/$i/key');
      if (key.isEmpty) continue;
      final String value = await _readProperty('metadata/list/$i/value');
      if (value.isEmpty) continue;
      tags[key] = value;
    }
    if (tags.isEmpty && count > 0) {
      // The list answered nothing although mpv counts entries — a build
      // with only part of the sub-properties. The probes still get the
      // common fields on screen.
      return _probeTags();
    }
    return tags;
  }

  /// Safety net for a libmpv without `metadata/list/*`: mpv's own
  /// `--display-tags` default set, one `metadata/by-key/…` probe each
  /// (`metadata/by-key/<key>` IS a plain string property, so it always
  /// answers — with `''` when the file has no such tag).
  static const List<String> _probeKeys = <String>[
    'title', 'artist', 'album', 'album_artist', 'genre', 'date', 'year',
    'track', 'disc', 'composer', 'performer', 'comment', 'publisher',
    'copyright', 'language', 'encoder', 'bpm', 'lyricist',
  ];

  Future<Map<String, String>> _probeTags() async {
    final Map<String, String> tags = <String, String>{};
    for (final String key in _probeKeys) {
      final String value = await _readProperty('metadata/by-key/$key');
      if (value.isNotEmpty) tags[key] = value;
    }
    return tags;
  }

  /// One mpv property as a string; `''` whenever mpv has nothing to say
  /// (unavailable property, engine not up yet, read failed).
  ///
  /// `NativePlayer.getProperty` returns `''` for a property mpv cannot
  /// serve, so empty is the only "no value" signal there is. A tag whose
  /// text merely STARTS with `(` is a real tag value (`(I Can't Get No)
  /// Satisfaction`) and is kept.
  Future<String> _readProperty(String name) async {
    final NativePlayer? native = _native;
    if (native == null) return '';
    try {
      return (await native.getProperty(name)).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadCover(String path, int generation) async {
    final _CoverEntry? hit = _validEntry(path);
    if (hit != null) {
      if (generation != _generation) return;
      coverBytes.value = hit.bytes;
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await compute(_readCoverArtBytes, path);
    } catch (_) {
      bytes = _readCoverArtBytes(path);
    }
    if (bytes == null) {
      // No embedded picture (or the tag reader could not open the
      // container) — the SALU-logo placeholder is the intended look
      // (L5). One debug line says which of the two it was.
      debugPrint('[SALU/audio] no embedded cover art in "$path"');
    }
    _remember(path, bytes);
    if (generation != _generation) return;
    coverBytes.value = bytes;
  }

  _CoverEntry? _validEntry(String path) {
    final _CoverEntry? entry = _coverCache[path];
    if (entry == null) return null;
    try {
      final FileStat stat = File(path).statSync();
      if (stat.size != entry.size || stat.modified != entry.modified) {
        _coverCache.remove(path);
        _coverOrder.remove(path);
        return null;
      }
    } catch (_) {
      return entry;
    }
    return entry;
  }

  void _remember(String path, Uint8List? bytes) {
    int size = 0;
    DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final FileStat stat = File(path).statSync();
      size = stat.size;
      modified = stat.modified;
    } catch (_) {}
    _coverCache[path] = _CoverEntry(
      bytes: bytes,
      size: size,
      modified: modified,
    );
    _coverOrder.remove(path);
    _coverOrder.add(path);
    while (_coverOrder.length > _cacheCap) {
      final String old = _coverOrder.removeAt(0);
      _coverCache.remove(old);
    }
  }
}

/// Isolate entry — cover-art bytes only (lrc.md L3 / L21). Title /
/// artist / album are never taken from here.
Uint8List? _readCoverArtBytes(String path) {
  try {
    final AudioMetadata meta = readMetadata(File(path), getImage: true);
    final List<Picture> pictures = meta.pictures;
    if (pictures.isEmpty) return null;
    Picture? cover;
    for (final Picture p in pictures) {
      if (p.pictureType == PictureType.coverFront && p.bytes.isNotEmpty) {
        cover = p;
        break;
      }
    }
    if (cover == null) {
      for (final Picture p in pictures) {
        if (p.bytes.isNotEmpty) {
          cover = p;
          break;
        }
      }
    }
    final Uint8List? bytes = cover?.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      return null;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}
