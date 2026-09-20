import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_tag_fields.dart';
import 'mpv_metadata.dart';
import 'lyric_service.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// Audio-canvas modes. `none` is everything that is not local audio —
/// video keeps the plain mpv canvas, untouched.
enum AudioCanvasMode { none, lyrics, metadata }

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
  /// many ticks for a local file (12 × 120 ms ≈ 1.4 s). `path` flips
  /// before the header is parsed, so this window is what actually waits
  /// for the tags; a tagless file just pays it once, invisibly.
  static const int _metaTries = 12;
  /// The mode the audio view reads. Nothing else in the file may imply
  /// a different combination (L15).
  final ValueNotifier<AudioCanvasMode> mode =
      ValueNotifier<AudioCanvasMode>(AudioCanvasMode.none);

  /// Metadata text. `null` while not on a local audio file.
  ///
  /// Carries the four rendered rows *and* the full tag map the canvas does
  /// not show ([AudioTrackInfo.rawTags]) — the parked set `info.md` is
  /// about. The read is unfiltered on purpose (L29).
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
    // Never inherit the previous track's art or text (L26). The name that
    // landed with the file is the whole canvas until the tags answer —
    // the minimal state (L33), not a placeholder waiting to be replaced.
    coverBytes.value = null;
    info.value = AudioTrackInfo(
      title: MediaUtils.displayName(path),
      minimal: true,
    );
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
    // L29–L35 — the whole map goes to the field contract, which decides
    // what the canvas shows and what stays parked. Nothing is filtered
    // here: the read keeps everything, the render keeps the standard set.
    info.value = buildAudioTrackInfo(
      tags,
      fallbackTitle: MediaUtils.displayName(path),
    );
  }

  /// Every tag mpv exposes for the file the engine now holds.
  ///
  /// `metadata` is a `MPV_FORMAT_NODE_MAP` — a key/value map of the
  /// current demuxer's tags — and mpv's manual says plainly of it:
  /// "Trying to retrieve this property as a raw string doesn't work."
  /// The one string the engine can produce for such a value is a JSON
  /// blob, never the `{key=value, …}` listing the old parser looked for,
  /// so that parse could only ever come back empty. The documented string
  /// route is the property's own sub-properties, and that is what this
  /// walks:
  ///
  ///   `metadata/list/count`  → how many tags the file actually has
  ///   `metadata/list/N/key`  → the Nth tag's name
  ///   `metadata/list/N/value`→ the Nth tag's text
  ///
  /// with the JSON string form and `metadata/by-key/<key>` probes as the
  /// fallbacks for an engine build without the list route. The source is
  /// `metadata` — never `filtered-metadata`, which is cut down
  /// to mpv's `--display-tags` whitelist and would hide real tags: the
  /// read is the whole map so the parked set is complete, and the canvas'
  /// standard-field selection happens at render instead (L29).
  Future<Map<String, String>> _readTagMap() =>
      MpvMetadataReader(_readProperty).readTags();

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
