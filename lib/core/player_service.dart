import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/osd/osd_controller.dart';
import 'media_utils.dart';
import 'queue_service.dart';
import 'resume_service.dart';

/// SALU's transport states. Three live states plus *idle* (nothing
/// loaded at all). **Stop is not pause and not start-over** — it parks
/// the queue: the engine releases the item, the queue stays loaded and
/// the exact position is remembered (see [PlayerService.stop]).
enum TransportState { idle, stopped, paused, playing }

/// The in-session memory taken by Stop: what was playing, where, for
/// how long. Consumed by Play-again-after-Stop; mirrored to disk the
/// moment it is taken so closing SALU right after a Stop still resumes.
class StopMemory {
  const StopMemory({
    required this.path,
    required this.position,
    required this.duration,
  });

  final String path;
  final Duration position;
  final Duration duration;
}

/// SALU's dedicated playback manager.
///
/// All player logic lives here — UI widgets never talk to `mpv` directly.
/// A single [Player] instance is created for the lifetime of the app and a
/// [VideoController] links the raw engine output to the Flutter canvas.
///
/// SALU owns the queue: [QueueService] holds the ordered paths above the
/// engine (mpv's own playlist does not survive `stop()`), mpv is handed
/// the full playlist while an item is loaded (native auto-advance and
/// gapless audio stay), and after a Stop the queue is re-opened at the
/// target index with the stop memory carried as `Media(start:)`.
class PlayerService {
  PlayerService._internal() {
    _init();
  }

  /// The one and only player instance for the whole app (single window,
  /// single engine).
  static final PlayerService instance = PlayerService._internal();

  /// Core `media_kit` player (wraps libmpv).
  late final Player player;

  /// Bridges raw engine frames onto the Flutter widget tree.
  /// Created lazily (on first access) so ANGLE/D3D11 surfaces aren't
  /// initialized eagerly at startup when no video is loaded.
  VideoController? _videoController;

  VideoController get videoController => _videoController ??= VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

  // ── Lightweight UI-facing state ───────────────────────────────────────

  /// Title of the currently loaded media (file name without extension).
  /// `null` while idle **and while stopped** — the stopped window is the
  /// initial window; its title bar and window title read `SALU`.
  final ValueNotifier<String?> currentTitle = ValueNotifier<String?>(null);

  /// Whether the engine currently holds an item. False after Stop (that
  /// is what shows the landing canvas); "is anything loaded at all" is
  /// answered by [QueueService.hasQueue].
  final ValueNotifier<bool> hasMedia = ValueNotifier<bool>(false);

  /// Whether media is actively playing right now. Drives the title
  /// bar's "Pin (playback off)" mode.
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  /// The full transport state (idle · stopped · paused · playing) — the
  /// one notifier the control row's enable matrix reads.
  final ValueNotifier<TransportState> transportState =
      ValueNotifier<TransportState>(TransportState.idle);

  /// Absolute path (or URL) of the item the engine holds; `null` while
  /// idle/stopped.
  final ValueNotifier<String?> currentPath = ValueNotifier<String?>(null);

  /// The parked position taken by Stop, until Play resumes it.
  final ValueNotifier<StopMemory?> stopMemory =
      ValueNotifier<StopMemory?>(null);

  /// The hardware decoder currently in use (e.g. `d3d11va`), `software`
  /// when the CPU is decoding, or `null` while unknown.
  final ValueNotifier<String?> activeHwdec = ValueNotifier<String?>(null);

