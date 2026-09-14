import 'package:flutter/foundation.dart';

import 'lyric_locator.dart';
import 'lyric_parser.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

export 'lyric_parser.dart';

/// SALU's lyrics engine (lrc.md) — local sidecar `.lrc` only, audio
/// only, never the subtitle pipeline.
///
/// Discovery re-runs on every landing (L26). Showing lyrics is a
/// single global opt-in (L14), default OFF. The current line is looked
/// up against `position − subDelay` so the Z/X keys actually move the
/// Flutter overlay (L12 / L20).
class LyricService {
  LyricService._internal();

  static final LyricService instance = LyricService._internal();

  /// A matching `.lrc` with at least one timed line sits next to the
  /// current local audio file.
  final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// Global lyrics-on toggle (L14). Survives track changes; a file
  /// without a sidecar simply cannot show lyrics until one exists.
  final ValueNotifier<bool> shown = ValueNotifier<bool>(false);

  /// The parsed document of the current track, or `null`.
  final ValueNotifier<LyricDocument?> document =
      ValueNotifier<LyricDocument?>(null);

  /// Index into [document.lines] of the current line, or `-1`.
  final ValueNotifier<int> currentIndex = ValueNotifier<int>(-1);

  bool _watching = false;
  int _generation = 0;

  /// Lyrics are the thing on screen right now (available ∧ shown).
  bool get isShowing => available.value && shown.value;

  /// Clock + landing listeners. Safe to call more than once.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    final PlayerService player = PlayerService.instance;
    player.position.addListener(_onClock);
    player.subDelay.addListener(_onClock);
  }

  /// The §5 L26 trigger — same start-file moment [SubtitleService]
  /// answers. Fire-and-forget from [PlayerService].
  void onMediaLanded(String uri, {required bool channelMode}) {
    startWatching();
    final int generation = ++_generation;
    if (channelMode || uri.contains('://') || !MediaUtils.isAudio(uri)) {
      _clearDocument();
      return;
    }
    if (QueueService.instance.isChannelList) {
      _clearDocument();
      return;
    }
    final String path = MediaUtils.canonicalPath(uri);
    final LyricDocument? doc = LyricLocator.load(path);
    if (generation != _generation) return;
    document.value = doc;
    available.value = doc != null && doc.isNotEmpty;
    _refreshIndex();
  }

  /// Stop / idle — the previous track's lyric must not linger (L26).
  void onStopped() {
    _generation++;
    _clearDocument();
  }

  /// The Fetch button's audio job (L13): flip the global shown flag.
  /// No-op when nothing is available (the button is greyed then).
  void toggleShown() {
    if (!available.value) return;
    shown.value = !shown.value;
  }

  /// Seek target for a rendered line (L28). `null` when out of range.
  Duration? timestampOf(int index) {
    final LyricDocument? doc = document.value;
    if (doc == null || index < 0 || index >= doc.lines.length) return null;
    return doc.lines[index].timestamp;
  }

  void _clearDocument() {
    if (document.value != null) document.value = null;
    if (available.value) available.value = false;
    if (currentIndex.value != -1) currentIndex.value = -1;
  }

  void _onClock() {
    if (!available.value) return;
    _refreshIndex();
  }

  void _refreshIndex() {
    final LyricDocument? doc = document.value;
    if (doc == null || doc.isEmpty) {
      if (currentIndex.value != -1) currentIndex.value = -1;
      return;
    }
    final PlayerService player = PlayerService.instance;
    final int next = LrcParser.indexAt(
      doc.lines,
      player.position.value,
      subDelaySeconds: player.subDelay.value,
    );
    if (next != currentIndex.value) currentIndex.value = next;
  }
}
