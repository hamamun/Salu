import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'media_utils.dart';

/// SALU's dedicated playback manager.
///
/// All player logic lives here — UI widgets never talk to `mpv` directly.
/// A single [Player] instance is created for the lifetime of the app and a
/// [VideoController] links the raw engine output to the Flutter canvas.
///
/// Every piece of UI-facing state is mirrored through [ValueNotifier]s so
/// widgets can rebuild reactively without listening to raw streams.
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

  // ── Media identity ─────────────────────────────────────────────────────

  /// Title of the currently loaded media (file name without extension).
  final ValueNotifier<String?> currentTitle = ValueNotifier<String?>(null);

  /// Whether any media has been loaded this session.
  final ValueNotifier<bool> hasMedia = ValueNotifier<bool>(false);

  /// The hardware decoder currently in use (e.g. `d3d11va`), `software`
  /// when the CPU is decoding, or `null` while unknown.
  final ValueNotifier<String?> activeHwdec = ValueNotifier<String?>(null);

  // ── Transport state ────────────────────────────────────────────────────

  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> completed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> buffered = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> rate = ValueNotifier<double>(1.0);

  // ── Audio state ────────────────────────────────────────────────────────

  /// Base volume 0–100 (edited from the OSC volume slider).
  final ValueNotifier<double> baseVolume = ValueNotifier<double>(100);

  /// Extra loudness 0–100 (edited from the Audio Tab). Effective mpv volume
  /// is `base + boost`, clamped to 200 thanks to `volume-max`.
  final ValueNotifier<double> volumeBoost = ValueNotifier<double>(0);

  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  // ── Playlist & tracks ──────────────────────────────────────────────────

  final ValueNotifier<Playlist?> playlist = ValueNotifier<Playlist?>(null);
  final ValueNotifier<Tracks?> tracks = ValueNotifier<Tracks?>(null);
  final ValueNotifier<Track?> currentTrack = ValueNotifier<Track?>(null);
  final ValueNotifier<PlaylistMode> playlistMode =
      ValueNotifier<PlaylistMode>(PlaylistMode.none);
  final ValueNotifier<bool> shuffle = ValueNotifier<bool>(false);

  // ── Codec / technical info (HUD) ───────────────────────────────────────

  final ValueNotifier<VideoParams?> videoParams = ValueNotifier<VideoParams?>(null);
  final ValueNotifier<AudioParams?> audioParams = ValueNotifier<AudioParams?>(null);
  final ValueNotifier<double?> audioBitrate = ValueNotifier<double?>(null);
  final ValueNotifier<int?> width = ValueNotifier<int?>(null);
  final ValueNotifier<int?> height = ValueNotifier<int?>(null);

  // ── Modes ──────────────────────────────────────────────────────────────

  /// True when the loaded media has no video stream (MP3/FLAC → Music Mode).
  final ValueNotifier<bool> isMusicMode = ValueNotifier<bool>(false);

  final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  /// True while the mini always-on-top window (SALU's PiP) is active.
  final ValueNotifier<bool> pip = ValueNotifier<bool>(false);

  // PiP bookkeeping so we can restore the window afterwards.
  Size? _prePipSize;
  Offset? _prePipPosition;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

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

    // Allow volume up to 200% so the Phase 4 "Volume Boost" slider works.
    unawaited(_setMpvProperty('volume-max', '200'));

    _subs.add(player.stream.playlist.listen(_onPlaylist));
    _subs.add(player.stream.playing.listen((bool v) => playing.value = v));
    _subs.add(player.stream.completed.listen((bool v) => completed.value = v));
    _subs.add(player.stream.buffering.listen((bool v) => buffering.value = v));
    _subs.add(player.stream.position.listen((Duration v) => position.value = v));
    _subs.add(player.stream.duration.listen((Duration v) => duration.value = v));
    _subs.add(player.stream.buffer.listen((Duration v) => buffered.value = v));
    _subs.add(player.stream.rate.listen((double v) => rate.value = v));
    _subs.add(player.stream.playlistMode.listen((PlaylistMode v) => playlistMode.value = v));
    _subs.add(player.stream.shuffle.listen((bool v) => shuffle.value = v));
    _subs.add(player.stream.tracks.listen((Tracks v) {
      tracks.value = v;
      _updateMusicMode();
    }));
    _subs.add(player.stream.track.listen((Track v) => currentTrack.value = v));
    _subs.add(player.stream.videoParams.listen((VideoParams v) => videoParams.value = v));
    _subs.add(player.stream.audioParams.listen((AudioParams v) => audioParams.value = v));
    _subs.add(player.stream.audioBitrate.listen((double? v) => audioBitrate.value = v));
    _subs.add(player.stream.width.listen((int? v) {
      width.value = v;
      if (v != null && v > 0) {
        unawaited(_refreshHwdecStatus());
      }
    }));
    _subs.add(player.stream.height.listen((int? v) => height.value = v));
    _subs.add(player.stream.error.listen((String message) {
      debugPrint('[SALU/mpv] error: $message');
    }));
  }

  void _onPlaylist(Playlist p) {
    playlist.value = p;
    if (p.medias.isEmpty) return;
    final int index = p.index.clamp(0, p.medias.length - 1).toInt();
    final String uri = p.medias[index].uri;
    final String title = MediaUtils.displayName(uri);
    currentTitle.value = title;
    hasMedia.value = true;
    _updateMusicMode();
    unawaited(_setWindowTitle('$title — SALU'));
  }

  void _updateMusicMode() {
    final Tracks? t = tracks.value;
    final bool music = hasMedia.value && (t == null || t.video.isEmpty);
    if (isMusicMode.value != music) {
      isMusicMode.value = music;
    }
  }

  /// URI of the media currently playing, if any.
  String? get currentMediaUri {
    final Playlist? p = playlist.value;
    if (p == null || p.medias.isEmpty) return null;
    final int index = p.index.clamp(0, p.medias.length - 1).toInt();
    return p.medias[index].uri;
  }

  bool get hasVideo => tracks.value?.video.isNotEmpty ?? false;

  // ── Opening media ─────────────────────────────────────────────────────

  /// Open a single local file or network URL and start playing.
  Future<void> openPath(String path, {bool play = true}) async {
    await player.open(Media(path), play: play);
  }

  /// Open several files as a queue; playback starts with the first one.
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    final Playlist p = Playlist(paths.map((String path) => Media(path)).toList());
    await player.open(p, play: play);
  }

  /// Attach an external subtitle file (.srt/.ass/…) to the current media.
  Future<void> loadExternalSubtitle(String path) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(path));
  }

  // ── Transport ─────────────────────────────────────────────────────────

  Future<void> play() => player.play();

  Future<void> pause() => player.pause();

  Future<void> playOrPause() => player.playOrPause();

  Future<void> seek(Duration target) => player.seek(target);

  /// Seek relative to the current position (clamped to [0, duration]).
  Future<void> seekBy(Duration offset) async {
    Duration target = position.value + offset;
    if (target < Duration.zero) target = Duration.zero;
    final Duration max = duration.value;
    if (max > Duration.zero && target > max) target = max;
    await player.seek(target);
  }

  Future<void> next() => player.next();

  Future<void> previous() => player.previous();

  Future<void> jump(int index) => player.jump(index);

  Future<void> addToPlaylist(String path) => player.add(Media(path));

  Future<void> addAllToPlaylist(List<String> paths) async {
    for (final String path in paths) {
      await player.add(Media(path));
    }
  }

  Future<void> removeFromPlaylist(int index) => player.remove(index);

  Future<void> setPlaylistMode(PlaylistMode mode) => player.setPlaylistMode(mode);

  Future<void> setShuffle(bool value) => player.setShuffle(value);

  Future<void> setRate(double value) => player.setRate(value);

  // ── Volume & mute ─────────────────────────────────────────────────────

  Future<void> setBaseVolume(double value) async {
    baseVolume.value = value.clamp(0.0, 100.0).toDouble();
    await _applyVolume();
  }

  Future<void> setVolumeBoost(double value) async {
    volumeBoost.value = value.clamp(0.0, 100.0).toDouble();
    await _applyVolume();
  }

  Future<void> _applyVolume() async {
    final double effective = (baseVolume.value + volumeBoost.value).clamp(0.0, 200.0).toDouble();
    await player.setVolume(effective);
  }

  Future<void> setMuted(bool value) async {
    await _setMpvProperty('mute', value ? 'yes' : 'no');
    muted.value = value;
  }

  Future<void> toggleMute() => setMuted(!muted.value);

  // ── Track selection ───────────────────────────────────────────────────

  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);

  Future<void> setSubtitleTrack(SubtitleTrack track) => player.setSubtitleTrack(track);

  Future<void> disableSubtitles() => player.setSubtitleTrack(SubtitleTrack.no());

  // ── View modes ────────────────────────────────────────────────────────

  Future<void> toggleFullscreen() async {
    if (!Platform.isWindows) return;
    final bool next = !fullscreen.value;
    await windowManager.setFullScreen(next);
    fullscreen.value = next;
  }

  /// SALU's PiP: shrink the window to a small always-on-top box and back.
  /// (True OS-level PiP isn't exposed to borderless Flutter windows, so a
  /// mini always-on-top window is the practical IINA-style equivalent.)
  Future<void> togglePip() async {
    if (!Platform.isWindows) return;
    if (pip.value) {
      await windowManager.setAlwaysOnTop(false);
      final Size? size = _prePipSize;
      final Offset? offset = _prePipPosition;
      if (size != null) await windowManager.setSize(size);
      if (offset != null) await windowManager.setPosition(offset);
      _prePipSize = null;
      _prePipPosition = null;
      pip.value = false;
    } else {
      _prePipSize = await windowManager.getSize();
      _prePipPosition = await windowManager.getPosition();
      await windowManager.setSize(const Size(480, 270));
      await windowManager.setAlwaysOnTop(true);
      pip.value = true;
    }
  }

  // ── Phase 4 · Video tab (mpv properties) ──────────────────────────────

  bool _hflip = false;
  bool _vflip = false;

  Future<void> setVideoRotation(int degrees) async {
    await _setMpvProperty('video-rotate', '$degrees');
  }

  Future<void> setHorizontalFlip(bool enabled) async {
    _hflip = enabled;
    await _applyVf();
  }

  Future<void> setVerticalFlip(bool enabled) async {
    _vflip = enabled;
    await _applyVf();
  }

  Future<void> _applyVf() async {
    final List<String> parts = <String>[
      if (_hflip) 'hflip',
      if (_vflip) 'vflip',
    ];
    await _setMpvProperty('vf', parts.join(','));
  }

  /// Force an aspect ratio, or restore automatic handling with `null`.
  Future<void> setAspectOverride(String? aspect) async {
    await _setMpvProperty('video-aspect-override', aspect ?? 'no');
  }

  // ── Phase 4 · Audio tab ───────────────────────────────────────────────

  Future<void> setAudioDelay(double seconds) async {
    await _setMpvProperty('audio-delay', seconds.toStringAsFixed(3));
  }

  /// Apply a 10-band equalizer curve (gains in dB).
  Future<void> setEqualizer(List<double> gains) async {
    final List<String> filters = <String>[];
    for (int i = 0; i < gains.length; i++) {
      final double g = gains[i].clamp(-12.0, 12.0).toDouble();
      filters.add('equalizer=f=${_bandFrequency(i)}:width_type=o:width=1:g=$g');
    }
    await _setMpvProperty('af', filters.join(','));
  }

  static String _bandFrequency(int index) {
    const List<String> freqs = <String>[
      '31.25', '62.5', '125', '250', '500', '1000', '2000', '4000', '8000', '16000',
    ];
    return freqs[index.clamp(0, freqs.length - 1).toInt()];
  }

  // ── Phase 4 · Subtitle tab ────────────────────────────────────────────

  Future<void> setSubtitleDelay(double seconds) async {
    await _setMpvProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  /// Subtitle vertical position. mpv's `sub-pos` is 0–100 (100 = bottom).
  Future<void> setSubtitlePosition(double percent) async {
    await _setMpvProperty('sub-pos', percent.toStringAsFixed(1));
  }

  // ── mpv property helpers ──────────────────────────────────────────────

  NativePlayer? get _native {
    final PlatformPlayer? platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> _setMpvProperty(String name, String value) async {
    try {
      await _native?.setProperty(name, value);
    } catch (error) {
      debugPrint('[SALU/mpv] setProperty "$name" failed: $error');
    }
  }

  /// Reads a raw mpv property as a string (e.g. `video-codec`, `mute`).
  Future<String?> getMpvProperty(String name) async {
    try {
      return await _native?.getProperty(name);
    } catch (_) {
      return null;
    }
  }

  // ── Hardware acceleration check (Phase 2 requirement) ────────────────

  /// Queries mpv for the decoder that is actually active right now.
  Future<void> _refreshHwdecStatus() async {
    final String? value = await getMpvProperty('hwdec-current');
    if (value == null) return;
    final String status = (value.isEmpty || value == 'no') ? 'software' : value;
    activeHwdec.value = status;
    debugPrint('[SALU] hardware decoding: $status');
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
    for (final StreamSubscription<dynamic> sub in _subs) {
      await sub.cancel();
    }
    await player.dispose();
  }
}
