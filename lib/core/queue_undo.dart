import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ui/osd/osd_controller.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// The one 5-second Undo slot for queue surgery (playlist_imp.md §5 —
/// follow.md rule 3: destructive actions execute instantly and offer an
/// Undo toast, never a confirmation dialog).
///
/// The service records the last undoable action, arms the deck's Undo
/// toast, and restores on [undo]:
///
///   · removal  — the item goes back to its original index; playback is
///     NOT yanked back if something else is playing (you are watching
///     that other item on purpose)
///   · reorder  — the move runs backwards
///   · clear    — the whole queue comes back in its original order AND,
///     if playback had been taken away (the deletion landed SALU in its
///     initial state), the item that was playing silently re-opens at its
///     remembered position. Always from an in-memory snapshot — an Undo
///     that re-fetches is not an Undo (§10.9 / M25).
///
/// What is never touched: the on-disk resume memory (a cleared playlist
/// is not a wiped history) and the saved URL seven.
class QueueUndoService {
  QueueUndoService._();

  static final QueueUndoService instance = QueueUndoService._();

  /// Whether an Undo is currently offered (the panel and the bridge
  /// mirror this; the deck card is the visible surface).
  final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  _UndoRecord? _record;
  Timer? _ttl;

  static const Duration _window = Duration(seconds: 5);

  // ── Recording (the panel calls these; they perform the action first) ──

  /// Delete row [i]: instant removal + 5 s Undo.
  Future<void> removeRow(int i) async {
    final RowRemoval? removal =
        await PlayerService.instance.removeFromQueue(i);
    if (removal == null) return;
    _arm(
      _RemoveRecord(removal),
      removal.item.title,
    );
  }

  /// Drag-reorder [from] → [to]: instant + 5 s Undo.
  Future<void> moveRow(int from, int to) async {
    final bool moved = await PlayerService.instance.moveInQueue(from, to);
    if (!moved) return;
    _arm(_MoveRecord(from, to), null);
  }

  /// Clear playlist: playback stops, the queue empties, SALU returns to
  /// its initial state — instantly, with a 5 s Undo.
  Future<void> clearAll() async {
    final QueueSnapshot? snapshot =
        await PlayerService.instance.clearPlaylist();
    if (snapshot == null) return;
    _arm(
      _ClearRecord(snapshot),
      '${snapshot.items.length}',
    );
  }

  // ── The 5 s window ───────────────────────────────────────────────────

  void _arm(_UndoRecord record, String? label) {
    _ttl?.cancel();
    _record = record;
    available.value = true;
    OsdController.instance.show(OsdUndoCard(label: label));
    _ttl = Timer(_window, _discard);
  }

  void _discard() {
    _ttl?.cancel();
    _ttl = null;
    _record = null;
    if (available.value) available.value = false;
  }

  /// Restores what the toast's action promised. Exactly what comes back
  /// is defined per record (see above).
  Future<void> undo() async {
    final _UndoRecord? record = _record;
    _ttl?.cancel();
    _record = null;
    if (available.value) available.value = false;
    OsdController.instance.dismiss();
    if (record == null) return;
    final PlayerService player = PlayerService.instance;
    switch (record) {
      case _RemoveRecord r:
        final RowRemoval removal = r.removal;
        await player.reinsertRemoved(removal.index, removal.item);
        // Only an initial-state landing re-opens playback (§5): the
        // deleted item had taken SALU to the logo canvas, so restoring
        // it re-opens it silently at its remembered position.
        if (removal.tookPlaybackToInitial) {
          await player.reopenRestored(removal.item, removal.position);
        }
      case _MoveRecord r:
        await player.moveInQueue(r.to, r.from);
      case _ClearRecord r:
        final QueueSnapshot snapshot = r.snapshot;
        QueueService.instance.setQueue(snapshot.items, snapshot.index);
        if (snapshot.restorePlayback && r.restoreItem != null) {
          await player.reopenRestored(r.restoreItem!, snapshot.position);
        }
    }
  }
}

/// What [PlayerService.removeFromQueue] did — the undo service stores it.
class RowRemoval {
  const RowRemoval({
    required this.item,
    required this.index,
    required this.tookPlaybackToInitial,
    required this.position,
  });

  final QueueItem item;
  final int index;

  /// True when the deleted item had been the only one: SALU returned to
  /// its initial state — Undo re-opens playback silently.
  final bool tookPlaybackToInitial;

  /// The playing item's position when it was removed.
  final Duration position;
}

/// What was parked before a clear (in-memory only — never a re-fetch).
class QueueSnapshot {
  const QueueSnapshot({
    required this.items,
    required this.index,
    required this.restorePlayback,
    required this.position,
  });

  final List<QueueItem> items;
  final int index;
  final bool restorePlayback;
  final Duration position;
}

// ── Records ─────────────────────────────────────────────────────────────

sealed class _UndoRecord {
  const _UndoRecord();
}

class _RemoveRecord extends _UndoRecord {
  const _RemoveRecord(this.removal);
  final RowRemoval removal;
}

class _MoveRecord extends _UndoRecord {
  const _MoveRecord(this.from, this.to);
  final int from;
  final int to;
}

class _ClearRecord extends _UndoRecord {
  const _ClearRecord(this.snapshot);
  final QueueSnapshot snapshot;

  /// The item that was playing when the queue was cleared, if any.
  QueueItem? get restoreItem {
    if (snapshot.index < 0 || snapshot.index >= snapshot.items.length) {
      return null;
    }
    return snapshot.items[snapshot.index];
  }
}
