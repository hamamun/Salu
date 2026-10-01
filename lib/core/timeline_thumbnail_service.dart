import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';

/// SALU's timeline hover thumbnails — the shared cache plus the background
/// generation behind it.
///
/// The hover preview (`ui/osc/media_timeline.dart`) is now a pure cache
/// lookup: the moment the pointer enters a second, its frame is usually
/// already here, so the preview flows continuously in either direction
/// while scrubbing instead of waiting for a decode.
///
/// Frames are filled by TWO lanes served by ONE serial worker:
///   · the STRIP lane — shortly after a video settles, a sparse grid of
///     frames is decoded in the background (one second apart on short
///     media, sparser on long, capped at [maxStripFrames]) so the whole
///     bar is hover-ready with no mouse activity at all;
///   · the FINE lane — the exact second under the cursor, for the gaps
///     the grid leaves. Fine always runs before strip, so a hovered
///     second is never queued behind the background grid.
///
/// Playback safety (why it is shaped this way):
///   · ONE decode in flight, ever — the worker is a single async loop, so
///     fast cursor movement can only fill a small queue, never pile up
///     parallel decodes;
///   · a short pause ([pacing]) between decodes keeps the plugin's native
///     thread idle between frames;
///   · the strip starts only after [stripStartDelay] — after the startup
///     and first-buffering spikes have passed;
///   · everything pending is dropped the instant the current video
///     changes (token bump in [ensureStrip]) or media stops ([release]);
///   · a file that cannot produce frames (audio, unsupported codec) is
///     marked dead after a few consecutive failures, so the worker never
///     burns work on a file that can never give a frame;
///   · remote streams (`://`) never enter any queue at all.
///
/// The cache is RAM-only, LRU and bounded — a full grid plus a hover
/// neighbourhood is a few hundred KB.
class TimelineThumbnailService {
  TimelineThumbnailService({
    Future<Uint8List?> Function(String path, int timeMs)? extractor,
    this.pacing = const Duration(milliseconds: 80),
    this.stripStartDelay = const Duration(milliseconds: 2500),
    int maxCacheEntries = 192,
    int maxStripFrames = 120,
    int maxFineQueue = 24,
  })  : _extractor = extractor ?? _pluginExtract,
        _maxCacheEntries = maxCacheEntries,
        _maxStripFrames = maxStripFrames,
        _maxFineQueue = maxFineQueue;

  /// The one and only instance for the app (tests build their own).
  static final TimelineThumbnailService instance =
      TimelineThumbnailService();

  /// Pause between two decodes (both lanes) — keeps the native thread
  /// off the CPU between frames.
  final Duration pacing;

  /// How long after [ensureStrip] the background grid starts decoding.
  final Duration stripStartDelay;

  /// Notified with every decoded frame (path, second, bytes). The
  /// timeline shows it only when it is the second under its cursor.
  void Function(String path, int timeMs, Uint8List bytes)? onFrame;

  /// The frame grid's cap for one video (plus the final second).
  static const int defaultMaxStripFrames = 120;

  static const int _maxConsecutiveFailures = 3;

  final Future<Uint8List?> Function(String path, int timeMs) _extractor;
  final int _maxCacheEntries;
  final int _maxStripFrames;
  final int _maxFineQueue;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// One job: one whole second of one file.
  final class _Job {
    const _Job(this.path, this.timeMs);
    final String path;
    final int timeMs;
    String get key => '$path@$timeMs';
  }

  /// Key of the in-flight job (null = idle) — deduplicates the queues.
  String? _inFlightKey;

  /// Hover requests — processed before the strip grid.
  final List<_Job> _fineQueue = <_Job>[];

  /// The armed strip grid, in file order.
  final List<_Job> _stripQueue = <_Job>[];

  /// The serial worker. Null = not running.
  Future<void>? _worker;

  /// Bumped on every re-arm — invalidates the in-flight decode and every
  /// pending job of the previous video.
  int _token = 0;

  /// '$path@${durationMs}' of the armed strip — re-arming the same video
  /// (timeline remount, duration settle) is a no-op.
  String? _armedKey;

  Timer? _stripTimer;

  /// A file proven unable to produce frames (audio, bad codec).
  String? _deadPath;

  int _failures = 0;

  // ── Cache ─────────────────────────────────────────────────────────────

  /// LRU lookup — a hit moves the entry to the most-recent end.
  Uint8List? lookup(String path, int timeMs) {
    final String key = '$path@$timeMs';
    final Uint8List? bytes = _cache.remove(key);
    if (bytes == null) return null;
    _cache[key] = bytes;
    return bytes;
  }

