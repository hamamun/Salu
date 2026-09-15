import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../ui/osd/osd_controller.dart';
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
///
/// **The graph is only ever in the pipeline when a load STARTED with
/// it.** `PlayerService` sets `lavfi-complex` before `player.open`, so
/// mpv folds the graph into the filter chain at first init. A running
/// pipeline is never handed the graph: mpv re-inits the chain on a
/// runtime change, and a failing re-init (or filter) STOPS the playback
/// — the engine treats a dead lavfi filter as end-of-file, which is how
/// the old toggle killed playback. The mid-playback switch therefore
/// re-opens the current item at its position instead, and a kill-watch
/// rolls any filter death back to exactly where the song was.
class AudioDisplayService {
  AudioDisplayService._internal();

  static final AudioDisplayService instance = AudioDisplayService._internal();

  /// Primary `lavfi-complex` graph (lrc.md L16): bar-type `showfreqs`,
  /// SALU accent on a dark canvas. No spectrum colour themes.
  static const String visualizerGraph =
      '[aid1]asplit[ao][a];[a]showfreqs=s=1280x720:mode=bar:ascale=log:fscale=log:win_func=gauss:averaging=5:colors=0x4C9EEB,format=yuv420p[vo]';

  static const int _cacheCap = 32;
  /// How long to wait for the engine to actually hold THIS file before
  /// its tags may be read (25 × 120 ms ≈ 3 s).
  static const int _fileTries = 25;
  static const Duration _metaGap = Duration(milliseconds: 120);
  /// Settle polls once the file gate has passed — the new demuxer's
  /// header (and with it the tags, or their absence) lands within this
  /// many ticks for a local file.
  static const int _metaTries = 8;
  /// A pre-load install failure stays disqualifying for this long — a
  /// re-open right after it would just re-open (the failure is a
  /// build-level one, not a per-try flake).
  static const Duration _installCooldown = Duration(seconds: 30);

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

  // ── Visualizer safety ────────────────────────────────────────────────

  /// Whether the pipeline currently holds the graph — the pre-load's
  /// decision, read on every landing and cleared by any runtime
  /// removal.
  bool _graphLive = false;

  /// The path whose install the pre-load failed for, and when — a
  /// re-open inside the cooldown would just loop.
  DateTime? _installFailedAt;

  StreamSubscription<bool>? _killWatch;
  String _killPath = '';

