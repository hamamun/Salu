import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/osd/osd_controller.dart';
import 'channel_favourites_service.dart';
import 'channel_grouping.dart';
import 'channel_load_service.dart';
import 'channel_view_service.dart';
import 'media_utils.dart';
import 'queue_service.dart';
import 'resume_service.dart';
import 'subtitle_service.dart';

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

/// Repeat mode (playlist_imp.md §4.4 · §5) — the header's slot-1 control.
/// Maps onto mpv's playlist modes, except where SALU drives the advance
/// itself (shuffle). Never persisted across restarts (out of scope).
enum RepeatMode { off, all, one }

/// Base of every queue mutation that offers a 5-second Undo.
sealed class QueueUndo {
  const QueueUndo({required this.text});

  /// Toast copy (a toast may carry words — playlist_imp.md / follow.md).
  final String text;
}

/// A removed row. [wasLive] means the deletion landed SALU in its initial
/// state (the only item was removed), so Undo also re-opens the item.
/// [wasStopped] means the removal consumed a parked stop memory (the row
/// was removed from the STOPPED state), so Undo re-arms it.
class RemovedItemUndo extends QueueUndo {
  const RemovedItemUndo({
    required super.text,
    required this.item,
    required this.index,
    required this.wasLive,
    this.wasStopped = false,
    this.position,
    this.duration,
  });

  /// The removed entry (its URL is already canonical).
  final QueueItem item;
  String get path => item.url;
  final int index;
  final bool wasLive;
  final bool wasStopped;
  final Duration? position;
  final Duration? duration;
}

/// A cleared queue. [wasLive] means the clear stopped live playback, so
/// Undo also re-opens the item that was playing, at its position, silently.
/// [wasStopped] means the clear consumed a parked stop memory (Play was
/// showing its resume card), so Undo re-arms it — the pre-clear stopped
/// state comes back exactly.
class ClearedQueueUndo extends QueueUndo {
  const ClearedQueueUndo({
    required super.text,
    required this.items,
    required this.index,
    required this.wasLive,
    this.wasStopped = false,
    this.path,
    this.position,
    this.duration,
    this.playlistKey,
  });

  /// The cleared entries — an immutable in-memory snapshot (playlist_imp.md
  /// §10.9: Undo never re-fetches), released with the toast.
  final List<QueueItem> items;
  final int index;
  final bool wasLive;
  final bool wasStopped;
  final String? path;
  final Duration? position;
  final Duration? duration;

  /// Favourites key of the cleared channel list (`null` for a local
  /// queue) — Undo reselects it so the restored rows show their
  /// bookmarks (§10.9: the favourites store survives the bin).
  final String? playlistKey;
}

/// A drag-reorder. Undo re-applies the inverse move.
class MovedItemUndo extends QueueUndo {
  const MovedItemUndo({
    required super.text,
    required this.from,
    required this.to,
  });

  final int from;
  final int to;
}

/// One row of mpv's `track-list` (cc.md §6.2) — the track panel's
/// single source of truth. media_kit's parsed `tracks` skips the
/// `selected` / `external` / `external-filename` fields, so the panel's
/// surface is built from the RAW property read (mpv formats it as JSON —
/// verified against mpv's `print_node` → `json_write`).
class MpvTrack {
  const MpvTrack({
    required this.id,
    required this.type,
    this.title,
    this.lang,
    this.codec,
    this.channels,
    this.external = false,
    this.externalFilename,
    this.selected = false,
  });

  /// mpv's numeric track id as a string (`1`, `2`, …) — the value `sid` /
  /// `aid` takes. Pseudo rows (`auto` / `no`) never appear here.
  final String id;

  /// `audio` or `sub`.
  final String type;

  final String? title;

  /// mpv's language code (ISO 639-1/2) or `null` when untagged.
  final String? lang;

  /// `ac3`, `subrip`, … for the technical sub-line.
  final String? codec;

  /// Audio channel layout (`5.1`, `2.0`) from `demux-channels`.
  final String? channels;

  /// `true` for external subtitle files (autoloaded or loaded) — the
  /// embedded/local split (§6.3).
  final bool external;

  /// The external file's path (sub rows only, when mpv reports it).
  final String? externalFilename;

  /// mpv's own pick — the live row mark (D17: mpv picks, SALU mirrors).
  final bool selected;

  bool get isAudio => type == 'audio';

  bool get isSub => type == 'sub';
}

/// The whole track surface for the current media (§6.2): raw lists as
/// mpv reports them, refreshed on every track/selection event. All rows
/// of one [TrackSurface] belong to one snapshot — the panel never mixes
/// lists across rebuilds.
class TrackSurface {
  const TrackSurface({
    this.audio = const <MpvTrack>[],
    this.embeddedSubs = const <MpvTrack>[],
    this.localSubs = const <MpvTrack>[],
  });

  /// Part 1 — every audio track.
  final List<MpvTrack> audio;

  /// Part 2 — embedded subtitles only (§6.3's split).
  final List<MpvTrack> embeddedSubs;

  /// Part 3 — external (autoloaded + loaded) subtitle files.
  final List<MpvTrack> localSubs;

  static const TrackSurface empty = TrackSurface();

  /// `true` when the Off row's mark reads nobody-selected (a sub row's
  /// selection never shows "Off" while real subs are picked).
  bool get offIsMarked =>
      !embeddedSubs.any((MpvTrack t) => t.selected) &&
      !localSubs.any((MpvTrack t) => t.selected);