  void _put(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// True when a job for [key] is in flight or already queued (fine or
  /// strip) — the worker would produce it anyway.
  bool _has(String key) {
    if (_inFlightKey == key) return true;
    for (final _Job j in _fineQueue) {
      if (j.key == key) return true;
    }
    for (final _Job j in _stripQueue) {
      if (j.key == key) return true;
    }
    return false;
  }

  // ── The strip (background) lane ───────────────────────────────────────

  /// Arms the background grid for one video. Idempotent per
  /// (path, duration): re-arming the same video does nothing; a different
  /// one cancels the previous arm — its timer, its queues and its
  /// in-flight decode.
  void ensureStrip(String path, Duration duration) {
    if (path.contains('://') || duration <= Duration.zero) return;
    final String key = '$path@${duration.inMilliseconds}';
    if (_armedKey == key) return;
    _stripTimer?.cancel();
    _token++;
    _failures = 0;
    _deadPath = null;
    _fineQueue.clear();
    _stripQueue.clear();
    _inFlightKey = null;
    _armedKey = key;
    _stripTimer = Timer(stripStartDelay, () {
      if (_armedKey != key) return;
      for (final int t
          in computeStripTimes(duration, maxFrames: _maxStripFrames)) {
        _stripQueue.add(_Job(path, t));
      }
      _kick();
    });
  }

  /// Stops all work and forgets the armed strip (media stopped / cleared).
  void release() {
    _stripTimer?.cancel();
    _stripTimer = null;
    _token++;
    _failures = 0;
    _deadPath = null;
    _fineQueue.clear();
    _stripQueue.clear();
    _inFlightKey = null;
    _armedKey = null;
  }

  /// The grid's seconds for [duration]: one second apart while that stays
  /// within [maxFrames] frames, a whole-second multiple beyond — plus the
  /// final second, so the bar's right end is never bare (the grid is thus
  /// at most [maxFrames] + 1 frames).
  static List<int> computeStripTimes(
    Duration duration, {
    int maxFrames = defaultMaxStripFrames,
  }) {
    final int durMs = duration.inMilliseconds;
    if (durMs <= 0) return const <int>[];
    final int ideal = (durMs ~/ maxFrames) < 1000 ? 1000 : durMs ~/ maxFrames;
    // Whole-second alignment: hover lookups are always on second marks.
    final int strideMs = (ideal + 999) ~/ 1000 * 1000;
    final List<int> times = <int>[];
    for (int t = 0; t < durMs; t += strideMs) {
      times.add(t);
    }
    final int last = durMs - 1000;
    if (last >= 0 && times.last != last) times.add(last);
    return times;
  }

  // ── The fine (hover) lane ─────────────────────────────────────────────

  /// Queues the exact second under the cursor. A no-op when the job is
  /// already in flight or queued, when the path is remote, or when the
  /// file has proven unable to decode.
  void requestFine(String path, int timeMs) {
    if (path.contains('://') || _deadPath == path) return;
    final _Job job = _Job(path, timeMs);
    if (_has(job.key)) return;
    if (_fineQueue.length >= _maxFineQueue) _fineQueue.removeAt(0);
    _fineQueue.add(job);
    _kick();
  }

  // ── The one worker ────────────────────────────────────────────────────

  void _kick() {
    if (_worker != null) return;
    _worker = _run().whenComplete(() {
      _worker = null;
      // A job enqueued while the last decode was in flight (a re-arm
      // during a slow decode) must start a fresh run — the run that
      // just exited is the old video's and bailed on its token.
      if (_fineQueue.isNotEmpty || _stripQueue.isNotEmpty) _kick();
    });
  }

  _Job? _nextJob() {
    if (_fineQueue.isNotEmpty) return _fineQueue.removeAt(0);
    if (_stripQueue.isNotEmpty) return _stripQueue.removeAt(0);
    return null;
  }

  Future<void> _run() async {
    while (true) {
      final _Job? job = _nextJob();
      if (job == null) return;
      final int token = _token;
      final String key = job.key;
      _inFlightKey = key;
      Uint8List? bytes;
      try {
        // Someone else (the other lane) may have filled it while queued —
        // reuse, do not decode twice.
        final Uint8List? cached = _cache[key];
        bytes = cached ?? await _extractor(job.path, job.timeMs);
      } catch (_) {
        bytes = null;
      }
      _inFlightKey = null;
      // The video changed mid-decode — the result (and everything still
      // queued) belongs to the previous file.
      if (token != _token) return;
      if (bytes == null) {
        _failures++;
        if (_failures >= _maxConsecutiveFailures) {
          _deadPath = job.path;
          _fineQueue.clear();
          _stripQueue.clear();
          return;
        }
        continue; // Nothing decoded, so nothing to pace behind.
      }
      _failures = 0;
      _put(key, bytes);
      final void Function(String, int, Uint8List)? notify = onFrame;
      notify?.call(job.path, job.timeMs, bytes);
      await Future<void>.delayed(pacing);
    }
  }

  /// The default decode — the same recipe the hover path has always used
  /// (240×135, JPEG 65). Runs on the plugin's native side, off the UI
  /// thread.
  static Future<Uint8List?> _pluginExtract(String path, int timeMs) {
    return FlutterVideoThumbnailPlus.thumbnailData(
      video: path,
      imageFormat: ImageFormat.jpeg,
      maxWidth: 240,
      maxHeight: 135,
      timeMs: timeMs,
      quality: 65,
    );
  }
}
