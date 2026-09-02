import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'app_prefs.dart';
import 'history_manager.dart';
import 'hwdec_manager.dart';
import 'language_utils.dart';
import 'lyrics_parser.dart';
import 'media_utils.dart';
import 'smart_queue_service.dart';
import 'subtitles_api.dart';
import 'updater_service.dart';

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

  /// True when the current media has no known duration (live stream).
  /// The OSC hides the timeline and seek buttons in this state (Phase 6).
  final ValueNotifier<bool> isLiveStream = ValueNotifier<bool>(false);

  // ── Phase 5 · notifications for the UI layer ──────────────────────────

  /// Hook the UI layer installs so the core can flash OSD messages (e.g.
  /// "Resumed from 12:04") without importing any widget code.
  void Function(String message)? onOsdMessage;

  void emitOsd(String message) {
    final void Function(String)? hook = onOsdMessage;
    if (hook != null) {
      hook(message);
    } else {
      debugPrint('[SALU] $message');
    }
  }

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
    _subs.add(player.stream.playing.listen((bool v) {
      playing.value = v;
      if (!v) _flushHistory(force: true);
    }));
    _subs.add(player.stream.completed.listen((bool v) {
      completed.value = v;
      if (v) _flushHistory(force: true);
    }));
    _subs.add(player.stream.buffering.listen((bool v) => buffering.value = v));
    _subs.add(player.stream.position.listen((Duration v) {
      position.value = v;
      _rememberPosition();
    }));
    _subs.add(player.stream.duration.listen((Duration v) {
      duration.value = v;
      // A live stream (IPTV/HLS) reports no duration — Phase 6 uses this to
      // strip the timeline and seek controls out of the OSC.
      isLiveStream.value = hasMedia.value && v <= Duration.zero;
      _maybeResume();
    }));
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

    // A new item started — flush the previous one's position and arm the
    // resume logic for this one (Phase 5 · Step 3).
    if (uri != _resumeTargetUri) {
      _flushHistory(force: true);
      _resumeTargetUri = uri;
      _resumeHandled = false;
      _attachSidecarSubtitle(uri);
      // Phase 7 · Step 1 — silently look for `song.lrc` beside the track.
      LyricsController.instance.onMediaOpened(uri);
      // Phase 7 · Step 5 — background OpenSubtitles fetch (when enabled).
      unawaited(_maybeAutoDownloadSubtitles(uri));
    }

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

  // ── Phase 5 · Seamless resume & history ───────────────────────────────

  /// URI whose resume position hasn't been applied yet.
  String? _resumeTargetUri;
  bool _resumeHandled = false;

  /// URI whose position we are currently recording.
  String? _historyUri;
  Duration _historyPosition = Duration.zero;
  Duration _historyDuration = Duration.zero;

  /// Applies the stored playback position once mpv reports a real duration.
  void _maybeResume() {
    final String? uri = _resumeTargetUri;
    if (uri == null || _resumeHandled) return;
    if (duration.value <= Duration.zero) return;
    _resumeHandled = true;

    if (!AppPrefs.instance.resumeLastPosition) return;
    if (_isNetworkUri(uri)) return;

    final Duration? target = HistoryManager.instance.resumePositionFor(uri);
    if (target == null || target >= duration.value) return;

    // No pop-up — IINA-style silent resume plus a quick OSD flash.
    unawaited(seek(target));
    emitOsd('Resumed from ${MediaUtils.formatDuration(target)}');
  }

  void _rememberPosition() {
    final String? uri = currentMediaUri;
    if (uri == null || _isNetworkUri(uri)) return;
    _historyUri = uri;
    _historyPosition = position.value;
    _historyDuration = duration.value;
    if (!AppPrefs.instance.resumeLastPosition) return;
    if (_historyDuration <= Duration.zero) return;
    HistoryManager.instance.remember(
      uri: uri,
      position: _historyPosition,
      duration: _historyDuration,
    );
  }

  /// Writes the pending position immediately (track change / app exit).
  void _flushHistory({bool force = false}) {
    final String? uri = _historyUri;
    if (uri == null) return;
    if (!AppPrefs.instance.resumeLastPosition) return;
    if (_historyDuration <= Duration.zero) return;
    HistoryManager.instance.remember(
      uri: uri,
      position: _historyPosition,
      duration: _historyDuration,
      force: force,
    );
  }

  /// Auto-loads `movie.srt` sitting next to `movie.mp4` (Phase 5 · Step 1/3).
  void _attachSidecarSubtitle(String uri) {
    if (_isNetworkUri(uri)) return;
    // mpv may report the item back as a `file:///…` URI — normalise first.
    final String path = SmartQueueService.toLocalPath(uri);
    final String? sidecar =
        SmartQueueService.findSidecar(path, MediaUtils.subtitleExtensions);
    if (sidecar == null) return;
    unawaited(loadExternalSubtitle(sidecar));
  }

  // ── Phase 7 · Step 5: silent subtitle auto-download ──────────────────

  String? _autoSubPendingPath;

  /// When "Auto-download Subtitles on Video Load" is enabled, silently pings
  /// OpenSubtitles with the file hash. Only a perfect hash match in the
  /// user's default language is downloaded — quietly, next to the video, so
  /// the sidecar logic picks it up for good and it is never fetched twice.
  Future<void> _maybeAutoDownloadSubtitles(String uri) async {
    if (!AppPrefs.instance.autoDownloadSubtitles) return;
    if (_isNetworkUri(uri)) return;
    final String path = SmartQueueService.toLocalPath(uri);
    if (!MediaUtils.isVideo(path)) return;
    // A sidecar subtitle already sitting there beats a download.
    if (SmartQueueService.findSidecar(path, MediaUtils.subtitleExtensions) != null) {
      return;
    }
    if (!SubtitlesApi.instance.hasApiKey) return;
    if (_autoSubPendingPath == path) return;
    _autoSubPendingPath = path;
    try {
      final SubtitleDownloadOutcome? outcome =
          await SubtitlesApi.instance.autoFetchBest(path);
      if (outcome == null) return;
      final String? file = outcome.path;
      if (!outcome.success || file == null) {
        debugPrint('[SALU] auto subtitles: ${outcome.message}');
        return;
      }
      // The user may have skipped ahead — never apply to the wrong video.
      final String? now = currentMediaUri;
      if (now == null || SmartQueueService.toLocalPath(now) != path) return;
      await loadExternalSubtitle(file);
      emitOsd('Subtitle Downloaded: '
          '${LanguageUtils.displayName(outcome.language ?? '')}');
    } catch (error) {
      debugPrint('[SALU] auto subtitle fetch failed: $error');
    } finally {
      if (_autoSubPendingPath == path) _autoSubPendingPath = null;
    }
  }

  static bool _isNetworkUri(String uri) {
    final String lower = uri.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('rtmp') ||
        lower.startsWith('rtsp') ||
        lower.startsWith('udp://');
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
  ///
  /// Phase 5 · Step 2: when [smartQueue] is on (and the user hasn't disabled
  /// it), the rest of the folder is silently queued behind the opened file in
  /// natural episode order.
  Future<void> openPath(String path, {bool play = true, bool smartQueue = true}) async {
    _flushHistory(force: true);
    path = MediaUtils.normalizePath(path);

    if (smartQueue &&
        AppPrefs.instance.autoQueueFolder &&
        !_isNetworkUri(path) &&
        MediaUtils.isMedia(path)) {
      final List<String> queue = SmartQueueService.queueForFile(path);
      if (queue.length > 1) {
        final int index = SmartQueueService.indexOf(queue, path);
        await player.open(
          Playlist(
            queue.map((String item) => Media(MediaUtils.normalizePath(item))).toList(),
            index: index,
          ),
          play: play,
        );
        return;
      }
    }

    await player.open(Media(path), play: play);
  }

  /// Open several files as a queue; playback starts with the first one.
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    _flushHistory(force: true);
    final Playlist p = Playlist(
        paths.map((String path) => Media(MediaUtils.normalizePath(path))).toList());
    await player.open(p, play: play);
  }

  /// Replaces the queue with [paths] and starts at [startIndex].
  Future<void> openQueue(List<String> paths,
      {int startIndex = 0, bool play = true}) async {
    if (paths.isEmpty) return;
    _flushHistory(force: true);
    final int index = startIndex.clamp(0, paths.length - 1).toInt();
    await player.open(
      Playlist(paths.map((String path) => Media(MediaUtils.normalizePath(path))).toList(),
          index: index),
      play: play,
    );
  }

  /// Attach an external subtitle file (.srt/.ass/…) to the current media.
  Future<void> loadExternalSubtitle(String path) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(MediaUtils.normalizePath(path)));
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

  /// Phase 5 · Step 5 — Exact vs. keyframe seeking.
  ///
  /// By default the arrow keys perform fast **keyframe** seeking; holding
  /// `Shift` switches to **exact** (millisecond-accurate) seeking. The
  /// Settings toggle `exactSeekByDefault` flips that relationship.
  ///
  /// [shiftHeld] reports whether the modifier was down for this keystroke.
  Future<void> seekByWithMode(Duration offset, {bool shiftHeld = false}) async {
    final bool exact = AppPrefs.instance.exactSeekByDefault ? !shiftHeld : shiftHeld;
    await setSeekPrecision(exact: exact);
    await seekBy(offset);
  }

  bool? _lastExactSeek;

  /// Switches mpv between `hr-seek=yes` (exact) and `hr-seek=no` (keyframe).
  Future<void> setSeekPrecision({required bool exact}) async {
    if (_lastExactSeek == exact) return;
    _lastExactSeek = exact;
    await _setMpvProperty('hr-seek', exact ? 'yes' : 'no');
  }

  Future<void> next() => player.next();

  Future<void> previous() => player.previous();

  Future<void> jump(int index) => player.jump(index);

  Future<void> addToPlaylist(String path) =>
      player.add(Media(MediaUtils.normalizePath(path)));

  Future<void> addAllToPlaylist(List<String> paths) async {
    for (final String path in paths) {
      await player.add(Media(MediaUtils.normalizePath(path)));
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

  /// Points mpv's built-in `ytdl_hook` at the yt-dlp binary SALU manages, so
  /// updating it from Settings → Updates actually affects stream parsing.
  Future<void> applyYtDlpPath() async {
    try {
      final String path = await UpdaterService.instance.ytDlpPath();
      if (!File(path).existsSync()) return;
      await _setMpvProperty('script-opts', 'ytdl_hook-ytdl_path=$path');
      debugPrint('[SALU] yt-dlp wired to mpv: $path');
    } catch (error) {
      debugPrint('[SALU] yt-dlp wiring failed: $error');
    }
  }

  // ── Phase 5 · Step 4: hardware decoding preference ───────────────────

  /// Pushes the stored `hwdec` preference into mpv and refreshes the HUD
  /// status. Called at startup and whenever the user changes the setting.
  Future<void> applyHwdecPreference() async {
    final HwdecMode mode = HwdecMode.fromPref(AppPrefs.instance.hwdec);
    await HwdecManager.apply(mode, _setMpvProperty);
    await _refreshHwdecStatus();
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
    _flushHistory(force: true);
    for (final StreamSubscription<dynamic> sub in _subs) {
      await sub.cancel();
    }
    await player.dispose();
  }
}