  /// `true` while a kill-recovery re-open is in flight — holds the
  /// end-of-item parker off so the restored song is not parked again.
  bool recovering = false;

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
      _graphLive = false;
      _resetSurface();
      unawaited(_applyEngine(AudioCanvasMode.none));
      return;
    }
    final String path = MediaUtils.canonicalPath(uri);
    _path = path;
    // The pre-load (in PlayerService, before the open) already decided
    // whether this load carries the graph — read the fact, then
    // re-evaluate the table. A load that DID take with the graph
    // clears any earlier install-failure marker.
    _graphLive = PlayerService.instance.visualizerArmed;
    if (_graphLive) _installFailedAt = null;
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
    _graphLive = false;
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
    _disarmKillWatch();
    final NativePlayer? native = _native;
    if (native == null) return;
    if (on) {
      if (_graphLive) {
        // This load came with the graph — it is in the pipeline from
        // init, nothing to install. All that is left is to watch for
        // a filter death.
        _armKillWatch();
        return;
      }
      // A running pipeline cannot be handed the graph (class doc): the
      // switch re-opens the current item at its position, and the load
      // comes back with the graph pre-applied.
      final PlayerService player = PlayerService.instance;
      final String? path = player.currentPath.value;
      if (path == null) return;
      final int index = QueueService.instance.indexOfUrl(path);
      if (index < 0) return;
      final DateTime now = DateTime.now();
      if (_installFailedAt != null &&
          now.difference(_installFailedAt!) < _installCooldown) {
        // The pre-load already failed for this file — a re-open would
        // just re-open it. The canvas keeps the metadata.
        mode.value = AudioCanvasMode.metadata;
        return;
      }
      _installFailedAt = now;
      await player.reopenItemAt(
        index,
        player.position.value,
        play: player.isPlaying.value,
      );
      return;
    }
    _graphLive = false;
    // A removal the pipeline tolerates — an empty graph has no filter
    // that can fail.
    try {
      await native.setProperty('lavfi-complex', '');
    } catch (error) {
      debugPrint('[SALU/audio] lavfi-complex clear failed: $error');
    }
  }

  // ── Kill watch — a dead lavfi filter is an "end of file" to mpv ─────

  /// Watches a graph-carrying load for the one failure the engine will
  /// not survive: a filter death, which mpv answers by stopping the
  /// playback as if the file had ended. Armed on every landing that
  /// carries the graph, for as long as the graph is in the pipeline —
  /// a filter can die on any frame, not only the first. A real
  /// end-of-song (position at the tail) passes it through untouched;
  /// Stop and file switches never set `eof-reached` at all, so they
  /// never trip it.
  void _armKillWatch() {
    final PlayerService player = PlayerService.instance;
    _killPath = player.currentPath.value ?? '';
    _killWatch = player.player.stream.completed.listen((bool done) {
      if (!done) return;
      final Duration dur = player.duration.value;
      final Duration at = player.position.value;
      // An "end" more than 2 s before the real end is the kill, not
      // the song finishing.
      if (dur <= Duration.zero || dur - at <= const Duration(seconds: 2)) {
        return;
      }
      unawaited(_recoverFromKill(at));
    });
  }

  void _disarmKillWatch() {
    _killWatch?.cancel();
    _killWatch = null;
  }

  /// The filter died mid-song: the graph off, the setting off (with
  /// the toast that re-tries it), and the song back where it was —
  /// the kill parked or advanced the engine like an end, so a plain
  /// re-open of the same row restores it.
  Future<void> _recoverFromKill(Duration at) async {
    _disarmKillWatch();
    final String path = _killPath;
    final PlayerService player = PlayerService.instance;
    final NativePlayer? native = _native;
    if (native != null) {
      try {
        await native.setProperty('lavfi-complex', '');
      } catch (_) {}
    }
    _graphLive = false;
    await SettingsService.instance.setVisualizer(false);
    final int index =
        path.isEmpty ? -1 : QueueService.instance.indexOfUrl(path);
    if (index >= 0) {
      recovering = true;
      try {
        await player.reopenItemAt(index, at);
      } finally {
        recovering = false;
      }
    }
    OsdController.instance.show(OsdUndoCard(
      label: 'Visualizer off — it stopped playback',
      onUndo: () => SettingsService.instance.setVisualizer(true),
    ));
  }

  NativePlayer? get _native {
    final PlatformPlayer? platform = PlayerService.instance.player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Mode C's text — the tags, but only THIS file's tags.
  ///
  /// mpv's `metadata` property reads the CURRENT demuxer's tags, and
  /// the old demuxer is torn down BEFORE `path` flips to the new file
  /// (mpv asserts `demuxer == NULL` when it sets the new filename).
  /// So `path` matching this file is the gate: until it matches,
  /// whatever is readable belongs to the previous song — the stale
  /// title on a no-tag file — and after it matches, the previous
  /// song's tags are unreachable, so an empty read can only mean "this
  /// file has no tags" or "its header is still being parsed". A file
  /// whose load never takes (failed open, or we already moved on)
  /// keeps the file name that landed with it.
  Future<void> _loadText(String path, int generation) async {
    bool current = false;
    for (int i = 0; i < _fileTries; i++) {
      if (generation != _generation) return;
      final NativePlayer? native = _native;
      if (native != null) {
        try {
          final String raw = await native.getProperty('path');
          if (raw.isNotEmpty && MediaUtils.canonicalPath(raw) == path) {
            current = true;
            break;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(_metaGap);
    }
    if (!current) return;
    // Settle: the new demuxer's tags (or their absence) land as soon
    // as its header is parsed. Poll like the old retry loop did — now
    // safe, because nothing stale can answer.
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
