import 'package:flutter/foundation.dart';

/// SALU's own play queue — the source of truth above the engine.
///
/// media_kit's `Player.stop()` clears mpv's internal playlist, so a queue
/// that survives Stop (Stop ≠ Start Over: the queue stays parked) has to
/// live here. `PlayerService` hands mpv the full playlist while an item is
/// loaded and mirrors mpv's index into this service; after a Stop it
/// re-opens the queue at the target index. The Phase 4 playlist panel and
/// Phase 5 smart queuing will read this same service.
class QueueService {
  QueueService._internal();

  /// The one and only queue for the whole app.
  static final QueueService instance = QueueService._internal();

  /// Ordered absolute paths (or URLs) of every queued item.
  final ValueNotifier<List<String>> paths = ValueNotifier<List<String>>(<String>[]);

  /// Index of the current item (`-1` while nothing is queued).
  final ValueNotifier<int> index = ValueNotifier<int>(-1);

  bool get hasQueue => paths.value.isNotEmpty;

  bool get hasCurrent {
    final int i = index.value;
    return i >= 0 && i < paths.value.length;
  }

  /// Whether an item exists after the current one (Next's enable state).
  bool get hasNext {
    final int i = index.value;
    return i >= 0 && i < paths.value.length - 1;
  }

  /// Replaces the whole queue and points [index] at the start item.
  void setQueue(List<String> list, int startIndex) {
    paths.value = List<String>.unmodifiable(list);
    index.value = list.isEmpty ? -1 : startIndex.clamp(0, list.length - 1);
  }

  /// Mirrors mpv's index while an item is loaded (auto-advance etc.).
  void setIndex(int i) {
    if (i >= 0 && i < paths.value.length && index.value != i) {
      index.value = i;
    }
  }

  /// Empties the queue (a fresh open replaces it; nothing calls this on
  /// Stop — Stop parks the queue, it never clears it).
  void clear() {
    paths.value = const <String>[];
    index.value = -1;
  }
}
