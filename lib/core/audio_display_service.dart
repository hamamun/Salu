import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'lyric_service.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'settings_service.dart';

/// The three exclusive audio-canvas modes (lrc.md §2 / L15). `none` is
/// everything that is not local audio — video keeps the plain mpv
/// canvas, untouched.
enum AudioCanvasMode { none, lyrics, visualizer, metadata }

/// Title / artist / album as shown in mode C. [title] is never empty
/// (lrc.md L4) — the file name fills any gap.
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.title,
    this.artist,
    this.album,
  });

  final String title;
  final String? artist;
  final String? album;
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

/// The audio canvas's one authority (lrc.md §2).
///
/// Precedence is lyrics > visualizer > metadata, exactly one at a time.
/// Flutter draws lyrics and metadata; mpv draws the visualizer via
/// `lavfi-complex` (L16) and is told `audio-display=no` so an embedded
/// cover never collides with mode C (L19). When lyrics win, the
/// visualizer is actually stopped — not covered (L18).
class AudioDisplayService {
  AudioDisplayService._internal();

  static final AudioDisplayService instance = AudioDisplayService._internal();

  /// Primary `lavfi-complex` graph (lrc.md L16): bar-type `showfreqs`,
  /// SALU accent on a dark canvas. No spectrum colour themes.
  static const String visualizerGraph =
      '[aid1]asplit[ao][a];[a]showfreqs=s=1280x720:mode=bar:ascale=log:fscale=log:win_func=gauss:averaging=5:colors=0x4C9EEB,format=yuv420p[vo]';

  static const int _cacheCap = 32;
  static const int _metaTries = 8;
  static const Duration _metaGap = Duration(milliseconds: 120);

  /// The mode the audio view reads. Nothing else in the file may imply
  /// a different combination (L15).
  final ValueNotifier<AudioCanvasMode> mode =
      ValueNotifier<AudioCanvasMode>(AudioCanvasMode.none);

  /// Mode C's text. `null` while not on a local audio file.
  final ValueNotifier<AudioTrackInfo?> info =
      ValueNotifier<AudioTrackInfo?>(null);

  /// Embedded cover bytes, or `null` → the SALU-logo placeholder (L5).
  final ValueNotifier<Uint8List?> coverBytes = ValueNotifier<Uint8List?>(null);

  bool _watching = false;
  int _generation = 0;
  String? _path;

  final Map<String, _CoverEntry> _coverCache = <String, _CoverEntry>{};
  final List<String> _coverOrder = <String>[];

  /// Attach clock-independent listeners. Safe to call more than once.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    // `shown` and the Settings visualizer are the two switches the
    // table reads live. `available` only changes on landing/stop, and
    // those paths call [_recompute] themselves — listening here would
    // re-evaluate against the *previous* track's path (audio → video
    // would briefly install lavfi-complex on a film).
    LyricService.instance.shown.addListener(_recompute);
    SettingsService.instance.visualizer.addListener(_recompute);
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
      unawaited(_applyEngine(AudioCanvasMode.none));
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
    unawaited(_applyEngine(AudioCanvasMode.none));
  }

  /// Pure precedence table (lrc.md §2) — the single authority.
  static AudioCanvasMode resolve({
    required bool isLocalAudio,
    required bool lyricsAvailable,
    required bool lyricsShown,
    required bool visualizerOn,
  }) {
    if (!isLocalAudio) return AudioCanvasMode.none;
    if (lyricsAvailable && lyricsShown) return AudioCanvasMode.lyrics;
    if (visualizerOn) return AudioCanvasMode.visualizer;
    return AudioCanvasMode.metadata;
  }

  void _recompute() {
    final AudioCanvasMode next = resolve(
      isLocalAudio: _path != null,
      lyricsAvailable: LyricService.instance.available.value,
      lyricsShown: LyricService.instance.shown.value,
      visualizerOn: SettingsService.instance.visualizer.value,
    );
    final AudioCanvasMode previous = mode.value;
    if (previous != next) mode.value = next;
    unawaited(_applyEngine(next));
  }

  void _resetSurface() {
    if (mode.value != AudioCanvasMode.none) {
      mode.value = AudioCanvasMode.none;
    }
    if (info.value != null) info.value = null;
    if (coverBytes.value != null) coverBytes.value = null;
  }

  Future<void> _applyEngine(AudioCanvasMode next) async {
    // L18: lyrics fully replace the visualizer — the engine stops
    // producing frames nobody sees. Metadata likewise. Always written
    // so a new landing cannot inherit a running graph.
    await _setVisualizer(next == AudioCanvasMode.visualizer);
  }

  Future<void> _setVisualizer(bool on) async {
    final NativePlayer? native = _native;
    if (native == null) return;
    try {
      await native.setProperty(
        'lavfi-complex',
        on ? visualizerGraph : '',
      );
    } catch (error) {
      debugPrint('[SALU/audio] lavfi-complex failed: $error');
    }
  }

  NativePlayer? get _native {
    final PlatformPlayer? platform = PlayerService.instance.player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> _loadText(String path, int generation) async {
    String title = '';
    String artist = '';
    String album = '';
    for (int i = 0; i < _metaTries; i++) {
      if (generation != _generation) return;
      title = await _readTag('title');
      artist = await _readTag('artist');
      album = await _readTag('album');
      if (title.isNotEmpty || artist.isNotEmpty || album.isNotEmpty) break;
      await Future<void>.delayed(_metaGap);
    }
    if (generation != _generation) return;
    final String fallback = MediaUtils.displayName(path);
    info.value = AudioTrackInfo(
      title: title.isEmpty ? fallback : title,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
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
