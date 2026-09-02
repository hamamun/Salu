import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Generates the video-frame thumbnails shown on timeline hover
/// (Phase 3 · Step 3 — "video thumbnails on timeline hover").
///
/// The visible [PlayerService] player must never be seeked just to produce a
/// preview frame, so this service runs its own **headless** mpv instance
/// (`vo: null`, muted, never playing) that seeks to the hovered timestamp and
/// captures a single frame with mpv's `screenshot-to-file` command. mpv's
/// `screenshot` `video` flag is implemented at the video-filter-chain level,
/// so it works even with the null video output.
class ThumbnailService {
  ThumbnailService._internal() {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'SALU Thumbnails',
        logLevel: MPVLogLevel.error,
        vo: 'null',
        muted: true,
      ),
    );
  }

  static final ThumbnailService instance = ThumbnailService._internal();

  late final Player _player;

  /// URI currently loaded into the headless player.
  String? _loadedUri;

  /// True once [_loadedUri] has reported a known duration.
  bool _ready = false;

  /// Bumped on every capture request so stale results are discarded.
  int _generation = 0;

  /// Recent captures keyed by `uri#bucketSeconds` (5-second buckets) so
  /// re-hovering an already-previewed region is instant.
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  NativePlayer? get _native {
    final PlatformPlayer? platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Captures the frame closest to [time] in [uri], returned as JPEG bytes.
  ///
  /// Returns `null` when the frame can't be produced (no video stream, mpv
  /// failure, or timeout). Results are cached per 5-second bucket.
  Future<Uint8List?> captureFrame(String uri, Duration time) async {
    final int bucket = (time.inMilliseconds ~/ 5000) * 5;
    final String key = '$uri#$bucket';
    final Uint8List? cached = _cache[key];
    if (cached != null) return cached;

    final int generation = ++_generation;
    try {
      await _openIfNeeded(uri);
      if (generation != _generation) return null;

      // The headless player stays paused; seeking updates the decoded frame.
      await _player.pause();
      await _player.seek(time);
      // Give mpv a beat to decode the frame at the new position.
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (generation != _generation) return null;

      final File file = await _captureToFile();
      Uint8List? bytes;
      try {
        if (file.existsSync() && file.lengthSync() > 0) {
          bytes = await file.readAsBytes();
        }
      } finally {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {
          // Best-effort temp cleanup.
        }
      }

      if (bytes != null && bytes.isNotEmpty) {
        _cache[key] = bytes;
        _trimCache();
      }
      return bytes;
    } catch (error) {
      debugPrint('[SALU/thumbs] capture failed: $error');
      return null;
    }
  }

  Future<void> _openIfNeeded(String uri) async {
    if (_loadedUri == uri) {
      if (!_ready) await _waitForDuration();
      return;
    }
    _loadedUri = uri;
    _ready = false;
    _cache.removeWhere((String key, Uint8List _) => key.startsWith('$uri#'));
    await _player.open(Media(uri), play: false);
    await _waitForDuration();
  }

  /// Blocks until mpv knows the media duration (needed before seeking).
  Future<void> _waitForDuration() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (_player.state.duration <= Duration.zero &&
        stopwatch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _ready = true;
  }

  /// Asks mpv to dump the current frame to a unique temp file, then waits
  /// (polling) until the write lands — `screenshot-to-file` is asynchronous.
  Future<File> _captureToFile() async {
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'salu_thumb_${_generation}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await _native?.command(<String>['screenshot-to-file', file.path, 'video']);
    final Stopwatch stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 3)) {
      if (file.existsSync() && file.lengthSync() > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return file;
  }

  /// Drops every cached thumbnail (Settings → General → Clear Cache & Data).
  void clearCache() {
    _cache.clear();
  }

  void _trimCache() {
    while (_cache.length > 160) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Releases the headless engine (the app lives for the process lifetime, so
  /// this mirrors [PlayerService.dispose] and is safe to call on shutdown).
  Future<void> dispose() async {
    _generation++;
    await _player.dispose();
  }
}
