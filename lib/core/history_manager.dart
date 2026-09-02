import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One remembered playback session.
class HistoryEntry {
  const HistoryEntry({
    required this.uri,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String uri;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// True when the file was watched (almost) to the end — resuming such a
  /// file would drop the user on the credits, so we start it over instead.
  bool get finished {
    if (duration <= Duration.zero) return false;
    final Duration remaining = duration - position;
    return remaining <= const Duration(seconds: 10);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uri': uri,
        'pos': position.inMilliseconds,
        'dur': duration.inMilliseconds,
        'at': updatedAt.millisecondsSinceEpoch,
      };

  static HistoryEntry? fromJson(Map<String, dynamic> json) {
    final Object? uri = json['uri'];
    if (uri is! String || uri.isEmpty) return null;
    return HistoryEntry(
      uri: uri,
      position: Duration(milliseconds: (json['pos'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (json['dur'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['at'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Unlimited playback history + seamless resume (Phase 5 · Step 3).
///
/// Positions are written to `shared_preferences` while playing (throttled to
/// one write every few seconds) so reopening a file silently continues from
/// exactly where the user left off — no pop-up, just an OSD flash.
class HistoryManager extends ChangeNotifier {
  HistoryManager._();

  static final HistoryManager instance = HistoryManager._();

  static const String _key = 'playback.history';

  /// Files shorter than this are never resumed (clips, ringtones…).
  static const Duration minResumableDuration = Duration(minutes: 1);

  /// Don't bother resuming the first few seconds.
  static const Duration minResumablePosition = Duration(seconds: 15);

  /// Cap the stored list so preferences stay small; "unlimited" in practice.
  static const int maxEntries = 2000;

  final Map<String, HistoryEntry> _entries = <String, HistoryEntry>{};
  SharedPreferences? _store;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// Most recently watched first.
  List<HistoryEntry> get entries {
    final List<HistoryEntry> list = _entries.values.toList()
      ..sort((HistoryEntry a, HistoryEntry b) =>
          b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> load() async {
    try {
      final SharedPreferences store = await SharedPreferences.getInstance();
      _store = store;
      final String? raw = store.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final Object? item in decoded) {
        if (item is! Map) continue;
        final HistoryEntry? entry =
            HistoryEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry != null) _entries[entry.uri] = entry;
      }
    } catch (error) {
      debugPrint('[SALU] history load failed: $error');
    }
    notifyListeners();
  }

  /// Remembers where [uri] currently is. Writes are throttled unless
  /// [force] is set (used when the file closes or the app quits).
  void remember({
    required String uri,
    required Duration position,
    required Duration duration,
    bool force = false,
  }) {
    if (uri.isEmpty) return;
    _entries[uri] = HistoryEntry(
      uri: uri,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    final DateTime now = DateTime.now();
    if (force || now.difference(_lastWrite) >= const Duration(seconds: 5)) {
      _lastWrite = now;
      _flush();
    }
  }

  /// The stored position for [uri] worth resuming from, or `null`.
  Duration? resumePositionFor(String uri) {
    final HistoryEntry? entry = _entries[uri];
    if (entry == null) return null;
    if (entry.finished) return null;
    if (entry.duration > Duration.zero &&
        entry.duration < minResumableDuration) {
      return null;
    }
    if (entry.position < minResumablePosition) return null;
    return entry.position;
  }

  HistoryEntry? entryFor(String uri) => _entries[uri];

  void clear() {
    _entries.clear();
    _flush();
    notifyListeners();
  }

  void _flush() {
    final SharedPreferences? store = _store;
    if (store == null) return;
    final List<HistoryEntry> list = entries;
    final List<HistoryEntry> capped =
        list.length > maxEntries ? list.sublist(0, maxEntries) : list;
    try {
      store.setString(
        _key,
        jsonEncode(capped.map((HistoryEntry e) => e.toJson()).toList()),
      );
    } catch (error) {
      debugPrint('[SALU] history save failed: $error');
    }
  }
}
