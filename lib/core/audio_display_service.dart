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
  Future<void> _loadText(String path, int generation) async {
    bool current = false;
    for (int i = 0; i < _fileTries; i++) {
      if (generation != _generation) return;
      final NativePlayer? native = _native;
      if (native != null) {
        try {
          final String raw = await native.getProperty('path');
          if (raw.isNotEmpty && MediaUtils.canonicalPath(raw) == path) {
            current = true;
            break;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(_metaGap);
    }
    if (!current) return;
    // Settle: the new demuxer's tags (or their absence) land as soon
    // as its header is parsed. Poll like the old retry loop did — now
    // safe, because nothing stale can answer.
    String title = '';
    String artist = '';
    String album = '';
    Map<String, String> additional = <String, String>{};
    for (int i = 0; i < _metaTries; i++) {
      if (generation != _generation) return;
      title = await _readTag('title');
      artist = await _readTag('artist');
      album = await _readTag('album');
      additional = await _readAllTags();
      if (title.isNotEmpty ||
          artist.isNotEmpty ||
          album.isNotEmpty ||
          additional.isNotEmpty) {
        break;
      }
      await Future<void>.delayed(_metaGap);
    }
    if (generation != _generation) return;
    final String fallback = MediaUtils.displayName(path);
    info.value = AudioTrackInfo(
      title: title.isEmpty ? fallback : title,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
      additional: additional,
    );
  }

  Future<String> _readTag(String key) async {
    final NativePlayer? native = _native;
    if (native == null) return '';
    try {
      final String raw =
          (await native.getProperty('metadata/by-key/$key')).trim();
      if (raw.isEmpty || raw.startsWith('(')) return '';
      return raw;
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, String>> _readAllTags() async {
    final NativePlayer? native = _native;
    if (native == null) return <String, String>{};
    try {
      final String raw = await native.getProperty('filtered-metadata');
      final Map<String, String> tags = _parseMetadataMap(raw);
      tags.removeWhere(
        (String key, String value) =>
            value.trim().isEmpty ||
            value.trim().startsWith('(') ||
            const <String>{'title', 'artist', 'album'}.contains(key.toLowerCase()),
      );
      return tags;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// mpv prints filtered metadata as a map such as `{genre=Rock, date=2024}`.
  /// Values may contain commas, so only commas followed by another key are
  /// treated as separators.
  static Map<String, String> _parseMetadataMap(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return <String, String>{};
    final Map<String, String> result = <String, String>{};
    final RegExp entry = RegExp(
      r'([A-Za-z0-9_.-]+)\s*=\s*(.*?)(?=,\s*[A-Za-z0-9_.-]+\s*=|\s*})',
    );
    for (final RegExpMatch match in entry.allMatches(text)) {
      final String key = match.group(1)!.trim();
      final String value = match.group(2)!.trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
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
