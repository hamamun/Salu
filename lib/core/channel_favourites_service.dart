import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm3u/channel_source.dart';
import 'queue_item.dart';

/// Saved favourite channels (playlist_imp.md §10.3 · point 6 Final).
///
/// Keyed **ID first, then name** (`tvg-id` → `tvg-name` → display name —
/// M11), stored per **playlist host** (M12), persisted in
/// `shared_preferences` with debounced writes. The queue itself stays
/// RAM-only; only the favourite keys are kept.
///
/// - Two playlists on one host share favourites (providers rotate
///   credentials, so a full-URL key would wipe everything on rotation).
/// - A local `.m3u` file uses its canonical path as its own key (M55) —
///   two local files never share a "no-host" bucket.
/// - Orphaned favourites are never pruned: the provider may restore the
///   channel tomorrow.
/// - Nothing here ever holds a stream URL or a full playlist URL, so
///   credentials can never leak through the store (§10.10e).
class ChannelFavouritesService {
  ChannelFavouritesService._internal();

  /// The one and only favourites store for the whole app.
  static final ChannelFavouritesService instance =
      ChannelFavouritesService._internal();

  static const String _prefsKey = 'salu_channel_favourites_v1';

  /// Writes are debounced — the whole file is rewritten on every change.
  static const Duration persistDebounce = Duration(milliseconds: 500);

  /// Favourite keys of the *current* playlist (empty while no channel
  /// list is loaded). A new unmodifiable set is published on every
  /// change so listeners rebuild once.
  final ValueNotifier<Set<String>> favourites =
      ValueNotifier<Set<String>>(const <String>{});

  /// Every playlist's keys, in memory (loaded once at startup).
  final Map<String, Set<String>> _store = <String, Set<String>>{};

  /// Key of the loaded playlist (`null` while local / empty).
  String? _playlistKey;

  String? get playlistKey => _playlistKey;

  bool _loaded = false;
  Timer? _debounce;

  /// Reads the persisted store once (called before the first frame).
  /// Republishes the current playlist's set, in case a playlist was
  /// already selected while loading.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((Object? k, Object? v) {
            if (k is String && v is List) {
              _store[k] = v.whereType<String>().toSet();
            }
          });
        }
      }
    } catch (_) {
      // Corrupt prefs — start clean, silently.
      _store.clear();
    }
    _publish();
  }

  /// Selects the playlist whose favourites [favourites] reports.
  /// Synchronous — the store is already in memory; when called before
  /// [load] finishes, the load republishes for this key.
  void setPlaylist(String? key) {
    _playlistKey = key;
    if (_loaded) _publish();
  }

  void _publish() {
    final Set<String>? set =
        _playlistKey == null ? null : _store[_playlistKey];
    favourites.value =
        set == null || set.isEmpty ? const <String>{} : Set<String>.unmodifiable(set);
  }

  /// Stable identity of a channel — ID first, then name (M11). Never
  /// the row number (order changes) and never the stream URL (it
  /// rotates). Duplicate display names stay distinct through their IDs.
  static String channelKey(QueueItem item) =>
      item.channelKey ?? item.label;

  /// Storage key of the playlist [source] came from: its **host** for a
  /// remote source, its own canonical path for a local file. Never the
  /// full URL (it carries credentials).
  static String playlistKeyForSource(String source) {
    final String s = source.trim();
    if (ChannelSource.isRemote(s)) {
      final String host = Uri.tryParse(s)?.host.toLowerCase() ?? '';
      return 'host:$host';
    }
    return 'file:${ChannelSource.localPath(s)}';
  }

  /// Whether [item] is a favourite of the current playlist.
  bool isFavourite(QueueItem item) =>
      favourites.value.contains(channelKey(item));

  /// Adds or removes [item] as a favourite of the current playlist.
  /// No-op while no channel list is loaded.
  void toggleFavourite(QueueItem item) {
    final String? key = _playlistKey;
    if (key == null) return;
    final String channel = channelKey(item);
    final Set<String> next = Set<String>.of(favourites.value);
    if (!next.remove(channel)) next.add(channel);
    _store[key] = next;
    favourites.value = Set<String>.unmodifiable(next);
    _debounce?.cancel();
    _debounce = Timer(persistDebounce, () => unawaited(flush()));
  }

  /// Writes the whole store now (also the debounce target, and the
  /// close-guard flush so a toggle can never be lost to a fast exit).
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(<String, List<String>>{
          for (final MapEntry<String, Set<String>> e in _store.entries)
            e.key: e.value.toList(growable: false),
        }),
      );
    } catch (_) {
      // In-memory state is already correct; persistence is best-effort.
    }
  }

  /// Forgets everything (tests only — production never clears the store;
  /// the bin unloads channels, not favourites, §10.9).
  @visibleForTesting
  void debugReset() {
    _debounce?.cancel();
    _debounce = null;
    _store.clear();
    _playlistKey = null;
    _loaded = false;
    favourites.value = const <String>{};
  }

  /// Seeds one playlist's keys without touching disk (tests only).
  @visibleForTesting
  void debugSeed(String playlistKey, Set<String> keys) {
    _loaded = true;
    _store[playlistKey] = Set<String>.of(keys);
    _playlistKey = playlistKey;
    _publish();
  }
}