  /// Current playback position — the single source of truth for the
  /// timeline.
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);

  /// Total duration of the loaded media (`Duration.zero` while unknown).
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);

  /// Volume level 0–100 (mpv's native range).
  final ValueNotifier<double> volumeLevel = ValueNotifier<double>(100);

  /// Mute state. Implemented locally (mute = volume 0 + flag) because
  /// mpv's mute property is not exposed as a dedicated stream here.
  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);

  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _volumeSub;

  // ── Smooth position interpolation ─────────────────────────────────────
  Timer? _ticker;
  Duration _anchor = Duration.zero;
  final Stopwatch _watch = Stopwatch();
  double _volumeBeforeMute = 100;

  /// Items given a `Media(start:)` whose arrival should fire the Resume
  /// toast when the playlist stream lands on them (normalized path →
  /// resumed position). Filled by every open path; consumed once.
  final Map<String, Duration> _pendingResume = <String, Duration>{};

  /// Fallback for containers that ignore `Media(start:)`: normalized
  /// path → expected offset, checked once when a real duration arrives.
  final Map<String, Duration> _expectedStartAfterLoad =
      <String, Duration>{};

  /// Index announced by the last playlist event (switch-flush trigger).
  int _lastAnnouncedIndex = -1;

  /// mutes volume-stream echo while the engine is being stopped
  /// (mpv may re-emit 100 after `stop()`; the outline flags this).
  bool _suppressVolumeEvents = false;

  /// True between an open-with-play and the engine confirming — keeps
  /// the optimistic `playing` state from flickering to `paused`.
  bool _openingWithPlay = false;

  void _init() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'SALU',
        logLevel: MPVLogLevel.warn,
        // Give mpv a generous demuxer cache for smooth local playback.
        bufferSize: 64 * 1024 * 1024,
      ),
    );

    // Keep window title & UI state in sync with whatever is playing.
    _playlistSub = player.stream.playlist.listen((Playlist playlist) {
      if (playlist.medias.isEmpty) return;
      final int index =
          playlist.index.clamp(0, playlist.medias.length - 1).toInt();
      final String uri = playlist.medias[index].uri;
      final String title = MediaUtils.displayName(uri);
      currentTitle.value = title;
      hasMedia.value = true;
      unawaited(_setWindowTitle('$title — SALU'));

      // Path + queue mirror (only when mpv holds OUR queue).
      final String key = normalizePathKey(uri);
      currentPath.value = key;
      final QueueService queue = QueueService.instance;
      if (queue.paths.value.length == playlist.medias.length) {
        queue.setIndex(index);
      }

      // A different item is loading — flush the previous one's resume
      // state to disk immediately (switch flush).
      if (_lastAnnouncedIndex != index) {
        _lastAnnouncedIndex = index;
        unawaited(ResumeService.instance.flush());
      }

      // Resume: this item was opened with a remembered offset → toast.
      final Duration? resumeAt = _pendingResume.remove(key);
      if (resumeAt != null) {
        OsdController.instance
            .show(OsdResumeCard(position: resumeAt));
      }
    });

    // Live "is playing" flag — false while paused or when nothing is
    // loaded.
    _playingSub = player.stream.playing.listen((bool playing) {
      isPlaying.value = playing;
      if (playing) {
        _openingWithPlay = false;
        // Re-anchor the glide: the stopwatch must not include the
        // paused time, or the bar would leap forward on resume.
        _watch
          ..reset()
          ..start();
        _startTicker();
      } else {
        _stopTicker();
        // Pausing is a resume flush point.
        unawaited(ResumeService.instance.flush());
      }
      _refreshTransportState();
    });

    // Position events re-anchor the interpolation and feed the resume
    // store (memory every tick; the disk write is throttled inside).
    _positionSub = player.stream.position.listen((Duration p) {
      if (p < Duration.zero) p = Duration.zero;
      position.value = p;
      _anchor = p;
      _watch
        ..reset()
        ..start();
      final String? path = currentPath.value;
      final Duration dur = duration.value;
      if (path != null && dur > Duration.zero && p > Duration.zero) {
        ResumeService.instance.update(path, p, dur);
      }
    });

    // Duration changes (new file, metadata resolved, live streams, …).
    _durationSub = player.stream.duration.listen((Duration d) {
      if (d < Duration.zero) d = Duration.zero;
      duration.value = d;
      // Fallback for containers that ignore Media(start:): seek once,
      // on the first real duration, if the engine ignored the offset.
      final String? path = currentPath.value;
      if (d > Duration.zero && path != null) {
        final Duration? expected =
            _expectedStartAfterLoad.remove(normalizePathKey(path));
        if (expected != null &&
            (position.value - expected).abs() >
                const Duration(seconds: 3)) {
          unawaited(seekTo(expected));
        }
      }
    });

    // Volume (0–100). Muting drives the volume to 0, unmuting restores
    // it.
    _volumeSub = player.stream.volume.listen((double v) {
      if (_suppressVolumeEvents) return;
      if (v < 0) v = 0;
      if (v > 100) v = 100;
      volumeLevel.value = v;
      if (!isMuted.value && v > 0) _volumeBeforeMute = v;
    });

    // Once real frames arrive, ask mpv which hardware decoder kicked in.
    _widthSub = player.stream.width.listen((int? width) {
      if (width != null && width > 0) {
        unawaited(_refreshHwdecStatus());
      }
    });

    _errorSub = player.stream.error.listen((String message) {
      debugPrint('[SALU/mpv] error: $message');
    });

    // mpv's default already keeps the file open after the last frame so
    // the paused end-frame stays visible; make it explicit.
    unawaited(_ensureKeepOpen());
  }

  // ── Path normalization ────────────────────────────────────────────────

  /// Canonical map key for resume/queue bookkeeping: forward slashes,
  /// no `file://` scheme, no leading `/` before a drive letter.
  static String normalizePathKey(String p) {
    String s = p.replaceAll('\\', '/');
    const String scheme = 'file://';
    if (s.startsWith('$scheme/')) {
      s = s.substring(scheme.length + 1);
    } else if (s.startsWith(scheme)) {
      s = s.substring(scheme.length);
    }
    // "/C:/x/y.mkv" (URI residue) → "C:/x/y.mkv".
    if (s.length >= 3 &&
        s.startsWith('/') &&
        s.codeUnitAt(1) >= 0x41 &&
        s.codeUnitAt(1) <= 0x7A &&
        s.codeUnitAt(2) == 0x3A) {
      s = s.substring(1);
    }
    return s;
  }

  // ── Transport state ───────────────────────────────────────────────────

  void _refreshTransportState() {
    if (hasMedia.value) {
      transportState.value = _openingWithPlay || isPlaying.value
          ? TransportState.playing
          : TransportState.paused;
    } else if (stopMemory.value != null) {
      transportState.value = TransportState.stopped;
    } else {
      transportState.value = TransportState.idle;
    }
  }

  // ── Position gliding ──────────────────────────────────────────────────

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      // Advance the cached position by real wall-clock time since the
      // last mpv event — smooth, and drifts back to mpv's truth on the
      // next position event.
      if (!isPlaying.value) return;
      final Duration dur = duration.value;
      if (dur <= Duration.zero) return;
      Duration p = _anchor + _watch.elapsed;
      if (p < Duration.zero) p = Duration.zero;
      if (p > dur) p = dur;
      if (p != position.value) position.value = p;
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _ensureKeepOpen() async {
    final PlatformPlayer? platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('keep-open', 'yes');
      } catch (_) {
        // Harmless if unavailable — mpv's default is usually `yes` anyway.
      }
    }
  }

  // ── Opening media ─────────────────────────────────────────────────────

  /// Open a single local file or network URL and start playing.
  Future<void> openPath(String path, {bool play = true}) async {
    QueueService.instance.setQueue(<String>[normalizePathKey(path)], 0);
    await _openQueueAt(0, play: play);
  }

  /// Open several files as a queue; playback starts with the first one.
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    QueueService.instance.setQueue(
      paths.map(normalizePathKey).toList(growable: false),
      0,
    );
    await _openQueueAt(0, play: play);
  }

  /// The one open path: hands mpv the FULL queue (native auto-advance
  /// and gapless audio stay), points it at [index], and carries any
  /// remembered offset as `Media(start:)` — so resuming never flashes.
  ///
  /// [start] overrides the disk memory for the target item (zero =
  /// deliberate restart); `null` = consult the disk memory, and when
  /// one exists the Resume toast fires on arrival.
  Future<void> _openQueueAt(
    int index, {
    bool play = true,
    Duration? start,
  }) async {
    final QueueService queue = QueueService.instance;
    final List<String> paths = queue.paths.value;
    if (paths.isEmpty) return;
    final int idx = index.clamp(0, paths.length - 1).toInt();
    queue.setIndex(idx);

    // Decide the target's offset: explicit > disk memory.
    Duration? targetStart = start;
    bool targetFromDisk = false;
    if (targetStart == null) {
      final Duration? saved =
          ResumeService.instance.savedPositionFor(paths[idx]);
      if (saved != null) {
        targetStart = saved;
        targetFromDisk = true;
      }
    }

    // Build the full playlist; every item with a memory gets its start.
    final List<Media> medias = <Media>[];
    for (int i = 0; i < paths.length; i++) {
      final String p = paths[i];
      final bool isTarget = i == idx;
      final Duration? offset = isTarget
          ? targetStart
          : ResumeService.instance.savedPositionFor(p);
      if (offset != null && offset > Duration.zero) {
        medias.add(Media(p, start: offset));
        final String key = normalizePathKey(p);
        _pendingResume[key] = offset;
        // Fallback expectation for every item given a start (the target
        // now, auto-advanced items later).
        _expectedStartAfterLoad[key] = offset;
      } else {
        medias.add(Media(p));
      }
    }
    // A deliberate restart clears the item's stale disk memory so it
    // cannot resurrect old state on a later open.
    if (targetFromDisk == false && start == Duration.zero) {
      ResumeService.instance.remove(paths[idx]);
    }

    stopMemory.value = null; // opening anything consumes a stop memory
    _openingWithPlay = play;
    hasMedia.value = true;
    _refreshTransportState();
    await player.open(Playlist(medias, index: idx), play: play);
  }

  // ── Basic transport ───────────────────────────────────────────────────

  Future<void> playOrPause() => player.playOrPause();

  Future<void> play() => player.play();

  Future<void> pause() => player.pause();

  /// **Stop — the third state.** Parks the queue: the engine releases
  /// the item (canvas → the initial SALU window), the queue stays
  /// loaded, the exact position is remembered in the session stop
  /// memory AND mirrored to disk, Prev/Next/Play/sound stay live, and
  /// Play-again resumes from the remembered position.
  Future<void> stop() async {
    final TransportState state = transportState.value;
    if (state != TransportState.playing && state != TransportState.paused) {
      return;
    }

    // 1 · Take the memory BEFORE the engine resets.
    final String? path = currentPath.value;
    final Duration pos = position.value;
    final Duration dur = duration.value;
    if (path != null) {
      stopMemory.value =
          StopMemory(path: path, position: pos, duration: dur);
      if (!path.contains('://')) {
        ResumeService.instance.update(path, pos, dur);
      }
      unawaited(ResumeService.instance.flush());
    }

    // 2 · Release the engine. The landing canvas (opaque) covers the
    //    stale last frame immediately.
    hasMedia.value = false;
    isPlaying.value = false;
    _stopTicker();
    _suppressVolumeEvents = true;
    await player.stop();

    // 3 · Zero the transport surface; title bar reads SALU again.
    currentTitle.value = null;
    currentPath.value = null;
    position.value = Duration.zero;
    _anchor = Duration.zero;
    _watch.reset();
    duration.value = Duration.zero;
    _pendingResume.clear();
    _expectedStartAfterLoad.clear();
    _openingWithPlay = false;
    transportState.value = TransportState.stopped;
    unawaited(_setWindowTitle('SALU'));

    // 4 · Re-assert the volume (mpv's state reset may re-emit 100).
    await player.setVolume(isMuted.value ? 0 : volumeLevel.value);
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      _suppressVolumeEvents = false;
    });
  }

  /// Play again after a Stop — resumes the parked item at its exact
  /// position (the Resume toast fires via the pending-resume path).
  /// A memory under the shared threshold (or a stream with no duration)
  /// simply starts the item from the beginning.
  Future<void> playFromStop() async {
    final StopMemory? mem = stopMemory.value;
    if (mem == null) return;
    final QueueService queue = QueueService.instance;
    int idx = queue.paths.value.indexOf(mem.path);
    if (idx < 0) idx = queue.hasCurrent ? queue.index.value : 0;

    final bool keep =
        mem.duration > Duration.zero && _withinKeepWindow(mem.position, mem.duration);
    stopMemory.value = null; // consumed
    await _openQueueAt(idx, start: keep ? mem.position : Duration.zero);
  }

  /// The shared resume threshold: `5 s ≤ position ≤ duration − 10 s`.
  static bool _withinKeepWindow(Duration pos, Duration dur) {
    if (pos < const Duration(seconds: 5)) return false;
    if (dur - pos < const Duration(seconds: 10)) return false;
    return true;
  }

  /// Whether Play-after-Stop will resume at the memory's position:
  /// the shared threshold applied to the stop memory (a stream with no
  /// duration never resumes — it simply starts over).
  bool get stopMemoryWillResume {
    final StopMemory? mem = stopMemory.value;
    if (mem == null || mem.duration <= Duration.zero) return false;
    return _withinKeepWindow(mem.position, mem.duration);
  }

  /// Previous item — one rule in every state: position (the stop memory
  /// while stopped) > 3 s, or first item → plays THIS item from `0:00`;
  /// otherwise plays the previous item (which follows the normal open
  /// path — if the disk remembers it, it resumes with the toast).
  Future<void> previous() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return;
    final int idx = queue.index.value;
    final StopMemory? mem = stopMemory.value;
    final Duration pos = (transportState.value == TransportState.stopped &&
            mem != null)
        ? mem.position
        : position.value;
    if (pos > const Duration(seconds: 3) || idx <= 0) {
      stopMemory.value = null;
      await _openQueueAt(idx <= 0 ? 0 : idx, start: Duration.zero);
    } else {
      stopMemory.value = null;
      await _openQueueAt(idx - 1);
    }
  }

  /// Next item — dimmed in the UI when there is none; identical in
  /// every state.
  Future<void> next() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasNext) return;
    stopMemory.value = null;
    await _openQueueAt(queue.index.value + 1);
  }

  /// Jump the timeline to an exact position.
  ///
  /// Clamps to the media bounds and reflects the target in the UI state
  /// immediately (the authoritative mpv position event follows within
  /// milliseconds). Seeking never pauses playback.
  Future<void> seekTo(Duration target) async {
    if (!hasMedia.value) return;
    final Duration dur = duration.value;
    Duration t = target;
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    position.value = t;
    _anchor = t;
    _watch
      ..reset()
      ..start();
    await player.seek(t);
  }

  /// Seek forward/backward by a relative amount (mouse-wheel scrub and
  /// the seek ramp).
  Future<void> seekBy(Duration delta) => seekTo(position.value + delta);

  // ── Volume ────────────────────────────────────────────────────────────

  /// Mute toggle. Mute = remember the level, drop to 0; unmute restores.
  Future<void> toggleMute() async {
    if (isMuted.value) {
      isMuted.value = false;
      await player.setVolume(_volumeBeforeMute.clamp(0, 100).toDouble());
    } else {
      _volumeBeforeMute = volumeLevel.value > 0 ? volumeLevel.value : 100;
      isMuted.value = true;
      await player.setVolume(0);
    }
  }

  /// Set volume from the UI (0–100). Dragging the volume bar unmutes.
  Future<void> setVolumeUI(double volume) async {
    final double v = volume.clamp(0, 100).toDouble();
    if (v > 0 && isMuted.value) isMuted.value = false;
    volumeLevel.value = v;
    if (v > 0) _volumeBeforeMute = v;
    await player.setVolume(v);
  }

  /// Volume ±[delta] (keyboard ↑/↓ and the OSD cards). Unmutes when the
  /// result leaves silence.
  Future<void> stepVolume(int delta) async {
    final double base = isMuted.value ? 0 : volumeLevel.value;
    await setVolumeUI(base + delta);
  }

  Future<void> setVolume(double volume) => player.setVolume(volume);

  /// Load an external subtitle file (SRT/ASS/etc.) onto the current media.
  Future<void> loadExternalSubtitle(String path) async {
    String normalized = path.replaceAll('\\', '/');
    final String uri = path.contains('://')
        ? path
        : Uri.file(normalized).toString();
    await player.setSubtitleTrack(
      SubtitleTrack.uri(
        uri,
        title: MediaUtils.displayName(path),
      ),
    );
  }

  // ── Hardware acceleration check (Phase 2 requirement) ────────────────

  /// Queries mpv for the decoder that is actually active right now.
  Future<void> _refreshHwdecStatus() async {
    final PlatformPlayer? platform = player.platform;
    if (platform is NativePlayer) {
      try {
        final String value = await platform.getProperty('hwdec-current');
        final String status =
            (value.isEmpty || value == 'no') ? 'software' : value;
        activeHwdec.value = status;
        debugPrint('[SALU] hardware decoding: $status');
      } catch (error) {
        debugPrint('[SALU] hwdec query failed: $error');
      }
    }
  }

  Future<void> _setWindowTitle(String title) async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.setTitle(title);
    } catch (_) {
      // Window may not be ready yet — harmless.
    }
  }

  /// Release the native engine. Not on the close path — `_CloseGuard`
  /// exits the process directly and the OS reclaims the engine — kept
  /// for programmatic shutdown (tests, embedded use).
  Future<void> dispose() async {
    _stopTicker();
    await _playlistSub?.cancel();
    await _errorSub?.cancel();
    await _widthSub?.cancel();
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _volumeSub?.cancel();
    await player.dispose();
  }
}
