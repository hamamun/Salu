import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/osd/osd_controller.dart';
import 'm3u_loader.dart';
import 'media_utils.dart';
import 'queue_service.dart';
import 'queue_undo.dart';
import 'resume_service.dart';

/// SALU's transport states. Three live states plus *idle* (nothing
/// loaded at all). **Stop is not pause and not start-over** — it parks
/// the queue: the engine releases the item, the queue stays loaded and
/// the exact position is remembered (see [PlayerService.stop]).
enum TransportState { idle, stopped, paused, playing }

/// Repeat modes (playlist_imp.md §5): off → all → one per click.
enum RepeatMode { off, all, one }

/// Why an item is being opened — the input to THE STEP RULE
/// ([PlayerService.playsOnStep]).
///
///   · [deliberate] — the user asked for this item: `|<<`, `>>|`, a row
///     click, an Open, Play-after-Stop.
///   · [automatic] — SALU moved on by itself: the end-of-item advance
///     and the dead-channel failure skip.
enum StepIntent { deliberate, automatic }

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
/// SALU owns the queue: [QueueService] holds the ordered items above the
/// engine (mpv's own playlist does not survive `stop()`). Two holdings
/// exist (playlist_imp.md §5 & §10.10a):
///
///   · FULL — local playback without shuffle/repeat-one: mpv gets the
///     whole queue, native auto-advance and gapless audio stay.
///   · SINGLE — shuffle on, repeat one, or a channel list: mpv holds ONE
///     media and SALU chooses the next index off `stream.completed`
///     (never `player.setShuffle`, and never 50 000 entries across the
///     Dart→mpv boundary on every zap).
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

  /// Title of the currently loaded media (file name without extension, or
  /// the channel's display name in channel mode — the playlist's own name
  /// always wins over mpv's stream metadata, M22).
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

  /// Repeat mode (playlist_imp.md §5) — survives Stop, runtime-only.
  final ValueNotifier<RepeatMode> repeatMode =
      ValueNotifier<RepeatMode>(RepeatMode.off);

  /// Shuffle on/off (§5) — playback order only; the visible list always
  /// shows the queue's natural order.
  final ValueNotifier<bool> shuffleOn = ValueNotifier<bool>(false);

  /// Whether the engine holds a live stream (an m3u channel — no duration,
  /// nothing to seek). Drives the inert timeline, the shimmer, the
  /// hairline handoff and the dimmed+silent seek marks (§10.8a–c).
  final ValueNotifier<bool> liveContent = ValueNotifier<bool>(false);

  /// The "live and receiving" flag (§10.8c): one source of truth for both
  /// live shimmers (timeline and hairline) so they can never disagree.
  /// False while paused, stalled or stopped — the drift stops.
  final ValueNotifier<bool> receiving = ValueNotifier<bool>(false);

  /// Whether a channel-list fetch/parse is in flight (m3u load) — the
  /// wordless loading state reuses the live shimmer (§10.10b / M42).
  final ValueNotifier<bool> playlistLoading = ValueNotifier<bool>(false);

  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _bufferingSub;

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

  /// The USER's pause intent, kept across item switches. `completed`
  /// arrives with `playing` already false (mpv flips both at eof), so the
  /// engine's state cannot answer "was the viewer paused?" — this latch
  /// can, and it is written only by the transport the user touches.
  /// The auto-advance obeys it: a paused player advances PAUSED, exactly
  /// as full holdings do, instead of being yanked into playback (§5).
  bool _userPaused = false;

  // ── Engine holdings & channel-mode bookkeeping ────────────────────────

  /// What mpv currently holds: one media (shuffle / repeat one / channel
  /// mode) or the whole queue (local default).
  bool _engineSingle = false;

  /// Random source for shuffle picks.
  final Random _rng = Random();

  /// True while mpv reports buffering — the receiving flag's stall input.
  bool _buffering = false;

  /// Whether the current open has produced a real playback signal yet
  /// (position, duration or frames) — the failure-skip gate (§10.8a-i):
  /// an error before any signal = a dead channel; after = a stall.
  bool _producedSignal = false;

  /// Consecutive channel failures (§10.8a-ii — the cascade guard).
  /// Three in a row is a dead provider, not a dead channel: SALU stops
  /// and waits. Reset on any success and on any manual pick.
  int _channelFailStrikes = 0;

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
      final QueueService queue = QueueService.instance;

      // SINGLE holdings (shuffle / repeat one / channel list): mpv's
      // index is meaningless (always 0) — the queue owns the truth and
      // the playlist's own display name wins over stream metadata (M22).
      if (_engineSingle) {
        final int qi = queue.index.value;
        if (qi >= 0 && qi < queue.items.value.length) {
          final QueueItem item = queue.items.value[qi];
          currentTitle.value = item.title;
          hasMedia.value = true;
          liveContent.value = queue.isChannelList;
          unawaited(_setWindowTitle('${item.title} — SALU'));
          currentPath.value = normalizePathKey(item.url);
          if (_lastAnnouncedIndex != qi) {
            _lastAnnouncedIndex = qi;
            unawaited(ResumeService.instance.flush());
          }
          final Duration? resumeAt =
              _pendingResume.remove(normalizePathKey(item.url));
          if (resumeAt != null) {
            OsdController.instance.show(OsdResumeCard(position: resumeAt));
          }
        }
        return;
      }

      final int index =
          playlist.index.clamp(0, playlist.medias.length - 1).toInt();
      final String uri = playlist.medias[index].uri;
      final String title = MediaUtils.displayName(uri);
      currentTitle.value = title;
      hasMedia.value = true;
      liveContent.value = false;
      unawaited(_setWindowTitle('$title — SALU'));

      // Path + queue mirror (only when mpv holds OUR queue).
      final String key = normalizePathKey(uri);
      currentPath.value = key;
      if (queue.items.value.length == playlist.medias.length) {
        final int queueIndex = index;
        queue.setIndex(queueIndex);
        queue.notePlayed(queueIndex);
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
      _refreshReceiving();
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
      if (p > Duration.zero) _markSignal();
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
      if (d > Duration.zero) _markSignal();
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
        _markSignal();
        unawaited(_refreshHwdecStatus());
      }
    });

    // Buffering — the shimmer's stall input (§10.8a): while a stream
    // stalls, "live and receiving" goes false and the drift stops.
    _bufferingSub = player.stream.buffering.listen((bool buffering) {
      _buffering = buffering;
      _refreshReceiving();
    });

    // Completed — intercepted ONLY while mpv holds a single media
    // (shuffle / repeat one): SALU chooses the next index (§5). In full
    // holdings mpv advances natively; channel mode never advances off
    // `completed` at all (M3e — skipping is failure-only).
    _completedSub = player.stream.completed.listen((bool completed) {
      if (!completed) return;
      _onCompleted();
    });

    _errorSub = player.stream.error.listen((String message) {
      debugPrint('[SALU/mpv] error: $message');
      _onEngineError();
    });

    // mpv's default already keeps the file open after the last frame so
    // the paused end-frame stays visible; make it explicit.
    unawaited(_ensureKeepOpen());
  }

  /// Real playback evidence (position / duration / frames): marks the
  /// current open as a living stream and resets the cascade counter.
  void _markSignal() {
    _producedSignal = true;
    if (_channelFailStrikes != 0) _channelFailStrikes = 0;
  }

  /// The shimmer's one source of truth (§10.8c): receiving = live and
  /// playing and not stalled.
  void _refreshReceiving() {
    receiving.value =
        liveContent.value && isPlaying.value && !_buffering;
  }

  /// The PACKAGING phase of a live channel (§10.8): the stream has been
  /// asked for but has produced nothing yet — position, duration, frames,
  /// all empty. Drives the brighter shimmer variant; a stall AFTER the
  /// first signal is just a stall — the drift stops there (M30).
  bool get livePackaging =>
      liveContent.value && isPlaying.value && !_producedSignal;

  // ── Path normalization ────────────────────────────────────────────────

  /// Canonical map key for resume/queue bookkeeping — the rules live in
  /// [MediaUtils.canonicalPath], which the queue and the memory manager
  /// share. Kept as a forwarding name so every call site here reads as
  /// "the queue's key", not "some path helper".
  ///
  /// It used to have its own copy of the rules — one that only folded
  /// DOUBLED backslashes, so a picked path (`C:\media\a.mp4`) came back
  /// unchanged and never matched the forward-slash spelling the engine
  /// reported. That is why local files opened from the picker or a drop
  /// remembered nothing.
  static String normalizePathKey(String p) => MediaUtils.canonicalPath(p);

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

  // ── Engine holdings & mode plumbing (§5) ──────────────────────────────

  /// Whether mpv should hold ONE media: channel lists always (M40), and
  /// shuffle / repeat-one locally (SALU then chooses the next index off
  /// `stream.completed`; `player.setShuffle` is never used — it would
  /// silently desync mpv's order from the queue's).
  bool get _useSingleMedia {
    final QueueService queue = QueueService.instance;
    return queue.isChannelList ||
        repeatMode.value == RepeatMode.one ||
        shuffleOn.value;
  }

  /// Reacts to repeat/shuffle toggles: keeps mpv's loop mode honest in
  /// full holdings, and switches holdings (full ⇄ single) on the fly —
  /// the switch re-opens the current item at its exact position so
  /// playback never visibly restarts.
  void _applyModeChange() {
    final QueueService queue = QueueService.instance;
    final bool wantSingle = _useSingleMedia;
    unawaited(player.setPlaylistMode(
      repeatMode.value == RepeatMode.all && !wantSingle
          ? PlaylistMode.loop
          : PlaylistMode.none,
    ));
    if (!hasMedia.value) return;
    if (wantSingle == _engineSingle) return;
    unawaited(_openQueueAt(
      queue.index.value,
      play: isPlaying.value,
      start: position.value,
    ));
  }

  /// Cycles repeat off → all → one (the header's slot 1).
  void cycleRepeatMode() {
    repeatMode.value = switch (repeatMode.value) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    _applyModeChange();
  }

  /// Toggles shuffle (the header's slot 2). Turning it on starts a fresh
  /// pass: everything unplayed except the item currently sounding.
  void toggleShuffle() {
    shuffleOn.value = !shuffleOn.value;
    final QueueService queue = QueueService.instance;
    if (shuffleOn.value) {
      queue.resetShufflePass(
          current: queue.hasCurrent ? queue.index.value : null);
    }
    _applyModeChange();
  }

  /// Next's enable state, folded over every mode (the decision table of
  /// playlist_imp.md §5; channel lists dim like local at the list's end).
  bool get nextAvailable {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return false;
    if (queue.isChannelList) return queue.hasNext;
    if (repeatMode.value == RepeatMode.one) return queue.hasNext;
    if (shuffleOn.value) {
      if (queue.unplayedInPass.isNotEmpty) return true;
      return repeatMode.value == RepeatMode.all &&
          queue.items.value.length > 1;
    }
    return queue.hasNext;
  }

  /// Previous's enable state: never dims while a local queue exists (it
  /// can always restart the item); channel lists dim with a single
  /// channel (M34).
  bool get prevAvailable {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return false;
    if (queue.isChannelList) return queue.items.value.length > 1;
    return true;
  }

  // ── Opening media ─────────────────────────────────────────────────────

  /// Open a single local file or network URL and start playing.
  ///
  /// Paths go in as the shell spelled them — [QueueService] owns the
  /// canonical form (§5), so no call site pre-normalizes anymore.
  Future<void> openPath(String path, {bool play = true}) async {
    // m3u is NEVER handed to mpv: SALU fetches & parses it itself and
    // the list becomes a channel queue (playlist_imp.md §10.1 / M2).
    if (M3uLoader.looksLikePlaylist(path)) {
      await M3uLoader.instance.open(path);
      return;
    }
    QueueService.instance.setPaths(<String>[path], 0);
    await _openQueueAt(0, play: play);
  }

  /// Open several files as a queue; playback starts with the first one.
  /// Any m3u among the picks loads as a channel list (M2) with the
  /// media files appended after it.
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    final List<String> playlists =
        paths.where(M3uLoader.looksLikePlaylist).toList();
    final List<String> media = paths
        .where((String p) => !M3uLoader.looksLikePlaylist(p))
        .toList();
    if (playlists.isNotEmpty) {
      await M3uLoader.instance.open(playlists.last);
      if (media.isNotEmpty) {
        await appendToQueue(
          <QueueItem>[
            for (final String p in media) QueueItem(p),
          ],
        );
      }
      return;
    }
    QueueService.instance.setPaths(paths, 0);
    await _openQueueAt(0, play: play);
  }

  /// Open a parsed channel list (m3u mode): the queue holds the items,
  /// the engine holds ONE media, and playback starts at [startIndex].
  Future<void> openChannelList(
    List<QueueItem> items, {
    int startIndex = 0,
    bool play = true,
  }) async {
    if (items.isEmpty) return;
    QueueService.instance.setQueue(items, startIndex);
    await _openQueueAt(startIndex, play: play);
  }

  /// The one open path: hands mpv the FULL queue in local mode (native
  /// auto-advance and gapless audio stay) or ONE media in single mode
  /// (shuffle / repeat one / channel list), points it at [index], and
  /// carries any remembered offset as `Media(start:)` — so resuming
  /// never flashes. (Channel lists: no resume — streams have none.)
  ///
  /// [start] overrides the disk memory for the target item (zero =
  /// deliberate restart); `null` = consult the disk memory, and when
  /// one exists the Resume toast fires on arrival.
  /// [silenceTargetResume] suppresses the target's Resume toast (the
  /// Undo restore re-opens silently — playlist_imp.md §5).
  ///
  /// [play] answers THE STEP RULE for this open — read it off
  /// [playsOnStep] with the step's intent, never as a bare literal. The
  /// default is the deliberate answer (`true`), because every remaining
  /// caller IS a deliberate open. Opening also writes the pause latch:
  /// an item that arrives playing leaves no pause behind for the next
  /// automatic advance to inherit.
  Future<void> _openQueueAt(
    int index, {
    bool play = true,
    Duration? start,
    bool silenceTargetResume = false,
  }) async {
    final QueueService queue = QueueService.instance;
    final List<QueueItem> items = queue.items.value;
    if (items.isEmpty) return;
    final int idx = index.clamp(0, items.length - 1).toInt();
    queue.setIndex(idx);
    queue.notePlayed(idx);

    // Decide the target's offset: explicit > disk memory.
    Duration? targetStart = start;
    bool targetFromDisk = false;
    if (targetStart == null) {
      final Duration? saved =
          ResumeService.instance.savedPositionFor(items[idx].url);
      if (saved != null) {
        targetStart = saved;
        targetFromDisk = true;
      }
    }

    stopMemory.value = null; // opening anything consumes a stop memory
    _openingWithPlay = play;
    _userPaused = !play; // the step rule's latch, written in one place
    hasMedia.value = true;
    _producedSignal = false;
    _refreshTransportState();

    if (_useSingleMedia) {
      _engineSingle = true;
      _lastAnnouncedIndex = idx;
      final String url = items[idx].url;
      final Duration? offset = targetStart;
      final Media media =
          (offset != null && offset > Duration.zero)
              ? Media(url, start: offset)
              : Media(url);
      if (offset != null &&
          offset > Duration.zero &&
          !silenceTargetResume) {
        final String key = normalizePathKey(url);
        _pendingResume[key] = offset;
        _expectedStartAfterLoad[key] = offset;
      }
      // A deliberate restart clears stale disk memory (same rule as the
      // full playlist below).
      if (targetFromDisk == false && start == Duration.zero) {
        ResumeService.instance.remove(url);
      }
      await player.open(media, play: play);
      return;
    }

    _engineSingle = false;

    // Build the full playlist; every item with a memory gets its start.
    final List<Media> medias = <Media>[];
    for (int i = 0; i < items.length; i++) {
      final String p = items[i].url;
      final bool isTarget = i == idx;
      final Duration? offset = isTarget
          ? targetStart
          : ResumeService.instance.savedPositionFor(p);
      if (offset != null && offset > Duration.zero) {
        medias.add(Media(p, start: offset));
        if (!(isTarget && silenceTargetResume)) {
          final String key = normalizePathKey(p);
          _pendingResume[key] = offset;
          // Fallback expectation for every item given a start (the
          // target now, auto-advanced items later).
          _expectedStartAfterLoad[key] = offset;
        }
      } else {
        medias.add(Media(p));
      }
    }
    // A deliberate restart clears the item's stale disk memory so it
    // cannot resurrect old state on a later open.
    if (targetFromDisk == false && start == Duration.zero) {
      ResumeService.instance.remove(items[idx].url);
    }

    await player.setPlaylistMode(
      repeatMode.value == RepeatMode.all
          ? PlaylistMode.loop
          : PlaylistMode.none,
    );
    await player.open(Playlist(medias, index: idx), play: play);
  }

  /// Builds a media for queue-append / undo-reinsert surgery in FULL
  /// holdings — the same per-item resume care [ _openQueueAt] applies.
  Media _mediaFor(QueueItem item) {
    final Duration? offset = ResumeService.instance.savedPositionFor(item.url);
    if (offset != null && offset > Duration.zero) {
      final String key = normalizePathKey(item.url);
      _pendingResume[key] = offset;
      _expectedStartAfterLoad[key] = offset;
      return Media(item.url, start: offset);
    }
    return Media(item.url);
  }

  // ── Queue-surgery public wrappers (playlist_imp.md §5) ────────────────

  /// Row clicks: play queue index [i] through the same open path as
  /// Previous/Next, so resume memory and the Resume toast behave exactly
  /// alike (`player.jump` is never used — it would skip the memory).
  Future<void> playIndex(int i) async {
    _channelFailStrikes = 0; // a deliberate pick, never part of a cascade
    stopMemory.value = null;
    // A clicked row plays, even from pause (the step rule).
    await _openQueueAt(i, play: playsOnStep(StepIntent.deliberate));
  }

  /// Removes the queue item at [i] and returns a [RowRemoval] describing
  /// what was done (the undo service records it), or `null` on a no-op.
  ///
  /// The owner's rule (playlist_imp.md §5): QueueService first, the
  /// engine second, the follow-up play third — the row that disappears
  /// and the row that lights up change in the same frame the audio
  /// changes. What plays after deleting the PLAYING item: the next one,
  /// else the previous, else the initial state (logo canvas).
  Future<RowRemoval?> removeFromQueue(int i) async {
    final QueueService queue = QueueService.instance;
    final List<QueueItem> items = queue.items.value;
    if (i < 0 || i >= items.length) return null;

    final QueueItem removed = items[i];
    final bool engineLive = hasMedia.value;
    final bool wasPlaying = engineLive && i == queue.index.value;
    final Duration remembered = wasPlaying ? position.value : Duration.zero;

    // 1 · QueueService.
    queue.removeAt(i);

    // 2 · The engine (full holdings only — a single-held media is
    // superseded by the follow-up open; a stopped engine rebuilds from
    // the queue on the next play).
    if (engineLive && !_engineSingle) {
      unawaited(player.remove(i));
    }

    // 3 · The follow-up play, when the PLAYING item was deleted.
    bool tookPlaybackToInitial = false;
    if (wasPlaying) {
      if (!queue.hasQueue) {
        // The only one: playback stops, the queue ends empty, SALU is
        // back at its initial state (logo canvas, TransportState.idle).
        tookPlaybackToInitial = true;
        await _returnToInitialState();
      } else {
        // Next (now at the same index) or, when none, the previous.
        await _openQueueAt(queue.index.value);
      }
    } else if (stopMemory.value != null &&
        stopMemory.value!.path == removed.url) {
      // The parked item was deleted — the stop memory must not point at
      // an item the queue no longer holds.
      stopMemory.value = null;
      _refreshTransportState();
    }

    return RowRemoval(
      item: removed,
      index: i,
      tookPlaybackToInitial: tookPlaybackToInitial,
      position: remembered,
    );
  }

  /// Re-inserts a previously removed item (Undo, QueueUndoService): the
  /// queue gets it back at its original index — playback is NOT yanked
  /// back while something else is playing (§5). The queue mutation is
  /// done here so queue and engine stay in lockstep.
  Future<void> reinsertRemoved(int index, QueueItem item) async {
    final QueueService queue = QueueService.instance;
    queue.insertAt(index, item);
    if (!hasMedia.value || _engineSingle) return;
    unawaited(player.add(_mediaFor(item)).then((_) async {
      final int last = queue.items.value.length - 1;
      if (index < last) await player.move(last, index);
    }));
  }

  /// Re-opens a restored item at its remembered position, silently — the
  /// Undo of an initial-state landing (no Resume toast, §5).
  Future<void> reopenRestored(QueueItem item, Duration start) async {
    final QueueService queue = QueueService.instance;
    int idx = queue.items.value
        .indexWhere((QueueItem e) => e.url == item.url);
    if (idx < 0) idx = queue.hasCurrent ? queue.index.value : 0;
    await _openQueueAt(idx, start: start, silenceTargetResume: true);
  }

  /// Drag-reorder: the queue and (in full holdings) mpv's playlist move
  /// together; playback never restarts. Returns false on a no-op.
  Future<bool> moveInQueue(int from, int to) async {
    final QueueService queue = QueueService.instance;
    final int count = queue.items.value.length;
    if (from < 0 || from >= count) return false;
    final int target = to.clamp(0, count - 1).toInt();
    if (from == target) return false;
    queue.move(from, target);
    if (hasMedia.value && !_engineSingle) {
      unawaited(player.move(from, target));
    }
    return true;
  }

  /// Appends entries (drop-on-panel, §7 step 10): the queue gets them
  /// and, in full holdings, mpv's playlist follows. The currently playing
  /// item is untouched.
  Future<void> appendToQueue(List<QueueItem> newItems) async {
    if (newItems.isEmpty) return;
    // An m3u is never a plain queue item (M-1): it loads as a whole
    // channel list, and any media items in the same gesture continue
    // after it. Extra playlists in one gesture are ignored — the last
    // thing opened is the truth.
    final List<QueueItem> playlists = newItems
        .where((QueueItem i) => M3uLoader.looksLikePlaylist(i.url))
        .toList();
    final List<QueueItem> media = newItems
        .where((QueueItem i) => !M3uLoader.looksLikePlaylist(i.url))
        .toList();
    if (playlists.isNotEmpty) {
      await M3uLoader.instance.open(playlists.first.url);
      if (media.isEmpty) return;
      newItems = media;
    }
    final bool hadQueue = QueueService.instance.hasQueue;
    final bool engineFull = hasMedia.value && !_engineSingle;
    QueueService.instance.append(newItems);
    if (engineFull) {
      for (final QueueItem item in newItems) {
        unawaited(player.add(_mediaFor(item)));
      }
      return;
    }
    // While stopped/idle the engine must stay untouched (M22) — unless
    // there was no queue at all: an open gesture against nothing starts
    // playing from the top (open is the append verb, §7.10/5.b).
    if (!hadQueue && !hasMedia.value) {
      await _openQueueAt(0);
    }
  }

  /// Clear playlist — ABSOLUTE (playlist_imp.md §5, the owner's rule):
  /// playback stops, the queue empties and SALU returns to its initial
  /// state (the logo canvas, TransportState.idle). Two things it must not
  /// touch: the on-disk resume memory and the saved URL seven.
  ///
  /// Returns the in-memory snapshot for the 5 s Undo (never a re-fetch),
  /// or `null` when there was nothing to clear.
  Future<QueueSnapshot?> clearPlaylist() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return null;
    final List<QueueItem> snapshot = List<QueueItem>.of(queue.items.value);
    final int snapshotIndex = queue.index.value;
    final bool restorePlayback = hasMedia.value;
    final Duration restorePosition = position.value;

    await _returnToInitialState();
    queue.clear();
    transportState.value = TransportState.idle;
    playlistLoading.value = false;

    return QueueSnapshot(
      items: snapshot,
      index: snapshotIndex,
      restorePlayback: restorePlayback,
      position: restorePosition,
    );
  }

  /// Playback stopped, queue emptied, logo canvas: what `stop()` + an
  /// empty queue produce, with the parked memory cleared too (the
  /// initial state, TransportState.idle).
  Future<void> _returnToInitialState() async {
    await stop();
    stopMemory.value = null;
    _refreshTransportState();
  }

  // ── Completion interception (§5 — shuffle & repeat one) ──────────────

  /// mpv finished its single held media; SALU answers "what plays now?"
  /// (exactly one control answers — the decision table of §5).
  void _onCompleted() {
    if (!_engineSingle) return; // full holdings: mpv advanced natively
    final QueueService queue = QueueService.instance;
    if (queue.isChannelList) return; // M3e: skipping is failure-only
    if (!queue.hasQueue) return;

    final int target = _completionTarget();
    if (target < 0) {
      // Stop → the queue parks (Stop ≠ Start Over). keep-open holds the
      // end frame; nothing else to do — a fresh Play replays the item.
      return;
    }
    // The advance inherits the viewer's state, it never overrides it:
    // paused at the end of an item → the next one loads PAUSED, exactly
    // like full holdings, where mpv pauses across the file change.
    unawaited(_openQueueAt(target, play: playsOnStep(StepIntent.automatic)));
  }

  /// The item ended: which index now? `-1` = park the queue.
  int _completionTarget() {
    final QueueService queue = QueueService.instance;
    final int current = queue.index.value;

    // Repeat one wins over shuffle — one control answers, and shuffle's
    // setting survives untouched.
    if (repeatMode.value == RepeatMode.one) return current;

    // Shuffle (and repeat one is off): the very same pick `>>|` makes, so
    // the automatic step and the manual one can never drift apart.
    if (shuffleOn.value) return shuffleNextTarget();
    return -1;
  }

  // ── The failure skip (§10.8 — a dead channel is skipped, not sat on) ─

  void _onEngineError() {
    final QueueService queue = QueueService.instance;
    if (!queue.isChannelList || !hasMedia.value) return;
    if (_producedSignal) return; // a stall mid-programme is not a dead channel
    if (queue.index.value < 0 ||
        queue.index.value >= queue.items.value.length) {
      return;
    }
    final QueueItem failed = queue.items.value[queue.index.value];
    _channelFailStrikes++;

    // 1 · The toast: "Failed to load" + the channel's name (M37), in the
    //    deck's existing card shape. Never the URL (§10.10e).
    OsdController.instance.show(
      OsdTransportCard(mark: OsdMark.next,
          text: 'Failed to load · ${failed.title}'),
    );

    // 2 · The cascade guard (§10.8a-ii): three consecutive failures is a
    //    dead provider — SALU stops, leaves the toast up and waits.
    if (_channelFailStrikes >= 3) return;

    // 3 · The next channel in LIST order. The tail failing does NOT
    //    wrap to index 0 — that would risk a silent loop.
    final int next = queue.index.value + 1;
    if (next >= queue.items.value.length) return;
    unawaited(_openQueueAt(next, play: playsOnStep(StepIntent.automatic)));
  }

  // ── THE STEP RULE (one owner for "does this step arrive playing?") ────

  /// Whether an item opened with this [intent] arrives PLAYING.
  ///
  /// **Deliberate steps always play — even from pause.** `|<<`, `>>|`, a
  /// row click and an Open are a statement of intent: you clicked, you
  /// want it playing. Opening also clears the pause latch (see
  /// [_openQueueAt]), so the automatic advance that may follow is not
  /// answering to a pause the viewer already stepped out of.
  ///
  /// **Automatic steps inherit the viewer's state.** The end-of-item
  /// advance (§5) and the dead-channel failure skip (§10.8a) never yank a
  /// paused player into playback: paused advances PAUSED, exactly as
  /// full holdings behave when mpv changes file by itself.
  ///
  /// This asymmetry is deliberate and lives HERE, in one function, so it
  /// is a rule and not an accident of a default argument. Every call site
  /// names its intent; nothing else decides.
  bool playsOnStep(StepIntent intent) =>
      intent == StepIntent.deliberate || !_userPaused;

  // ── Basic transport ───────────────────────────────────────────────────

  /// Play / Pause. The user's own toggle is the only thing that moves the
  /// pause latch the auto-advance obeys (see [_userPaused]).
  Future<void> playOrPause() {
    // Read the surface the user acted on, not the engine: while an open is
    // still confirming, `isPlaying` lags and the mark already reads "playing".
    _userPaused = transportState.value == TransportState.playing;
    return player.playOrPause();
  }

  Future<void> play() {
    _userPaused = false;
    return player.play();
  }

  Future<void> pause() {
    _userPaused = true;
    return player.pause();
  }

  /// **Stop — the third state.** Parks the queue: the engine releases
  /// the item (canvas → the initial SALU window), the queue stays
  /// loaded, the exact position is remembered in the session stop
  /// memory AND mirrored to disk, Prev/Next/Play/sound stay live, and
  /// Play-again resumes from the remembered position. Channel mode:
  /// identical — the list stays parked on the same channel (M33).
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
    liveContent.value = false;
    receiving.value = false;
    _channelFailStrikes = 0;
    playlistLoading.value = false;
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
    // Stop is not a pause: Play-again resumes, it does not sit paused on the
    // parked item. The latch starts clean for that decision.
    _userPaused = false;
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
    int idx = queue.paths.indexOf(mem.path);
    if (idx < 0) idx = queue.hasCurrent ? queue.index.value : 0;

    final bool keep =
        mem.duration > Duration.zero && _withinKeepWindow(mem.position, mem.duration);
    stopMemory.value = null; // consumed
    _channelFailStrikes = 0; // a deliberate pick
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

  /// Previous item — local: position (the stop memory while stopped)
  /// > 3 s, or first item → plays THIS item from `0:00`; otherwise the
  /// previous item (which follows the normal open path — if the disk
  /// remembers it, it resumes with the toast).
  ///
  /// Shuffle on: `|<<` returns to the item actually HEARD before (§5 —
  /// the play-order history), never the list's left neighbor.
  ///
  /// Channel mode (M36): no position to restart from — Previous always
  /// moves to the previous channel, in LIST order (M35).
  Future<void> previous() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return;
    final int idx = queue.index.value;
    _channelFailStrikes = 0; // a deliberate pick

    // Channel lists: plain step back, never a restart.
    if (queue.isChannelList) {
      if (idx <= 0) return;
      stopMemory.value = null;
      await _openQueueAt(idx - 1, play: playsOnStep(StepIntent.deliberate));
      return;
    }

    // Asked BEFORE the heard-log is consumed, and by the same getter the
    // deck reads for its card — one predicate, one answer.
    final bool restart = previousRestartsThisItem;

    // Shuffle (and not suspended by repeat one): what was heard before.
    // The predicate already answered `false` whenever such a step exists,
    // so the two branches can never contradict each other.
    if (!restart &&
        shuffleOn.value &&
        repeatMode.value != RepeatMode.one) {
      final int? heard = queue.previousHeard(idx);
      if (heard != null && heard != idx) {
        stopMemory.value = null;
        await _openQueueAt(heard, play: playsOnStep(StepIntent.deliberate));
        return;
      }
    }

    stopMemory.value = null;
    if (restart) {
      await _openQueueAt(
        idx <= 0 ? 0 : idx,
        play: playsOnStep(StepIntent.deliberate),
        start: Duration.zero,
      );
    } else {
      await _openQueueAt(idx - 1, play: playsOnStep(StepIntent.deliberate));
    }
  }

  /// **Whether `|<<` restarts THIS item** instead of stepping away — the
  /// Previous rule, owned here and read by everyone (the deck titles its
  /// card `00:00:00` off this getter instead of re-deriving the rule and
  /// drifting from it in the corners).
  ///
  /// Local: the position (the stop memory while stopped) is past 3 s, or
  /// the queue is on its first item. Never on a channel list (M36 — a
  /// live stream has no position to restart from). While shuffle is on
  /// and not suspended by repeat one, a real "heard before" step wins;
  /// with an EMPTY heard-log there is nothing to step back to, so the
  /// position rule answers — the narrow case the deck used to get wrong.
  ///
  /// Non-mutating: it peeks the heard-log ([QueueService.peekPreviousHeard]),
  /// so asking may be done as often as the UI likes.
  bool get previousRestartsThisItem {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return false;
    if (queue.isChannelList) return false;
    final int idx = queue.index.value;
    if (shuffleOn.value && repeatMode.value != RepeatMode.one) {
      final int? heard = queue.peekPreviousHeard(idx);
      if (heard != null && heard != idx) return false;
    }
    final StopMemory? mem = stopMemory.value;
    final Duration pos =
        (transportState.value == TransportState.stopped && mem != null)
            ? mem.position
            : position.value;
    return pos > const Duration(seconds: 3) || idx <= 0;
  }

  /// Next item — LIST order locally and on channel lists (M35: browsing
  /// must never change what Next does); a shuffled pick from the
  /// not-yet-played set while shuffle is on (never the same item twice
  /// in a row); list order while shuffle is suspended by repeat one.
  Future<void> next() async {
    final QueueService queue = QueueService.instance;
    if (!nextAvailable) return;
    _channelFailStrikes = 0; // a deliberate pick
    stopMemory.value = null;
    // A hand-pressed `>>|` plays, even from pause (the step rule).
    final bool play = playsOnStep(StepIntent.deliberate);

    if (queue.isChannelList) {
      await _openQueueAt(queue.index.value + 1, play: play);
      return;
    }

    if (shuffleOn.value && repeatMode.value != RepeatMode.one) {
      final int target = shuffleNextTarget();
      if (target < 0) return;
      await _openQueueAt(target, play: play);
      return;
    }

    await _openQueueAt(queue.index.value + 1, play: play);
  }

  /// The shuffled `>>|` target: an unplayed item of the current pass;
  /// at pass end with repeat all, a new pass (its first pick is never
  /// the item currently sounding); `-1` = there is no next.
  ///
  /// `stream.completed` asks THIS function too (via [_completionTarget]),
  /// so the manual step and the automatic one draw from the same pick —
  /// the two can never drift apart.
  int shuffleNextTarget() {
    final QueueService queue = QueueService.instance;
    final int count = queue.items.value.length;
    if (queue.unplayedInPass.isNotEmpty) {
      final List<int> pass = queue.unplayedInPass.toList();
      return pass[_rng.nextInt(pass.length)];
    }
    if (repeatMode.value == RepeatMode.all && count > 1) {
      final List<int> fresh = List<int>.generate(count, (int i) => i)
        ..remove(queue.index.value);
      queue.resetShufflePass();
      return fresh[_rng.nextInt(fresh.length)];
    }
    return -1;
  }

  /// Jump the timeline to an exact position.
  ///
  /// Clamps to the media bounds and reflects the target in the UI state
  /// immediately (the authoritative mpv position event follows within
  /// milliseconds). Seeking never pauses playback — and a live channel
  /// has nothing to seek into (§10.8a: the timeline is inert).
  Future<void> seekTo(Duration target) async {
    if (!hasMedia.value || liveContent.value) return;
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
    // Same canonical spelling as the queue (it used to fold only DOUBLED
    // backslashes, which a picked path never has).
    final String normalized = MediaUtils.canonicalPath(path);
    final String uri = normalized.contains('://')
        ? normalized
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
    await _completedSub?.cancel();
    await _bufferingSub?.cancel();
    await player.dispose();
  }
}
