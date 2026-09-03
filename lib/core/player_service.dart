import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'media_utils.dart';

/// SALU's dedicated playback manager.
///
/// All player logic lives here — UI widgets never talk to `mpv` directly.
/// A single [Player] instance is created for the lifetime of the app and a
/// [VideoController] links the raw engine output to the Flutter canvas.
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
  late final VideoController videoController;

  // ── Lightweight UI-facing state ───────────────────────────────────────

  /// Title of the currently loaded media (file name without extension).
  final ValueNotifier<String?> currentTitle = ValueNotifier<String?>(null);

  /// Whether any media has been loaded this session.
  final ValueNotifier<bool> hasMedia = ValueNotifier<bool>(false);

  /// Whether media is actively playing right now (false while paused,
  /// stopped, or when nothing is loaded). Drives the title bar's
  /// "Pin (playback off)" mode.
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  /// The hardware decoder currently in use (e.g. `d3d11va`), `software`
  /// when the CPU is decoding, or `null` while unknown.
  final ValueNotifier<String?> activeHwdec = ValueNotifier<String?>(null);

  /// Current playback position — the single source of truth for the
  /// timeline. Updated from mpv events and glided between them by an
  /// interpolation ticker while playing, so the bar always moves smoothly.
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
  // mpv reports `time-pos` in coarse events; while playing we bridge the
  // gaps with a lightweight ticker so the fill advances every frame
  // instead of stepping.
  Timer? _ticker;
  Duration _anchor = Duration.zero;
  final Stopwatch _watch = Stopwatch();
  double _volumeBeforeMute = 100;

  void _init() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'SALU',
        logLevel: MPVLogLevel.warn,
        // Give mpv a generous demuxer cache for smooth local playback.
        bufferSize: 64 * 1024 * 1024,
      ),
    );

    // Hardware decoding ON by default — the GPU does the heavy lifting.
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
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
    });

    // Live "is playing" flag — false while paused or when nothing is loaded.
    _playingSub = player.stream.playing.listen((bool playing) {
      isPlaying.value = playing;
      if (playing) {
        // Re-anchor the glide: the stopwatch must not include the paused
        // time, or the bar would leap forward on resume.
        _watch
          ..reset()
          ..start();
        _startTicker();
      } else {
        _stopTicker();
      }
    });

    // Position events re-anchor the interpolation.
    _positionSub = player.stream.position.listen((Duration p) {
      if (p < Duration.zero) p = Duration.zero;
      position.value = p;
      _anchor = p;
      _watch
        ..reset()
        ..start();
    });

    // Duration changes (new file, metadata resolved, live streams, …).
    _durationSub = player.stream.duration.listen((Duration d) {
      duration.value = d < Duration.zero ? Duration.zero : d;
    });

    // Volume (0–100). Muting drives the volume to 0, unmuting restores it.
    _volumeSub = player.stream.volume.listen((double v) {
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
    await player.open(Media(path), play: play);
  }

  /// Open several files as a queue; playback starts with the first one.
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    final Playlist playlist =
        Playlist(paths.map((String p) => Media(p)).toList());
    await player.open(playlist, play: play);
  }

  /// Attach an external subtitle file (.srt/.ass/…) to the current media.
  Future<void> loadExternalSubtitle(String path) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(path));
  }

  // ── Basic transport ───────────────────────────────────────────────────

  Future<void> playOrPause() => player.playOrPause();

  Future<void> play() => player.play();

  Future<void> pause() => player.pause();

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

  /// Seek forward/backward by a relative amount (mouse-wheel scrub).
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

  Future<void> setVolume(double volume) => player.setVolume(volume);

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

  /// Release the native engine (called when the window closes).
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