  /// Parses the `track-list` JSON string. Anything unreadable → empty
  /// (the panel simply shows its marks, never bogus rows).
  static TrackSurface parse(String raw) {
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final List<MpvTrack> audio = <MpvTrack>[];
      final List<MpvTrack> embedded = <MpvTrack>[];
      final List<MpvTrack> local = <MpvTrack>[];
      for (final dynamic e in list) {
        if (e is! Map) continue;
        final Map<dynamic, dynamic> m = e;
        final String type = '${m['type'] ?? ''}';
        if (type != 'audio' && type != 'sub') continue;
        final Object? id = m['id'];
        if (id == null) continue;
        final bool external = type == 'sub' && m['external'] == true;
        final MpvTrack track = MpvTrack(
          id: '$id',
          type: type,
          title: (m['title'] as String?)?.trim().isEmpty ?? true
              ? null
              : (m['title'] as String?),
          lang: (m['lang'] as String?)?.trim().isEmpty ?? true
              ? null
              : (m['lang'] as String?),
          codec: m['codec'] as String?,
          channels: m['demux-channels'] as String?,
          external: external,
          externalFilename: m['external-filename'] as String?,
          selected: m['selected'] == true,
        );
        if (type == 'audio') {
          audio.add(track);
        } else if (external) {
          local.add(track);
        } else {
          embedded.add(track);
        }
      }
      return TrackSurface(
        audio: audio,
        embeddedSubs: embedded,
        localSubs: local,
      );
    } catch (_) {
      return TrackSurface.empty;
    }
  }
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
/// gapless audio stay for list-order playback), and after a Stop the
/// queue is re-opened at the target index with the stop memory carried
/// as `Media(start:)`.
///
/// Repeat & shuffle (playlist_imp.md §5): repeat maps onto mpv's playlist
/// modes (`none` / `loop` / `single`). Shuffle NEVER uses mpv's own
/// `setShuffle` — mpv would reorder the playlist SALU handed it and the
/// two orders would silently diverge. While SALU drives the advance
/// (shuffle on, repeat ≠ one, more than one item) the engine is put on
/// `PlaylistMode.none` with mpv `keep-open=always`, so mpv never drifts
/// to the next list entry on its own and every end-of-media reaches the
/// `completed` stream for SALU to answer (playlist_imp.md §5's one
/// decision table). All other states keep `keep-open=yes`, which still
/// lets mpv advance natively through every entry but the last.
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

  /// Whether mpv is currently buffering (stalled — no data arriving).
  /// Drives the live light's quiet fade (§10.8a): the still soft light
  /// is present while data arrives and fades while this is true.
  final ValueNotifier<bool> isBuffering = ValueNotifier<bool>(false);

  /// Repeat mode — the header's slot-1 control (off → all → one).
  final ValueNotifier<RepeatMode> repeatMode =
      ValueNotifier<RepeatMode>(RepeatMode.off);

  /// Shuffle on/off — the header's slot-2 control. SALU drives the
  /// advance itself; mpv's playlist order is never touched.
  final ValueNotifier<bool> shuffleOn = ValueNotifier<bool>(false);

  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Tracks>? _tracksSub;

  /// The sub-download / sub-selection events cluster (start-file emits
  /// track-list + sid + aid practically together): one debounced raw
  /// read per burst keeps the mirror exact without churn.
  Timer? _surfaceDebounce;

  /// mpv-only observation of `sid` / `aid` (installed once, guarded —
  /// media_kit's own built-in state never double-observes into this
  /// map; a second registration would [ArgumentError]).
  bool _selectionObserversInstalled = false;

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

  /// Whether the viewer is PAUSED by a deliberate pause (not by EOF).
  /// A natural end must auto-advance with sound; a hand-pause that is
  /// followed by an end must advance into the next item still paused —
  /// the automatic answer never starts sound nobody asked for.
  bool _userPaused = false;

  // ── Channel failure · toast only (never a skip) ─────────────────────

  /// Queue index of the channel the last "Failed to load" toast reported
  /// (`-1` while none). One dead channel emits several mpv error lines —
  /// only the first reports; every fresh open resets it, so zapping back
  /// to a still-dead channel reports again.
  int _lastReportedFailure = -1;

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
      final String key = normalizePathKey(uri);
      final QueueService queue = QueueService.instance;

      // ── The index mirror (playlist_imp.md §10.12 M-3) ───────────────
      //
      // Local mode: mpv holds OUR whole queue, so its index IS ours —
      // the length check is what proves it (a mid-surgery playlist must
      // never move the pointer).
      //
      // Channel mode: mpv holds ONE media (§10.10a) and its index is
      // always 0, which says nothing. SALU is the only thing that knows
      // which channel that media is, so the queue keeps its own index
      // and the row is looked up by URL only as a safety net — never
      // taken from mpv. This is the `1 != 24` gate that used to leave
      // SALU blind to the playing channel.
      final bool channelMode = queue.isChannelList;
      if (!channelMode && queue.length == playlist.medias.length) {
        queue.setIndex(index);
      } else if (channelMode && playlist.medias.length == 1) {
        final QueueItem? at = queue.current;
        if (at == null || normalizePathKey(at.url) != key) {
          // Queue URLs are stored in the same canonical spelling, so the
          // key is what matches.
          final int row = queue.indexOfUrl(key);
          if (row >= 0) queue.setIndex(row);
        }
      }

      // The title is the CHANNEL's display name in channel mode — never
      // `1234` derived from a stream URL (§10.13 check 2) and never the
      // URL itself (§10.10e). `MediaUtils.displayName` is a FILE name
      // rule, so it is only ever applied to local playback; an unmatched
      // channel keeps the title it had rather than exposing a URL stem.
      final QueueItem? playing = channelMode ? queue.current : null;
      final String? title = channelMode
          ? (playing?.label ?? currentTitle.value)
          : MediaUtils.displayName(uri);
      currentTitle.value = title;
      hasMedia.value = true;
      unawaited(_setWindowTitle(title == null ? 'SALU' : '$title — SALU'));

      currentPath.value = key;

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

      // A different item is loading — stale tracks must never flash:
      // zero the surface, the tracks stream rebuilds it right away.
      trackSurface.value = TrackSurface.empty;

      // Subtitle engine (cc.md §3.1): every local video landing is
      // answered once. All guards live inside the service — this stays
      // one dumb line by design (D6/D17: nothing on the player side is
      // ever forced).
      SubtitleService.instance.onMediaLanded(uri, channelMode: channelMode);
    });

    // The track surface (cc.md §6.2): every structural track change
    // (new media · sub-add / sub-remove · external auto-load landing)
    // triggers a raw `track-list` re-read; selection flips (sid/aid)
    // arrive through the observed properties below. Both feed the same
    // debounced refresh.
    _tracksSub = player.stream.tracks.listen((_) => _queueSurfaceRefresh());
    unawaited(_installSelectionObservers());

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

    // Buffering — the live light fades while the stream stalls (§10.8a).
    _bufferingSub = player.stream.buffering.listen((bool buffering) {
      isBuffering.value = buffering;
    });

    _errorSub = player.stream.error.listen(_onEngineError);

    // End-of-item — the one place the "what plays next" question is
    // answered (playlist_imp.md §5's decision table). While SALU drives
    // the advance (shuffle) the engine never drifts on its own, so every
    // end reaches here. In list-order mode mpv's native playlist advance
    // owns the transition (gapless); this handler only parks the queue
    // when the LAST item ends with repeat off.
    _completedSub = player.stream.completed.listen((bool done) {
      if (done) _onMediaCompleted();
    });

    // keep-open=yes: pause on the last frame at the end of the playlist
    // (never quit), while entries before the last still auto-advance.
    unawaited(_setKeepOpen('yes'));
  }

  // ── Path normalization ────────────────────────────────────────────────

  /// Canonical map key for resume/queue bookkeeping: forward slashes,
  /// no `file://` scheme, no leading `/` before a drive letter.
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

  Future<void> _setKeepOpen(String value) async {
    final PlatformPlayer? platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('keep-open', value);
      } catch (_) {
        // Harmless if unavailable — mpv's default is `yes` anyway.
      }
    }
  }

  // ── Repeat & shuffle (playlist_imp.md §5) ─────────────────────────────

  /// Whether SALU must drive the advance itself: shuffle on, repeat is
  /// NOT "one" (which suspends shuffle), and there is more than one item
  /// (shuffle is meaningless on a single row). While true the engine is
  /// kept on `PlaylistMode.none` + `keep-open=always` so mpv never
  /// drifts to the next list entry on its own — SALU answers every
  /// `completed` event from the shuffle pass instead.
  ///
  /// Never in channel mode: repeat and shuffle are **dropped** there
  /// (M2 · §10.1), and the engine holds one media, so there is no list
  /// for either to act on. A shuffle left on by a previous local
  /// session must not silently drive channel zapping.
  bool get _shuffleDriving =>
      shuffleOn.value &&
      repeatMode.value != RepeatMode.one &&
      QueueService.instance.length > 1 &&
      !QueueService.instance.isChannelList;

  /// The engine mode matching the current repeat × shuffle state
  /// (playlist_imp.md §5 — one control answers "what plays next"):
  ///
  /// | repeat | shuffle | engine |
  /// |---|---|---|
  /// | one | any | `single` (mpv loops the current file — repeat-one
  ///   wins, shuffle is suspended) |
  /// | all | off | `loop` (mpv restarts the playlist at its end) |
  /// | off | off | `none` (mpv's native list-order advance) |
  /// | any | **on** (≠ one) | `none` + `keep-open=always` (SALU answers
  ///   every end from the shuffle pass) |
  ///
  /// `keep-open=yes` (every non-driving state) lets mpv advance through
  /// every entry but the last; the last entry pauses on its end frame.
  /// While SALU drives, `keep-open=always` stops ALL native advance so
  /// the shuffle pick — and only the pick — moves playback.
  Future<void> _applyPlaylistMode() async {
    if (!hasMedia.value) return;
    try {
      // Channel mode: repeat and shuffle are dropped (M2) and the engine
      // holds one media, so the only correct engine state is "play this
      // one thing". A repeat mode left over from a local session must
      // never make a channel loop instead of reporting its failure.
      if (QueueService.instance.isChannelList) {
        await _setKeepOpen('yes');
        await player.setPlaylistMode(PlaylistMode.none);
        return;
      }
      if (_shuffleDriving) {
        await _setKeepOpen('always');
        await player.setPlaylistMode(PlaylistMode.none);
        return;
      }
      await _setKeepOpen('yes');
      final PlaylistMode mode = switch (repeatMode.value) {
        RepeatMode.off => PlaylistMode.none,
        RepeatMode.all => PlaylistMode.loop,
        RepeatMode.one => PlaylistMode.single,
      };
      await player.setPlaylistMode(mode);
    } catch (_) {
      // Never fatal — the engine keeps its current mode.
    }
  }

  /// Cycles repeat off → all → one → off (the header control).
  Future<void> cycleRepeat() async {
    final RepeatMode next = switch (repeatMode.value) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    repeatMode.value = next;
    await _applyPlaylistMode();
  }

  /// Toggles shuffle. The state always survives (repeat-one only suspends
  /// the mark); the engine mode follows immediately.
  Future<void> toggleShuffle() async {
    shuffleOn.value = !shuffleOn.value;
    final QueueService queue = QueueService.instance;
    queue.resetShuffleState();
    if (shuffleOn.value && queue.hasCurrent) {
      queue.recordPlayed(queue.index.value);
    }
    await _applyPlaylistMode();
  }

  /// One media ended — "what plays next?" (playlist_imp.md §5).
  ///
  /// While [_shuffleDriving], SALU answers from the shuffle pass: an
  /// exhausted pass with repeat off parks the queue (Stop semantics),
  /// with repeat all it starts a fresh pass (whose first pick is never
  /// the item that just ended).
  ///
  /// Otherwise mpv's native advance owns list-order playback. The only
  /// case SALU still answers here is repeat **off** and the **last**
  /// item of the queue ending: mpv pauses on the end frame (keep-open)
  /// with nothing to advance to, so SALU parks the queue Stop-style, per
  /// the §5 table's off/off row. A short delay lets a real native
  /// advance (which follows `completed` within milliseconds mid-list)
  /// win first, so a slow playlist event can never double-park.
  void _onMediaCompleted() {
    final QueueService queue = QueueService.instance;
    // Channel mode: a live channel never "ends", and the engine holds
    // one media, so there is nothing here to advance to or to park.
    if (queue.isChannelList) return;
    if (_shuffleDriving) {
      int? next = queue.takeNextShuffle();
      if (next == null) {
        if (repeatMode.value == RepeatMode.all) {
          queue.startNewShufflePass();
          next = queue.takeNextShuffle();
        }
      }
      if (next == null) {
        // Pass exhausted + repeat off → park the queue, Stop style.
        unawaited(stop());
        return;
      }
      // The advance inherits the viewer's state: a hand-pause followed
      // by an end loads the next item paused — never sound nobody asked
      // for.
      final bool resumePaused = _userPaused;
      _userPaused = false;
      unawaited(_openQueueAt(next, play: !resumePaused));
      return;
    }

    if (repeatMode.value != RepeatMode.off || queue.hasNext) return;
    final TransportState state = transportState.value;
    if (state != TransportState.playing && state != TransportState.paused) {
      return;
    }
    Timer(const Duration(milliseconds: 300), () {
      if (!_shuffleDriving &&
          repeatMode.value == RepeatMode.off &&
          !queue.hasNext &&
          hasMedia.value &&
          (transportState.value == TransportState.playing ||
              transportState.value == TransportState.paused)) {
        unawaited(stop());
      }
    });
  }

  // ── Channel failure (toast only — never a skip) ─────────────────────

  /// Every mpv error line lands here.
  ///
  /// **Local mode is unchanged** — the line is printed and nothing else
  /// happens (Phase A behaviour is not touched).
  ///
  /// **Channel mode (§10.8):** the channel failed — toast
  /// **"Failed to load"** with the channel's name and stay on it. There
  /// is no auto-advance and no buffering-vs-failure guessing: a dead
  /// channel waits for the viewer (a retry is one click away), and a
  /// dead provider never stampedes the list.
  void _onEngineError(String message) {
    final QueueService queue = QueueService.instance;
    if (!queue.isChannelList) {
      debugPrint('[SALU/mpv] error: $message');
      return;
    }
    // The message is never logged in channel mode: mpv quotes the
    // failing URL and those carry credentials (§10.10e). What IS logged
    // is the decision (below), not the arrival of a line: one dead
    // channel emits several mpv error lines, and a bare line per error
    // reads like three dead channels when only one failed.
    reportChannelFailure();
  }

  /// Reports the current channel as failed — separated from the engine
  /// stream so it can be exercised without one. Toasts **"Failed to
  /// load"** with the channel's name and stays put: no skip, no cascade.
  /// A burst of mpv lines for one dead channel still reports once.
  void reportChannelFailure() {
    final QueueService queue = QueueService.instance;
    if (!queue.isChannelList || !queue.hasCurrent) return;
    // A late error from a channel the viewer already left behind (Stop
    // parks the list — §10.8b) must not pop a toast for a channel nobody
    // watches.
    if (!hasMedia.value) return;
    final int at = queue.index.value;
    if (at == _lastReportedFailure) {
      // A second error line for the channel that already failed — one
      // failure, one report.
      debugPrint('[SALU] channel error ignored (duplicate report)');
      return;
    }
    _lastReportedFailure = at;

    // The toast names the CHANNEL, never its URL (§10.10e).
    final QueueItem? failed = queue.itemAt(at);
    final String label = failed?.label ?? 'Channel';
    OsdController.instance.show(OsdFailedCard(name: label));
    debugPrint('[SALU] channel failed to load — staying put');
  }

  // ── Opening media ─────────────────────────────────────────────────────

  /// Open a single local file or network URL and start playing — a FRESH
  /// load (playlist_imp.md §1 decision 5): the shown playlist is one row,
  /// playback starts at it from the top. Stored memory is never burned
  /// (row clicks / Next still resume it later).
  Future<void> openPath(String path, {bool play = true}) async {
    final List<String> list = <String>[path];
    QueueService.instance.setQueue(list, 0);
    await _openQueueAt(0, play: play, fresh: true);
  }

  /// Open several files as a queue — a FRESH load: playback starts with
  /// the first row of the shown list, from the top, never from a
  /// remembered position or mid-list (playlist_imp.md §1 decision 5).
  Future<void> openPaths(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return;
    QueueService.instance.setQueue(paths, 0);
    await _openQueueAt(0, play: play, fresh: true);
  }

  /// Play a queue row (the playlist panel's click). Resume memory and
  /// the Resume toast behave exactly as they do for Next.
  Future<void> playIndex(int i, {bool play = true}) async {
    final QueueService queue = QueueService.instance;
    if (i < 0 || i >= queue.length) return;
    stopMemory.value = null;
    _userPaused = false;
    await _openQueueAt(i, play: play);
  }

  /// The one open path: hands mpv the FULL queue (native auto-advance
  /// and gapless audio stay), points it at [index], and carries any
  /// remembered offset as `Media(start:)` — so resuming never flashes.
  ///
  /// [start] overrides the disk memory for the target item (zero =
  /// deliberate restart); `null` = consult the disk memory, and when
  /// one exists the Resume toast fires on arrival.
  ///
  /// [fresh] = a freshly loaded queue: the target starts from `0:00`,
  /// its stored memory is left untouched, and no Resume toast fires.
  ///
  /// [silent] suppresses the Resume toast for the target even when a
  /// remembered offset IS applied (Undo restores — "silently").
  ///
  /// [keepMemory] stops a `start: Duration.zero` from erasing the item's
  /// stored memory (a fresh load is not a deliberate restart).
  Future<void> _openQueueAt(
    int index, {
    bool play = true,
    Duration? start,
    bool fresh = false,
    bool silent = false,
    bool keepMemory = false,
  }) async {
    final QueueService queue = QueueService.instance;
    _lastReportedFailure = -1; // a fresh open reports its own failure

    // ── Channel mode: ONE media, never the list (M40 · §10.10a) ───
    //
    // SALU owns the channel list; the engine is handed only the channel
    // being watched, so a zap costs one `open` whether the list holds 24
    // channels or 50 000 (mpv#6162: a `playlist-pos` change costs ~1 s
    // at 40 k entries, ~2 s at 80 k). Nothing is lost: a live stream has
    // no resume memory to carry (`resume_service.dart` skips anything
    // with `://`), and the advance that matters in this mode is the
    // failure skip, which SALU drives from `stream.error` (§10.8).
    // Local playback below keeps the full-queue path exactly as it is.
    if (queue.isChannelList) {
      final int count = queue.length;
      if (count == 0) return;
      final int at = index.clamp(0, count - 1).toInt();
      queue.setIndex(at);
      final QueueItem? channel = queue.itemAt(at);
      if (channel == null) return;
      stopMemory.value = null; // opening anything consumes a stop memory
      _openingWithPlay = play;
      hasMedia.value = true;
      _refreshTransportState();
      await player.open(Media(channel.url), play: play);
      if (play) _userPaused = false;
      // A live stream carries no remembered offset (`resume_service`
      // skips anything with `://`), so [start], [fresh], [silent] and
      // [keepMemory] have nothing to act on here — the resume machinery
      // is deliberately not run for a channel.
      await _applyPlaylistMode();
      return;
    }

    final List<String> paths = queue.paths;
    if (paths.isEmpty) return;
    final int idx = index.clamp(0, paths.length - 1).toInt();
    queue.setIndex(idx);

    // Keep the shuffle bookkeeping honest: whatever opened now was heard.
    if (_shuffleDriving) queue.recordPlayed(idx);

    // Decide the target's offset: explicit > fresh top > disk memory.
    Duration? targetStart = start;
    bool targetFromDisk = false;
    if (fresh) {
      targetStart = Duration.zero;
    } else if (targetStart == null) {
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
        if (!(isTarget && (fresh || silent))) {
          _pendingResume[key] = offset;
        }
        // Fallback expectation for every item given a start (the target
        // now, auto-advanced items later).
        _expectedStartAfterLoad[key] = offset;
      } else {
        medias.add(Media(p));
      }
    }
    // A deliberate restart clears the item's stale disk memory so it
    // cannot resurrect old state on a later open. Fresh loads and Undo
    // restores never erase memory.
    if (!fresh &&
        !keepMemory &&
        targetFromDisk == false &&
        start == Duration.zero) {
      ResumeService.instance.remove(paths[idx]);
    }

    stopMemory.value = null; // opening anything consumes a stop memory
    _openingWithPlay = play;
    hasMedia.value = true;
    _refreshTransportState();
    await player.open(Playlist(medias, index: idx), play: play);
    if (play) _userPaused = false;
    await _applyPlaylistMode();
  }

  // ── Basic transport ───────────────────────────────────────────────────

  Future<void> playOrPause() {
    // Decide from the pre-action state so _userPaused tracks the viewer's
    // intent (EOF pauses never count as a hand-pause).
    _userPaused = isPlaying.value;
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
    isBuffering.value = false;
    _stopTicker();
    _suppressVolumeEvents = true;
    _userPaused = false;
    await player.stop();

    // 3 · Zero the transport surface; title bar reads SALU again.
    currentTitle.value = null;
    currentPath.value = null;
    // The stopped player keeps the LAST media's track-list in mpv — the
    // panel must not show it: zero the surface with the rest.
    trackSurface.value = TrackSurface.empty;
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
    int idx = queue.indexOfUrl(mem.path);
    if (idx < 0) idx = queue.hasCurrent ? queue.index.value : 0;

    final bool keep =
        mem.duration > Duration.zero && _withinKeepWindow(mem.position, mem.duration);
    stopMemory.value = null; // consumed
    _userPaused = false;
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

  /// Whether a `>>|` can play something right now. In list order that is
  /// simply "an item exists after the current one"; while shuffle drives
  /// the advance there is always a pick (an exhausted pass starts a
  /// fresh one), so only the single-row queue dims Next.
  /// In channel mode this follows the open group (raw list order in Flat,
  /// while the accordion is collapsed, or while a search flattens the
  /// list) — and at the progressive-load frontier it is honestly `false`
  /// until more rows arrive (M56), which is exactly the end-of-list park
  /// the spec asks for.
  bool get hasNextItem {
    if (_shuffleDriving) return true;
    final QueueService queue = QueueService.instance;
    if (queue.isChannelList) {
      return _stepChannel(queue.index.value, 1) != null;
    }
    return queue.hasNext;
  }

  /// Whether a live channel is loaded right now (channel mode + the
  /// engine holds a channel). The timeline's empty inert state (§10.8a).
  bool get isLiveMode =>
      QueueService.instance.isChannelList && hasMedia.value;

  /// Whether live data is arriving — the one flag driving the still
  /// soft light on both the timeline and the hairline (§10.8a–c). False
  /// while buffering (the stall fade), while stopped/idle, and
  /// everywhere outside channel mode. Paused keeps the light: paused is
  /// not stalled.
  bool get isLiveReceiving {
    if (!isLiveMode) return false;
    if (isBuffering.value) return false;
    final TransportState state = transportState.value;
    return state == TransportState.playing ||
        state == TransportState.paused;
  }

  /// Whether `|<<` can do anything right now. Local mode: any queue —
  /// Previous can always restart the item. Channel mode (§10.8b): only
  /// when a previous channel exists, since there is no restart to fall
  /// back on (a one-channel list dims it, exactly as local dims Next).
  /// While a group is open the head that dims it is the group's head.
  bool get hasPreviousItem {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return false;
    if (!queue.isChannelList) return true;
    return _stepChannel(queue.index.value, -1) != null;
  }

  /// "Does `|<<` restart THIS item?" — one owner (playlist_imp.md §5),
  /// read both by [previous] and by the OSD card so the action and the
  /// card can never disagree. During shuffle with a non-empty heard-log
  /// the answer is no (it steps back to what was heard before); with an
  /// empty heard-log the ordinary rule answers: position (the stop
  /// memory while stopped) > 3 s, or first item → restarts this item.
  bool get previousRestartsThisItem {
    final QueueService queue = QueueService.instance;
    // Channel mode (§10.8b): Previous never "restarts" a live stream —
    // it always steps back a channel.
    if (queue.isChannelList) return false;
    if (_shuffleDriving && queue.peekPreviousHeard != null) return false;
    final int from = queue.index.value;
    final StopMemory? mem = stopMemory.value;
    final Duration pos = (transportState.value == TransportState.stopped &&
            mem != null)
        ? mem.position
        : position.value;
    return pos > const Duration(seconds: 3) || from <= 0;
  }

  // ── Group-aware channel stepping ────────────────────────────────────

  /// Cache for [_openGroupMembers]: the open group's member indexes only
  /// change when the list, the mode, the open group or the search state
  /// does — a dim-state read must never rescan 50 000 rows (§10.10c).
  List<QueueItem>? _stepItems;
  ChannelGroupMode? _stepMode;
  String? _stepGroup;
  bool _stepSearching = false;
  List<int> _stepMembers = const <int>[];

  /// Real queue indexes of the open group, in list order — empty in Flat
  /// mode, while the accordion is collapsed, while a search flattens the
  /// list, or for a stale key, in which case stepping falls back to raw
  /// list order.
  List<int> _openGroupMembers() {
    final ChannelViewService view = ChannelViewService.instance;
    final List<QueueItem> items = QueueService.instance.items.value;
    final ChannelGroupMode mode = view.groupMode.value;
    final String? open = view.openGroup.value;
    final bool searching = view.searching.value;
    if (!identical(items, _stepItems) ||
        mode != _stepMode ||
        open != _stepGroup ||
        searching != _stepSearching) {
      _stepItems = items;
      _stepMode = mode;
      _stepGroup = open;
      _stepSearching = searching;
      _stepMembers = (open == null || searching)
          ? const <int>[]
          : ChannelGrouping.membersOf(items, mode, open);
    }
    return _stepMembers;
  }

  /// The Prev/Next landing index in channel mode ([direction] +1 / −1),
  /// or `null` when the step parks (see [ChannelGrouping.stepTarget]).
  int? _stepChannel(int from, int direction) {
    return ChannelGrouping.stepTarget(
      members: _openGroupMembers(),
      from: from,
      direction: direction,
      count: QueueService.instance.length,
    );
  }

  /// Previous item — returns the index that ended up playing (`null`
  /// when nothing happened).
  ///
  /// During shuffle, `|<<` returns to the item actually heard before
  /// (the play-order history), never the raw previous list row; with an
  /// empty history the ordinary rule answers. Otherwise: position (the
  /// stop memory while stopped) > 3 s, or first item → plays THIS item
  /// from `0:00`; else plays the previous item (which follows the
  /// normal open path — if the disk remembers it, it resumes with the
  /// toast).
  Future<int?> previous() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return null;
    final int from = queue.index.value;
    // Channel mode (§10.8b): Previous ALWAYS steps back a channel — a
    // live stream has no position to restart from, so the 3-second rule
    // does not apply. While a group is open it steps within that group
    // (stepping into it when the playing channel sits outside); at an
    // edge it parks (never wraps), exactly as the frontier rule parks at
    // the tail (M56).
    if (queue.isChannelList) {
      final int? target = _stepChannel(from, -1);
      if (target == null) return null;
      stopMemory.value = null;
      _userPaused = false;
      await _openQueueAt(target);
      return target;
    }
    if (_shuffleDriving) {
      final int? back = queue.peekPreviousHeard;
      if (back != null && back >= 0) {
        stopMemory.value = null;
        _userPaused = false;
        await _openQueueAt(back);
        return back;
      }
    }
    final StopMemory? mem = stopMemory.value;
    final Duration pos = (transportState.value == TransportState.stopped &&
            mem != null)
        ? mem.position
        : position.value;
    if (pos > const Duration(seconds: 3) || from <= 0) {
      stopMemory.value = null;
      _userPaused = false;
      await _openQueueAt(from <= 0 ? 0 : from, start: Duration.zero);
      return from <= 0 ? 0 : from;
    }
    final int target = from - 1;
    stopMemory.value = null;
    _userPaused = false;
    await _openQueueAt(target);
    return target;
  }

  /// Next item — returns the index that ended up playing (`null` when
  /// nothing happened). During shuffle it plays the next pick of the
  /// pass (a fresh pass starts when the current one is exhausted — a
  /// deliberate step always plays); otherwise the next list row.
  Future<int?> next() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue) return null;
    // Channel mode (§10.8b): the open group's order (raw list order in
    // Flat, while the accordion is collapsed, or while a search flattens
    // the list), no shuffle, no wrap. Past the last PARSED channel it
    // behaves like end-of-list and parks — the progressive-load frontier
    // rule (M56).
    if (queue.isChannelList) {
      final int? target = _stepChannel(queue.index.value, 1);
      if (target == null) return null;
      stopMemory.value = null;
      _userPaused = false;
      await _openQueueAt(target);
      return target;
    }
    if (_shuffleDriving) {
      int? target = queue.takeNextShuffle();
      if (target == null) {
        queue.startNewShufflePass();
        target = queue.takeNextShuffle();
      }
      if (target == null) return null;
      stopMemory.value = null;
      _userPaused = false;
      await _openQueueAt(target);
      return target;
    }
    if (!queue.hasNext) return null;
    final int target = queue.index.value + 1;
    stopMemory.value = null;
    _userPaused = false;
    await _openQueueAt(target);
    return target;
  }

  /// Jump the timeline to an exact position.
  ///
  /// Clamps to the media bounds and reflects the target in the UI state
  /// immediately (the authoritative mpv position event follows within
  /// milliseconds). Seeking never pauses playback.
  Future<void> seekTo(Duration target) async {
    if (!hasMedia.value) return;
    // Channel mode: seek is dimmed and silent (§10.8a) — the timeline is
    // inert and the marks/keys never call here, but a stray call must
    // still be a silent no-op rather than a live-stream seek.
    if (QueueService.instance.isChannelList) return;
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

  // ── Track surface — the Fetch panel's live mirror (cc.md §6.2) ────────

  /// Everything the track panel shows, rebuilt from RAW `track-list`
  /// JSON on every mpv track/selection event. Empty while stopped.
  final ValueNotifier<TrackSurface> trackSurface =
      ValueNotifier<TrackSurface>(TrackSurface.empty);

  void _queueSurfaceRefresh() {
    _surfaceDebounce?.cancel();
    _surfaceDebounce =
        Timer(const Duration(milliseconds: 70), _refreshTrackSurface);
  }

  /// Observes `sid` / `aid` exactly once for the player's lifetime —
  /// selection flips re-read the surface so the panel's marks mirror
  /// ALL changes (the viewer's taps, mpv's own auto-picks — D17 says
  /// mpv picks, SALU only mirrors).
  Future<void> _installSelectionObservers() async {
    if (_selectionObserversInstalled) return;
    final PlatformPlayer? platform = player.platform;
    if (platform is! NativePlayer) return;
    _selectionObserversInstalled = true;
    // One burst-source per property is plenty; the debouncer coalesces.
    // media_kit's callback contract is `Future<void> Function(String)`
    // (its `observedProperties` map) — async block bodies satisfy it.
    try {
      await platform.observeProperty('sid', (_) async {
        _queueSurfaceRefresh();
      });
      await platform.observeProperty('aid', (_) async {
        _queueSurfaceRefresh();
      });
    } catch (error) {
      // Extremely defensive: a future media_kit registering the same
      // property first would throw ArgumentError — better no observer
      // than an engine-handled crash.
      debugPrint('[SALU] track observers unavailable: $error');
    }
  }

  Future<void> _refreshTrackSurface() async {
    // A stopped player keeps the LAST media's track-list — do NOT
    // re-read and re-show it; the surface is zeroed on stop already
    // (D6's inert-when-nothing-is-loaded world).
    if (!hasMedia.value) {
      if (trackSurface.value.audio.isNotEmpty ||
          trackSurface.value.embeddedSubs.isNotEmpty ||
          trackSurface.value.localSubs.isNotEmpty) {
        trackSurface.value = TrackSurface.empty;
      }
      return;
    }
    final PlatformPlayer? platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final String raw = await platform.getProperty('track-list');
      // The media may have changed while waiting for the property
      // (rapid zaps) — the tracks-subscription will re-refresh; only
      // ever write forward-looking data.
      trackSurface.value = TrackSurface.parse(raw);
    } catch (error) {
      debugPrint('[SALU] track-list read failed: $error');
    }
  }

  // ── Track selectors (cc.md §6.6: "select by id; no OSD on switch") ──

  /// Panel tap on an AUDIO row.
  Future<void> selectAudioTrack(MpvTrack track) async {
    await player.setAudioTrack(
      AudioTrack(track.id, track.title, track.lang),
    );
  }

  /// Panel tap on a SUB row (embedded or local) — the id drives it;
  /// mpv figures out the rest (never a SALU re-pick — D17).
  Future<void> selectSubTrack(MpvTrack track) async {
    await player.setSubtitleTrack(
      SubtitleTrack(track.id, track.title, track.lang),
    );
  }

  /// Panel tap on the pinned **Off** row (§6.6).
  Future<void> selectSubOff() async {
    await player.setSubtitleTrack(SubtitleTrack.no());
  }

  // ── Playlist surgery (playlist_imp.md §5) ─────────────────────────────

  /// Removes row [i] and applies the owner's follow-up rule:
  /// playing row + a next → play the next (via [playIndex], resume
  /// memory applies) · no next but a previous → play the previous ·
  /// the only item → initial state (stopped, empty queue, logo canvas).
  /// Rows before/after the playing one leave playback untouched.
  ///
  /// Returns the Undo token (or `null` when nothing was removed).
  Future<RemovedItemUndo?> removeFromQueue(int i) async {
    final QueueService queue = QueueService.instance;
    final List<QueueItem> items = queue.items.value;
    if (i < 0 || i >= items.length) return null;

    final QueueItem removed = items[i];
    final bool wasCurrent = queue.index.value == i;
    final bool onlyItem = items.length == 1;

    // The only item: remove → stop (parks the position for Undo) → the
    // initial state (queue empty, logo canvas).
    if (wasCurrent && onlyItem) {
      final bool live = hasMedia.value;
      // A removal from the STOPPED state consumes the parked memory; the
      // Undo token carries it so Undo restores the exact pre-removal state.
      final StopMemory? parked = live ? null : stopMemory.value;
      final RemovedItemUndo undo = RemovedItemUndo(
        text: removed.label,
        item: removed,
        index: i,
        wasLive: live,
        wasStopped: !live && parked != null,
        position: live ? position.value : parked?.position,
        duration: live ? duration.value : parked?.duration,
      );
      queue.removeAt(i);
      if (live) await stop();
      stopMemory.value = null;
      _refreshTransportState();
      return undo;
    }

    queue.removeAt(i);

    if (wasCurrent) {
      if (hasMedia.value) {
        // Follow-up: next → else previous. Both go through playIndex so
        // resume memory applies exactly as it does for Next.
        final int rest = queue.length;
        if (rest == 0) {
          stopMemory.value = null;
        } else if (i < rest) {
          await playIndex(i);
        } else {
          await playIndex(rest - 1);
        }
      } else if (queue.index.value < 0 && queue.hasQueue) {
        // Stopped/parked: the pointer parks on the row that slid in.
        queue.setIndex(queue.length - 1);
      }
    } else if (hasMedia.value && !queue.isChannelList) {
      // A row that is not playing: mirror the removal into the engine.
      // Channel mode has nothing to mirror — the engine holds only the
      // channel being watched (§10.10a).
      try {
        await player.remove(i);
      } catch (_) {
        // Best-effort mirror; the queue is already authoritative.
      }
    }

    return RemovedItemUndo(
      text: removed.label,
      item: removed,
      index: i,
      wasLive: false,
    );
  }

  /// Restores a removed row (5 s Undo). The list always comes back; when
  /// the removal had landed SALU in its initial state, the item that was
  /// playing also re-opens silently at its remembered position.
  Future<void> undoRemoveFromQueue(RemovedItemUndo undo) async {
    final QueueService queue = QueueService.instance;
    queue.insert(undo.index, undo.item);
    if (hasMedia.value && !queue.isChannelList) {
      // Engine mirror: append at the end, then move into place. Channel
      // mode holds one media, so there is nothing to mirror.
      try {
        await player.add(Media(undo.path));
        final int last = queue.length - 1;
        if (last != undo.index) {
          await player.move(last, undo.index);
        }
      } catch (_) {
        // Best-effort mirror; the next open rebuilds from the queue.
      }
      return;
    }
    if (undo.wasLive &&
        undo.position != null &&
        undo.duration != null) {
      final int idx = queue.indexOfUrl(undo.path);
      if (idx >= 0) {
        final bool keep =
            undo.duration! > Duration.zero &&
                _withinKeepWindow(undo.position!, undo.duration!);
        await _openQueueAt(
          idx,
          start: keep ? undo.position : Duration.zero,
          silent: true,
          keepMemory: true,
        );
      }
    } else if (undo.wasStopped &&
        undo.position != null &&
        undo.duration != null) {
      // The removal had consumed a parked stop memory — re-arm it so Play
      // resumes the item exactly as before the removal.
      stopMemory.value = StopMemory(
        path: undo.path,
        position: undo.position!,
        duration: undo.duration!,
      );
      _refreshTransportState();
    }
  }

  /// Clears the queue — ABSOLUTE (owner): playback stops, the queue
  /// empties, SALU returns to its initial state. On-disk resume memory
  /// and the saved URL seven are untouched. Returns the Undo token
  /// (`null` when there was nothing to clear).
  Future<ClearedQueueUndo?> clearQueue() async {
    final QueueService queue = QueueService.instance;
    if (!queue.hasQueue && !hasMedia.value) return null;
    // The bin unloads the channels (§10.9): a progressive load still
    // arriving must not append into the emptied list — cancelling kills
    // the worker isolate with its buffers. Saved URLs and favourites are
    // untouched, and Undo restores from the in-memory snapshot below,
    // never a re-fetch.
    ChannelLoadService.instance.cancel();

    // The published list is already unmodifiable — the snapshot IS the
    // list, no copy (a 50 000-row clear must not duplicate the queue).
    final List<QueueItem> snapshot = queue.items.value;
    final int at = queue.index.value;
    final bool live = hasMedia.value;
    final String? playing = live ? currentPath.value : null;
    final Duration pos = live ? position.value : Duration.zero;
    final Duration dur = live ? duration.value : Duration.zero;
    // A clear from the STOPPED state consumes the parked stop memory; the
    // Undo token carries it so Undo restores the exact pre-clear state.
    final StopMemory? parked = stopMemory.value;
    final bool wasStopped = !live && parked != null;

    if (hasMedia.value) await stop();
    queue.clear();
    stopMemory.value = null;
    _refreshTransportState(); // nothing left → idle (the initial state)

    return ClearedQueueUndo(
      text: 'Playlist cleared',
      items: snapshot,
      index: at,
      wasLive: live && playing != null,
      wasStopped: wasStopped,
      path: live ? playing : parked?.path,
      position: live ? pos : parked?.position,
      duration: live ? dur : parked?.duration,
      playlistKey: (snapshot.isNotEmpty && snapshot.first.isChannel)
          ? ChannelLoadService.instance.playlistKey.value
          : null,
    );
  }

  /// Restores a cleared queue (5 s Undo): the whole queue comes back in
  /// its original order; if the clear had stopped live playback, the
  /// item that was playing re-opens silently at its remembered position.
  Future<void> undoClearQueue(ClearedQueueUndo undo) async {
    final QueueService queue = QueueService.instance;
    if (undo.items.isEmpty) return;
    queue.setItems(undo.items, undo.index >= 0 ? undo.index : 0);
    // §10.9: the bin unloads the channels but never their favourites —
    // reselect the restored list's key so the rows show their bookmarks.
    if (undo.playlistKey != null) {
      ChannelLoadService.instance.playlistKey.value = undo.playlistKey;
      ChannelFavouritesService.instance.setPlaylist(undo.playlistKey);
    }
    if (undo.wasLive &&
        undo.path != null &&
        undo.position != null &&
        undo.duration != null) {
      final int idx = queue.indexOfUrl(undo.path!);
      if (idx >= 0) {
        final bool keep =
            undo.duration! > Duration.zero &&
                _withinKeepWindow(undo.position!, undo.duration!);
        await _openQueueAt(
          idx,
          start: keep ? undo.position : Duration.zero,
          silent: true,
          keepMemory: true,
        );
      }
    } else if (undo.wasStopped &&
        undo.path != null &&
        undo.position != null &&
        undo.duration != null) {
      // The clear had consumed a parked stop memory — re-arm it so Play
      // resumes the item exactly as before the clear.
      stopMemory.value =
          StopMemory(path: undo.path!, position: undo.position!, duration: undo.duration!);
      _refreshTransportState();
    }
  }

  /// Reorders row [from] to [to] (final-position semantics) in the queue
  /// AND the engine; playback does not restart (a drag is a deliberate
  /// change — only fresh loads start at the top). Returns the Undo token,
  /// or `null` when nothing moved (no-op / out of range).
  Future<MovedItemUndo?> moveInQueue(int from, int to) async {
    if (from == to) return null;
    final QueueService queue = QueueService.instance;
    // Rows have no drag in channel mode (M-4 · §10.4) and the engine
    // holds one media — nothing to reorder on either side.
    if (queue.isChannelList) return null;
    final QueueItem? moved = queue.itemAt(from);
    if (moved == null) return null;
    // queue.move itself resets the shuffle bookkeeping — an index-based
    // heard-log/pass is meaningless once rows have moved under it.
    if (!queue.move(from, to)) return null;
    if (hasMedia.value) {
      try {
        await player.move(from, to);
      } catch (_) {
        // Best-effort mirror; the next open rebuilds from the queue.
      }
    }
    return MovedItemUndo(
      text: moved.label,
      from: from,
      to: to,
    );
  }

  /// Restores a drag-reorder (5 s Undo): the inverse move, playback
  /// untouched, no second toast.
  Future<void> undoMoveInQueue(MovedItemUndo undo) async {
    await moveInQueue(undo.to, undo.from);
  }

  /// Appends a batch of (already boundary-sorted) items. The current
  /// item is untouched; while the engine holds the playlist the items
  /// are mirrored into mpv as they are queued.
  Future<void> appendToQueue(List<String> paths) async {
    if (paths.isEmpty) return;
    // A channel list is not a local queue: local files never join it
    // (§10.4 — the channel panel has no append gesture), and the engine
    // holds one media there, so there is no playlist to mirror into.
    if (QueueService.instance.isChannelList) return;
    final List<String> canonical =
        paths.map(MediaUtils.canonicalPath).toList(growable: false);
    QueueService.instance.append(canonical);
    if (hasMedia.value) {
      for (final String p in canonical) {
        try {
          await player.add(Media(p));
        } catch (_) {
          // Best-effort mirror.
        }
      }
    }
  }

  /// Grows a SINGLE-row queue in place — folder auto-load
  /// (autoload_imp.md §2 step 5): [before] and [after] slot in around
  /// the item playing right now, in the folder's natural order, so the
  /// picked file's row becomes its natural folder position
  /// (`before.length`). The current media is NEVER reopened — no
  /// flicker, no position jump, resume memory untouched. Neighbours are
  /// plain `Media`s (no `start:` offsets), exactly like
  /// [appendToQueue]: a remembered position applies when a row is
  /// explicitly opened later — the established append precedent.
  ///
  /// Callers guarantee the queue is the untouched singleton a fresh
  /// single-file load just installed; anything else is a no-op. Returns
  /// `true` when the queue grew.
  Future<bool> insertAroundCurrent({
    required List<String> before,
    required List<String> after,
  }) async {
    if (before.isEmpty && after.isEmpty) return false;
    final QueueService queue = QueueService.instance;
    final List<String> paths = queue.paths;
    // The caller's contract: exactly the freshly loaded item, playing.
    if (paths.length != 1 || queue.index.value != 0 || !hasMedia.value) {
      return false;
    }

    final List<String> beforeC =
        before.map(MediaUtils.canonicalPath).toList(growable: false);
    final List<String> afterC =
        after.map(MediaUtils.canonicalPath).toList(growable: false);

    // Engine mirror. The queue is still the singleton while the engine
    // playlist grows, so the playlist stream's length guard
    // (`queue.length == playlist.medias.length`) blocks any
    // mid-surgery setIndex from clobbering the row the queue lands on
    // below; mpv keeps the CURRENT entry through every add/move, so
    // title and path never leave the picked file either.
    int engineLength = 1;
    for (final String p in afterC) {
      try {
        await player.add(Media(p));
        engineLength++;
      } catch (_) {
        // Best-effort mirror; the queue is already authoritative.
      }
    }
    for (int j = 0; j < beforeC.length; j++) {
      try {
        await player.add(Media(beforeC[j]));
        engineLength++;
        await player.move(engineLength - 1, j);
      } catch (_) {
        // Best-effort mirror; the queue is already authoritative.
      }
    }

    // The queue lands in its final shape only after the engine is done:
    // one items.value fire, the panel fills in a single pass, and the
    // picked file sits at its natural row.
    queue.setQueue(
      <String>[...beforeC, paths.first, ...afterC],
      beforeC.length,
    );

    // The repeat × shuffle engine state was answered for a one-row
    // queue — it just stopped being one, so re-answer "what plays next"
    // (a live shuffle now takes over the advance).
    await _applyPlaylistMode();

    debugPrint(
        '[SALU] auto-load inserted ${beforeC.length + afterC.length} item(s) around the current one');
    return true;
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
    await _completedSub?.cancel();
    await _widthSub?.cancel();
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _volumeSub?.cancel();
    await _bufferingSub?.cancel();
    await _tracksSub?.cancel();
    _surfaceDebounce?.cancel();
    await player.dispose();
  }
}
