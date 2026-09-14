import 'dart:convert';

import 'tune_model.dart';

/// The Auto EQ learning map (eq_imp.md §5) — bounded, on-device, no network.
///
/// Shape, one JSON blob inside the settings store:
/// `{"audio|jazz": ["pop", 1720000000000], "video|the office": ["", …, [0,2,…]]}`
/// — key = file type + genre/series, value = the KEPT choice + last-used time
/// (≈ 100 bytes an entry, + 10 numbers when the kept thing is a full curve,
/// §7c).
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
  EqMemory.empty() : _entries = <String, EqMemoryEntry>{};

  /// Beyond this many entries the least-recently-used one is evicted.
  static const int maxEntries = 500;

  /// Entries untouched for longer than this are dropped at app start.
  static const Duration staleness = Duration(days: 90);

  final Map<String, EqMemoryEntry> _entries;

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  Iterable<String> get keys => _entries.keys;

  /// The kept choice for a key, `null` when nothing was ever kept. Empty for
  /// a key whose kept thing is a custom curve (§7c) — ask [entryFor] for the
  /// numbers in that case.
  String? presetFor(String key) {
    final String? preset = _entries[key]?.presetKey;
    return preset == null || preset.isEmpty ? null : preset;
  }

  EqMemoryEntry? entryFor(String key) => _entries[key];

  /// Records a KEPT choice (a hover never teaches — §5's rule). The entry is
  /// created or refreshed, and the LRU cap is applied immediately so [length]
  /// never overshoots.
  ///
  /// [presetKey] is the named stop the person landed on (`''` for a free
  /// curve), [gains] the curve they kept — §7c: the full curve is what
  /// makes Auto return *their* sound, not merely the preset nearest to it.
  void teach(
    String key,
    String presetKey, {
    List<double>? gains,
    DateTime? now,
  }) {
    if (key.isEmpty) return;
    final List<double>? curve = _cleanCurve(gains);
    if (presetKey.isEmpty && curve == null) return;
    _entries[key] = EqMemoryEntry(
      presetKey: presetKey,
      usedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
      gains: curve,
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
      gains: e.gains,
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

  /// A curve is only a curve when it is the full 10 bands of numbers —
  /// anything else is dropped, silently (a half-written blob must not invent
  /// a sound out of nothing).
  static List<double>? _cleanCurve(List<double>? raw) {
    if (raw == null || raw.length < kEqBandCount) return null;
    final List<double> out = List<double>.filled(kEqBandCount, 0);
    for (int i = 0; i < kEqBandCount; i++) {
      final double v = raw[i];
      if (!v.isFinite) return null;
      out[i] = clampRange(v, kEqGainMin, kEqGainMax);
    }
    return out;
  }

  // ── Wire format ────────────────────────────────────────────────────────

  /// `key → [preset, usedAtMs, curve?]` — the same compact shape the resume
  /// and subtitle-sync stores use, with the §7c curve appended only when the
  /// kept thing *was* a curve.
  String encode() {
    final Map<String, List<Object>> out = <String, List<Object>>{};
    _entries.forEach((String key, EqMemoryEntry e) {
      out[key] = e.toJson();
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
      final EqMemoryEntry? entry = _entryFrom(value);
      if (entry != null) memory._entries[key] = entry;
    });
    memory._evictToCap();
    return memory;
  }

  /// One row of the map, in either the current shape (`[preset, ms, curve?]`)
  /// or the first one (`[preset, ms]`, and a map with `preset` / `used`).
  static EqMemoryEntry? _entryFrom(Object? value) {
    if (value is List && value.isNotEmpty) {
      final List<double>? gains = value.length >= 3 ? _curveFrom(value[2]) : null;
      final String preset = value.first is String ? value.first as String : '';
      if (preset.isEmpty && gains == null) return null;
      return EqMemoryEntry(
        presetKey: preset,
        usedAtMs: value.length >= 2 && value[1] is num
            ? (value[1] as num).toInt()
            : 0,
        gains: gains,
      );
    }
    if (value is Map) {
      final Object? preset = value['preset'];
      final List<double>? gains = _curveFrom(value['gains']);
      if (preset is! String && gains == null) return null;
      final Object? ts = value['used'];
      return EqMemoryEntry(
        presetKey: preset is String ? preset : '',
        usedAtMs: ts is num ? ts.toInt() : 0,
        gains: gains,
      );
    }
    return null;
  }

  /// A stored curve, tolerantly: JSON gives `List<dynamic>`, and anything
  /// short, non-numeric or out of range is not a curve.
  static List<double>? _curveFrom(Object? raw) {
    if (raw is! List) return null;
    if (raw.length < kEqBandCount) return null;
    final List<double> out = <double>[];
    for (int i = 0; i < kEqBandCount; i++) {
      final Object? v = raw[i];
      if (v is! num || !v.toDouble().isFinite) return null;
      out.add(clampRange(v.toDouble(), kEqGainMin, kEqGainMax));
    }
    return out;
  }
}

/// One learning entry: what this person kept for this kind of content, and
/// when they last kept it.
class EqMemoryEntry {
  const EqMemoryEntry({
    required this.presetKey,
    required this.usedAtMs,
    this.gains,
  });

  /// The named stop that was kept — `''` when they kept a free curve.
  final String presetKey;

  /// Epoch milliseconds — the LRU clock and the staleness clock.
  final int usedAtMs;

  /// The 10 gains they kept (eq_imp.md §7c), `null` for a preset-name-only
  /// entry (v1's shape, and the shape a named stop writes today).
  final List<double>? gains;

  DateTime get usedAt => DateTime.fromMillisecondsSinceEpoch(usedAtMs);

  bool get hasCurve => gains != null && gains!.length == kEqBandCount;

  List<Object> toJson() => <Object>[
        presetKey,
        usedAtMs,
        if (gains != null) gains!,
      ];

  bool sameAs(EqMemoryEntry other) {
    if (other.presetKey != presetKey || other.usedAtMs != usedAtMs) return false;
    if (other.gains == null || gains == null) return other.gains == gains;
    if (other.gains!.length != gains!.length) return false;
    for (int i = 0; i < gains!.length; i++) {
      if (other.gains![i] != gains![i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is EqMemoryEntry && sameAs(other);

  @override
  int get hashCode =>
      Object.hash(presetKey, usedAtMs, gains == null ? null : Object.hashAll(gains!));
}
