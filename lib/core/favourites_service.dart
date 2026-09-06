import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queue_service.dart';

/// Channel favourites (playlist_imp.md §10.3): a per-playlist set of
/// channel keys, persisted in `shared_preferences` (follow.md §7).
///
///   · A channel's key is `tvg-id` → display name, in that order (M11) —
///     never the index (order changes) and never the stream URL (it
///     rotates). QueueItem has no separate `tvg-name`, so the display
///     name is the fallback.
///   · A playlist's key is its HOST, not the full URL (M12) — providers
///     rotate credentials (`/live/USER/TOKEN/`); a URL key would silently
///     wipe every favourite on rotation.
///   · Writes are DEBOUNCED ~500 ms (the whole file is rewritten on every
///     change).
///   · Orphaned favourites are NEVER pruned on reload — the provider may
///     restore the channel tomorrow.
class FavouritesService {
  FavouritesService._();

  static final FavouritesService instance = FavouritesService._();

  static const String _prefsKey = 'm3u_favourites';
  static const Duration _writeDelay = Duration(milliseconds: 500);

  /// The favourite keys of the CURRENT playlist (empty while a local
  /// queue is loaded).
  final ValueNotifier<Set<String>> currentKeys =
      ValueNotifier<Set<String>>(const <String>{});

  /// The whole store: host → channel keys.
  Map<String, Set<String>> _byHost = <String, Set<String>>{};

  String? _host;
  Timer? _writeTimer;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final Map<String, Set<String>> out = <String, Set<String>>{};
      for (final MapEntry<Object?, Object?> e in decoded.entries) {
        final Object? value = e.value;
        if (value is List) {
          out[e.key.toString()] =
              value.map((Object? v) => v.toString()).toSet();
        }
      }
      _byHost = out;
    } catch (_) {
      _byHost = <String, Set<String>>{};
    }
  }

  /// The m3u load path announces the list's host here; a local open
  /// passes `null`. Orphaned keys are kept as-is (never pruned).
  void setPlaylistHost(String? host) {
    _host = host;
    currentKeys.value =
        Set<String>.unmodifiable(_byHost[host] ?? const <String>{});
  }

  /// A channel's favourite key (§10.3 / M11). Local files (`name == null`)
  /// have no key — the row bookmark simply never appears there.
  static String? favouriteKeyOf(QueueItem? item) {
    if (item == null || item.name == null) return null;
    final String? id = item.tvgId;
    if (id != null && id.trim().isNotEmpty) return id.trim();
    return item.name;
  }

  bool isFavourite(String? key) =>
      key != null && currentKeys.value.contains(key);

  /// Toggles [item]'s favourite state; the write lands ~500 ms later.
  void toggleItem(QueueItem? item) {
    final String? key = favouriteKeyOf(item);
    final String? host = _host;
    if (key == null || host == null) return;
    final Set<String> next = Set<String>.of(currentKeys.value);
    if (!next.remove(key)) next.add(key);
    currentKeys.value = Set<String>.unmodifiable(next);
    _byHost[host] = next;
    _scheduleWrite();
  }

  void _scheduleWrite() {
    _writeTimer?.cancel();
    _writeTimer = Timer(_writeDelay, _writeNow);
  }

  Future<void> _writeNow() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_byHost.map(
          (String k, Set<String> v) => MapEntry(k, v.toList()),
        )),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }
}
