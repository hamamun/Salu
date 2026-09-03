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

  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<bool>? _playingSub;

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

  Future<void> seek(Duration position) => player.seek(position);

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
    await _playlistSub?.cancel();
    await _errorSub?.cancel();
    await _widthSub?.cancel();
    await _playingSub?.cancel();
    await player.dispose();
  }
}
