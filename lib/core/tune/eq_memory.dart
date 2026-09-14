import 'dart:convert';

/// The Auto EQ learning map (eq_imp.md §5) — bounded, on-device, no network.
///
/// Shape, one JSON blob inside the settings store:
/// `{"audio|jazz": ["pop", 1720000000000], "video|the office": ["movie", …]}`
/// — key = file type + genre/series, value = the KEPT choice + last-used
/// time (≈ 100 bytes an entry).
///
/// The bounds are the spec's own data policy:
///  * **LRU cap 500** — every pick/teach touches its entry, so recency is
///    free to track; beyond the cap the least-recently-used entry dies.
///  * **90-day staleness** — entries unused for 90+ days are pruned at app
///    start (taste moves on; stale taste is worthless data).
///  * **Manual clear** — the whole map wipes in one tap, with SALU's Undo
///    toast (no confirm dialog; the caller keeps the snapshot).
///
/// Pure Dart: the map never touches `shared_preferences`, so the cap, the
/// pruning and the round-trip are unit-testable, and `TuneService` owns the
/// disk write exactly like `SubDelayService` does.
class EqMemory {
  EqMemory._(this._entries);

  EqMemory.empty() : _entries = <String, EqMemoryEntry>{};

  /// Beyond this many entries the least-recently-used one is evicted.
  static const int maxEntries = 500;

  /// Entries untouched for longer than this are dropped at app start.
  static const Duration staleness = Duration(days: 90);

  final Map<String, EqMemoryEntry> _entries;

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  Iterable<String> get keys => _entries.keys;

  /// The kept choice for a key, `null` when nothing was ever kept.
  String? presetFor(String key) => _entries[key]?.presetKey;

  EqMemoryEntry? entryFor(String key) => _entries[key];

  /// Records a KEPT choice (a hover never teaches — §5's rule). The entry is
  /// created or refreshed, and the LRU cap is applied immediately so
  /// [length] never overshoots.
  void teach(String key, String presetKey, {DateTime? now}) {
    if (key.isEmpty || presetKey.isEmpty) return;
    _entries[key] = EqMemoryEntry(
      presetKey: presetKey,
      usedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
    _evictToCap();
  }

  /// Every pick/teach already touches its entry; this is the read path's
  /// touch, kept so a heavily used key is never the one the cap evicts.
  void touch(String key, {DateTime? now}) {
    final EqMemoryEntry? e = _entries[key];
    if (e == null) return;
    _entries[key] = EqMemoryEntry(
      presetKey: e.presetKey,
      usedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  void remove(String key) => _entries.remove(key);

  void clear() => _entries.clear();

  /// Drops everything unused for [staleness] or longer. Returns how many
  /// entries went away.
  int pruneStale({DateTime? now}) {
    final int cutoff =
        (now ?? DateTime.now()).subtract(staleness).millisecondsSinceEpoch;
    final List<String> dead = <String>[];
    _entries.forEach((String key, EqMemoryEntry e) {
      if (e.usedAtMs <= cutoff) dead.add(key);
    });
    for (final String key in dead) {
      _entries.remove(key);
    }
    return dead.length;
  }

  /// A reversible snapshot for the Undo toast.
  Map<String, EqMemoryEntry> snapshot() =>
      Map<String, EqMemoryEntry>.of(_entries);

  /// Restores a [snapshot] (the "Clear EQ memory" undo).
  void restore(Map<String, EqMemoryEntry> previous) {
    _entries
      ..clear()
      ..addAll(previous);
    _evictToCap();
  }

  void _evictToCap() {
    if (_entries.length <= maxEntries) return;
    final List<MapEntry<String, EqMemoryEntry>> sorted =
        _entries.entries.toList(growable: false)
          ..sort((MapEntry<String, EqMemoryEntry> a,
                  MapEntry<String, EqMemoryEntry> b) =>
              a.value.usedAtMs.compareTo(b.value.usedAtMs));
    final int excess = _entries.length - maxEntries;
    for (int i = 0; i < excess; i++) {
      _entries.remove(sorted[i].key);
    }
  }

  // ── Wire format ────────────────────────────────────────────────────────

  /// `key → [preset, usedAtMs]` — the same compact shape the resume and
  /// subtitle-sync stores use.
  String encode() {
    final Map<String, List<Object>> out = <String, List<Object>>{};
    _entries.forEach((String key, EqMemoryEntry e) {
      out[key] = <Object>[e.presetKey, e.usedAtMs];
    });
    return jsonEncode(out);
  }

  /// Anything unreadable → an empty map, silently (the house rule for
  /// hand-edited or corrupt prefs).
  static EqMemory decode(Object? raw) {
    final EqMemory memory = EqMemory.empty();
    if (raw is! String || raw.isEmpty) return memory;
    // Tolerate both the JSON string and an already-decoded map (tests).
    Object? decoded = raw;
    if (raw.trimLeft().startsWith('{')) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return memory;
      }
    }
    if (decoded is! Map) return memory;
    decoded.forEach((Object? key, Object? value) {
      if (key is! String || key.isEmpty) return;
      if (value is List && value.isNotEmpty && value.first is String) {
        memory._entries[key] = EqMemoryEntry(
          presetKey: value.first as String,
          usedAtMs: value.length >= 2 && value[1] is num
              ? (value[1] as num).toInt()
              : 0,
        );
      } else if (value is Map && value['preset'] is String) {
        final Object? ts = value['used'];
        memory._entries[key] = EqMemoryEntry(
          presetKey: value['preset'] as String,
          usedAtMs: ts is num ? ts.toInt() : 0,
        );
      }
    });
    memory._evictToCap();
    return memory;
  }
}

/// One learning entry: what this person kept for this kind of content, and
/// when they last kept it.
class EqMemoryEntry {
  const EqMemoryEntry({required this.presetKey, required this.usedAtMs});

  final String presetKey;

  /// Epoch milliseconds — the LRU clock and the staleness clock.
  final int usedAtMs;

  DateTime get usedAt => DateTime.fromMillisecondsSinceEpoch(usedAtMs);

  List<Object> toJson() => <Object>[presetKey, usedAtMs];

  @override
  bool operator ==(Object other) =>
      other is EqMemoryEntry &&
      other.presetKey == presetKey &&
      other.usedAtMs == usedAtMs;

  @override
  int get hashCode => Object.hash(presetKey, usedAtMs);
}
