import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'media_utils.dart';
import 'settings_service.dart';

/// Remembers where playback stopped, per file, across sessions.
///
/// One JSON map under `resume_positions`:
/// `{"<absolute path>": [posMs, durMs, updatedEpochMs]}` — local files
/// only (anything with `://` is skipped: live streams have no position
/// worth keeping). Capped at 1 000 entries, oldest pruned. A later
/// "Recent" list can read this same map.
///
/// THE SAVE RULE (the only rule): an entry is kept while
/// `5 s ≤ position ≤ duration − 10 s`; outside that window it is
/// REMOVED — a finished file starts over next time, and a deliberate
/// jump to `0:00` followed by a close starts over too. No special
/// cases. Files shorter than 30 s are never remembered.
///
/// The in-session stop memory (`PlayerService.stopMemory`) is mirrored
/// here the moment it is taken, so closing SALU after a Stop still
/// remembers. Both memories share the keep-threshold above — the user
/// never sees two systems.
class ResumeService {
  ResumeService._internal();

  /// The one and only resume store for the whole app.
  static final ResumeService instance = ResumeService._internal();

  static const String _key = 'resume_positions';
  static const int _maxEntries = 1000;
  static const Duration _minKeep = Duration(seconds: 5);
  static const Duration _tailMargin = Duration(seconds: 10);
  static const Duration _minFileLength = Duration(seconds: 30);
  static const Duration _diskThrottle = Duration(seconds: 5);

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
          if (value is List && value.length >= 2) {
            final int pos = _toInt(value[0]);
            final int dur = _toInt(value[1]);
            final int stamp = value.length >= 3 ? _toInt(value[2]) : 0;
            _entries[path] = <int>[pos, dur, stamp];
          }
        });
      }
    } catch (_) {
      // Corrupt store — start empty, silently.
      _entries.clear();
    }
  }

  static int _toInt(Object? v) => v is int ? v : (v is num ? v.round() : 0);

  // ── Gating (Settings → Resume) ─────────────────────────────────────────

  /// Whether the current mode remembers this path's kind at all.
  bool remembersKind(String path) {
    switch (SettingsService.instance.resumeMode.value) {
      case ResumeMode.all:
        return true;
      case ResumeMode.videoOnly:
        return MediaUtils.isVideo(path);
      case ResumeMode.audioOnly:
        return MediaUtils.isAudio(path);
      case ResumeMode.off:
        return false;
    }
  }

  /// The keep-window both memories share. Local files only.
  bool shouldKeep(String path, Duration pos, Duration dur) {
    if (path.contains('://')) return false; // streams: nothing to keep
    if (dur < _minFileLength) return false;
    if (pos < _minKeep) return false;
    if (dur - pos < _tailMargin) return false;
    return true;
  }

  // ── Reading ────────────────────────────────────────────────────────────

  /// The remembered position for [path], or `null` when nothing usable
  /// is stored (never stored, pruned, outside the keep-window, or gated
  /// off by the current Resume mode).
  Duration? savedPositionFor(String path) {
    if (!remembersKind(path)) return null;
    final List<int>? entry = _entries[path];
    if (entry == null || entry.length < 2) return null;
    final Duration pos = Duration(milliseconds: entry[0]);
    final Duration dur = Duration(milliseconds: entry[1]);
    if (!shouldKeep(path, pos, dur)) {
      _entries.remove(path);
      return null;
    }
    return pos;
  }

  // ── Writing ────────────────────────────────────────────────────────────

  /// Memory update on every position tick. The disk write is throttled
  /// to one every 5 s while playing; call [flush] for an immediate write
  /// (pause, Stop, item switch, window close).
  void update(String path, Duration pos, Duration dur) {
    if (path.isEmpty || path.contains('://')) return;
    if (!remembersKind(path)) return;
    if (!shouldKeep(path, pos, dur)) {
      // Outside the keep-window (near start, near end, too short):
      // remove — finished files start over next time.
      if (_entries.containsKey(path)) {
        _entries.remove(path);
        _maybeWriteDisk(force: true);
      }
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    _entries[path] = <int>[pos.inMilliseconds, dur.inMilliseconds, now];
    _maybeWriteDisk();
  }

  /// Drops any stored position for [path] (e.g. the current item is
  /// being restarted — a finished file must not resurrect old state).
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
                (a.value.length >= 3 ? a.value[2] : 0)
                    .compareTo(b.value.length >= 3 ? b.value[2] : 0));
      final int excess = _entries.length - _maxEntries;
      for (int i = 0; i < excess; i++) {
        _entries.remove(sorted[i].key);
      }
    }
    final Map<String, List<int>> out = _entries;
    return jsonEncode(out);
  }

  void _maybeWriteDisk({bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastDiskWrite) < _diskThrottle) return;
    _lastDiskWrite = now;
    unawaited(flush());
  }
}
