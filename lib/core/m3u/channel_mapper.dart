import '../queue_item.dart';
import 'm3u_aliases.dart';
import 'm3u_parser.dart';

/// Turns raw [M3uEntry]s into SALU's [QueueItem] channel records
/// (playlist_imp.md §10.0 point 2 · §10.2a · §10.10c). One mapper per
/// playlist load — it owns that load's intern pool, so repeated
/// group/language/country text is shared within the playlist and released
/// with the load (never a process-wide pool that keeps old playlists
/// alive).
///
/// Boundary rules (§10.16 patches 1–2, tested in `test/`):
/// - blank optional values → `null`;
/// - category = `group-title` when non-blank, else that entry's `#EXTGRP`
///   when non-blank, else `null`;
/// - label = title → `tvg-name` → `tvg-id` → `Unknown` (never the URL);
/// - language/country pass through the alias tables, whole (no splitting);
/// - a relative stream / logo URL resolves against the playlist's base;
/// - the lowercase `name + group` search key is computed once, here.
class ChannelMapper {
  ChannelMapper({Uri? base}) : _base = base;

  /// Where the playlist came from — resolves relative entry/logo URLs.
  /// A local file passes its `file:` URI; `null` leaves URLs as written.
  final Uri? _base;

  final Map<String, String> _pool = <String, String>{};

  /// How many distinct strings the pool shares (diagnostics/tests only).
  int get internedCount => _pool.length;

  String? _intern(String? value) {
    if (value == null) return null;
    return _pool.putIfAbsent(value, () => value);
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final String s = value.trim();
    return s.isEmpty ? null : s;
  }

  /// Maps one entry. Returns `null` only for an entry with an empty URL
  /// (the parser never produces one, but the boundary stays total).
  QueueItem? map(M3uEntry entry) {
    final String url = _resolve(entry.url);
    if (url.isEmpty) return null;

    final String? tvgId = _clean(entry['tvg-id']);
    final String? tvgName = _clean(entry['tvg-name']);
    final String name = _clean(entry.title) ?? tvgName ?? tvgId ?? 'Unknown';

    // Point 5 FINAL: an explicit non-blank group-title wins; a blank or
    // absent one falls back to the same entry's #EXTGRP.
    final String? group =
        _intern(_clean(entry['group-title']) ?? _clean(entry.extgrp));
    final String? language = _intern(normaliseLanguage(entry['tvg-language']));
    final String? country = _intern(normaliseCountry(entry['tvg-country']));

    final String? logoRaw = _clean(entry['tvg-logo']);
    final String? logoUrl = logoRaw == null ? null : _resolve(logoRaw);

    final String searchKey =
        group == null ? name.toLowerCase() : '${name.toLowerCase()} ${group.toLowerCase()}';

    return QueueItem(
      url,
      name: name,
      tvgId: tvgId,
      tvgName: tvgName,
      group: group,
      language: language,
      country: country,
      logoUrl: logoUrl,
      searchKey: searchKey,
    );
  }

  /// Resolves [raw] against the base when it is relative. Absolute URLs
  /// and Windows drive paths pass through untouched (a URL's spelling is
  /// its key — never rewritten, §5).
  String _resolve(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || _base == null) return s;
    if (s.contains('://')) return s;
    // `C:\x` / `C:/x` — a local absolute path inside a local playlist.
    if (s.length >= 3 && s.codeUnitAt(1) == 0x3A) {
      final int c = s.codeUnitAt(0);
      final bool letter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      if (letter && (s.codeUnitAt(2) == 0x2F || s.codeUnitAt(2) == 0x5C)) {
        return s;
      }
    }
    // `//host/path` (scheme-relative) and plain relative paths.
    try {
      final Uri resolved = _base.resolve(s.replaceAll('\\', '/'));
      if (resolved.scheme == 'file') return resolved.toFilePath(windows: true);
      return resolved.toString();
    } on FormatException {
      return s;
    }
  }
}
