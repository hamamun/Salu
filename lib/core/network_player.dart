import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'player_service.dart';

/// One entry parsed out of an extended M3U playlist.
class IptvChannel {
  const IptvChannel({
    required this.title,
    required this.url,
    this.group,
    this.country,
    this.language,
    this.logo,
  });

  final String title;
  final String url;
  final String? group;
  final String? country;
  final String? language;
  final String? logo;
}

/// How the (potentially massive) IPTV playlist is grouped in the UI.
enum IptvGrouping {
  none('Flat / None'),
  category('Category'),
  country('Country'),
  language('Language');

  const IptvGrouping(this.label);

  final String label;
}

/// Network stream & IPTV playback (Phase 6 · Step 3).
///
/// Handles saved M3U URLs: fetches and parses the playlist, feeds every
/// channel into the mpv queue, and exposes the parsed metadata so the
/// Playlist tab can offer the "Group By" filter.
class NetworkPlayer extends ChangeNotifier {
  NetworkPlayer._();

  static final NetworkPlayer instance = NetworkPlayer._();

  /// An M3U with more entries than this counts as a "massive" IPTV list and
  /// unlocks the grouping / clear controls in the Playlist tab.
  static const int massivePlaylistThreshold = 25;

  final List<IptvChannel> _channels = <IptvChannel>[];
  bool _loading = false;
  String? _sourceName;

  List<IptvChannel> get channels => List<IptvChannel>.unmodifiable(_channels);

  bool get loading => _loading;

  /// Name of the M3U currently loaded, if any.
  String? get sourceName => _sourceName;

  bool get isIptvLoaded => _channels.isNotEmpty;

  bool get isMassivePlaylist => _channels.length >= massivePlaylistThreshold;

  IptvGrouping _grouping = IptvGrouping.none;
  IptvGrouping get grouping => _grouping;
  set grouping(IptvGrouping value) {
    if (_grouping == value) return;
    _grouping = value;
    notifyListeners();
  }

  /// Distinct group values for the active [grouping], sorted.
  List<String> get groupValues {
    final Set<String> values = <String>{};
    for (final IptvChannel channel in _channels) {
      final String? value = valueFor(channel);
      if (value != null && value.isNotEmpty) values.add(value);
    }
    final List<String> list = values.toList()..sort();
    return list;
  }

  String? valueFor(IptvChannel channel) {
    switch (_grouping) {
      case IptvGrouping.none:
        return null;
      case IptvGrouping.category:
        return channel.group;
      case IptvGrouping.country:
        return channel.country;
      case IptvGrouping.language:
        return channel.language;
    }
  }

  /// Plays a saved stream URL. Plain media URLs go straight to mpv; `.m3u`
  /// playlists are fetched, parsed and turned into a channel queue.
  Future<String> playStream(String url, {String? name}) async {
    final PlayerService player = PlayerService.instance;
    if (!_looksLikeM3u(url)) {
      clear();
      _sourceName = name;
      await player.openPath(url, smartQueue: false);
      return 'Playing ${name ?? url}';
    }

    _loading = true;
    notifyListeners();
    try {
      final http.Response response = await http
          .get(Uri.parse(url), headers: <String, String>{
        'User-Agent': 'SALU-Player',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        return 'Stream failed (HTTP ${response.statusCode})';
      }

      final List<IptvChannel> parsed = parseM3u(utf8.decode(
        response.bodyBytes,
        allowMalformed: true,
      ));
      if (parsed.isEmpty) {
        // Not a playlist after all — hand the URL to mpv directly.
        clear();
        await player.openPath(url, smartQueue: false);
        return 'Playing ${name ?? url}';
      }

      _channels
        ..clear()
        ..addAll(parsed);
      _sourceName = name ?? url;
      _grouping = IptvGrouping.none;

      await player.openQueue(
        parsed.map((IptvChannel c) => c.url).toList(),
      );
      return 'Loaded ${parsed.length} channels';
    } catch (error) {
      debugPrint('[SALU] stream load failed: $error');
      return 'Stream failed: could not load playlist';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Drops the loaded IPTV metadata (the mpv queue is cleared separately).
  void clear() {
    if (_channels.isEmpty && _sourceName == null) return;
    _channels.clear();
    _sourceName = null;
    _grouping = IptvGrouping.none;
    notifyListeners();
  }

  /// Title for the queue entry at [index], falling back to the raw URL.
  String? titleAt(int index) {
    if (index < 0 || index >= _channels.length) return null;
    return _channels[index].title;
  }

  static bool _looksLikeM3u(String url) {
    final String lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.m3u') || lower.endsWith('.m3u8');
  }

  /// Parses an extended M3U document (`#EXTINF` + attributes).
  static List<IptvChannel> parseM3u(String content) {
    final List<IptvChannel> channels = <IptvChannel>[];
    final List<String> lines = const LineSplitter().convert(content);

    String? title;
    String? group;
    String? country;
    String? language;
    String? logo;

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.toUpperCase().startsWith('#EXTINF')) {
        final int comma = line.indexOf(',');
        title = comma >= 0 && comma + 1 < line.length
            ? line.substring(comma + 1).trim()
            : null;
        final String attrs = comma >= 0 ? line.substring(0, comma) : line;
        group = _attr(attrs, 'group-title');
        country = _attr(attrs, 'tvg-country');
        language = _attr(attrs, 'tvg-language');
        logo = _attr(attrs, 'tvg-logo');
        continue;
      }

      if (line.startsWith('#')) continue;

      channels.add(IptvChannel(
        title: (title == null || title.isEmpty) ? line : title,
        url: line,
        group: group,
        country: country,
        language: language,
        logo: logo,
      ));
      title = null;
      group = null;
      country = null;
      language = null;
      logo = null;
    }

    return channels;
  }

  static String? _attr(String source, String key) {
    final RegExpMatch? match =
        RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(source);
    final String? value = match?.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}
