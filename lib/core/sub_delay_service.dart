import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the subtitle sync offset, per file, across sessions.
///
/// One JSON map under `sub_delay_offsets`:
/// `{"<absolute path>": [offsetMs, updatedEpochMs]}` — local files only
/// (anything with `://` is skipped: a live stream's delay is the
/// stream's business, never the viewer's saved one). Capped at 1 000
/// entries, oldest pruned — the same shape as `resume_service.dart`,
/// because it answers the same question in the same place.
///
/// THE KEEP RULE: an offset is kept only while it is NOT zero. A viewer
/// who puts a file back in sync (`0.0 s`) has deleted the memory — the
/// next open starts in sync. No special cases.
///
/// Why this exists at all (owner 2026-09-13): mpv's `sub-delay` is a
/// RUNTIME option — it is not per-file, and a value set for one item
/// survives into the next one in the same mpv instance. So the player
/// must write an explicit value on every file landing (see
/// `PlayerService._applySavedSubDelay`); this store is what that write
/// reads.
class SubDelayService {
  SubDelayService._internal();

  /// The one and only sync store for the whole app.
  static final SubDelayService instance = SubDelayService._internal();

  static const String _key = 'sub_delay_offsets';
  static const int _maxEntries = 1000;
  static const Duration _diskThrottle = Duration(seconds: 2);

  final Map<String, List<int>> _entries = <String, List<int>>{};
  DateTime _lastDiskWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Loads the store once at startup (after `SettingsService.load()`),
  /// so lookups at open time are synchronous.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((String path, Object? value) {
          if (value is List && value.isNotEmpty) {
            _entries[path] = <int>[
              _toInt(value[0]),
              value.length >= 2 ? _toInt(value[1]) : 0,
            ];
          }
        });
      }
    } catch (_) {
      // Corrupt store — start empty, silently.
      _entries.clear();
    }
  }

  static int _toInt(Object? v) => v is int ? v : (v is num ? v.round() : 0);

  // ── Reading ────────────────────────────────────────────────────────────

  /// The remembered offset for [path] — [Duration.zero] when nothing is
  /// stored (never stored, cleared, or a stream).
  Duration savedOffsetFor(String path) {
    if (path.isEmpty || path.contains('://')) return Duration.zero;
    final List<int>? entry = _entries[path];
    if (entry == null || entry.isEmpty || entry[0] == 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: entry[0]);
  }

  // ── Writing ────────────────────────────────────────────────────────────

  /// Memory update on every sync change. The disk write is throttled to
  /// one every 2 s while the viewer drags; call [flush] for an immediate
  /// write (item switch, Stop, window close).
  void update(String path, Duration offset) {
    if (path.isEmpty || path.contains('://')) return;
    if (offset == Duration.zero) {
      // Back in sync = no memory (THE KEEP RULE).
      if (_entries.remove(path) != null) {
        _maybeWriteDisk(force: true);
      }
      return;
    }
    _entries[path] = <int>[
      offset.inMilliseconds,
      DateTime.now().millisecondsSinceEpoch,
    ];
    _maybeWriteDisk();
  }

  /// Drops any stored offset for [path].
  void remove(String path) {
    if (_entries.remove(path) != null) {
      _maybeWriteDisk(force: true);
    }
  }

  /// Immediate disk write (also prunes to the 1 000-entry cap).
  Future<void> flush() async {
    _lastDiskWrite = DateTime.now();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _encode());
    } catch (_) {
      // Best-effort; the in-memory map stays authoritative.
    }
  }

  String _encode() {
    // Prune oldest beyond the cap.
    if (_entries.length > _maxEntries) {
      final List<MapEntry<String, List<int>>> sorted =
          _entries.entries.toList()
            ..sort((MapEntry<String, List<int>> a,
                    MapEntry<String, List<int>> b) =>
                (a.value.length >= 2 ? a.value[1] : 0)
                    .compareTo(b.value.length >= 2 ? b.value[1] : 0));
      final int excess = _entries.length - _maxEntries;
      for (int i = 0; i < excess; i++) {
        _entries.remove(sorted[i].key);
      }
    }
    return jsonEncode(_entries);
  }

  void _maybeWriteDisk({bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastDiskWrite) < _diskThrottle) return;
    _lastDiskWrite = now;
    unawaited(flush());
  }
}

/// The sync offset's ONE spelling — `+0.4 s`, `-1.0 s`, `0.0 s`.
///
/// Top-level so the panel's sync row and the OSD deck both read the
/// same number the same way: a control and its own echo can never
/// drift apart. One decimal is the step the row and Z/X move in, so
/// the label never shows a digit the viewer did not set.
String formatSubDelay(double seconds) {
  final String magnitude = seconds.abs().toStringAsFixed(1);
  if (seconds == 0) return '0.0 s';
  return '${seconds > 0 ? '+' : '-'}$magnitude s';
}
