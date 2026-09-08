import 'media_utils.dart';

/// One queue entry (playlist_imp.md §10.0 — point 2 FINAL).
///
/// Local files fill [url] only; m3u channels add their details. The record
/// is immutable and the queue holds exactly ONE list of these — no parallel
/// metadata table, no manual mode flag, nothing on disk. Search / group
/// views refer to queue indexes, never to copies of these objects.
class QueueItem {
  const QueueItem(
    this.url, {
    this.name,
    this.tvgId,
    this.tvgName,
    this.group,
    this.language,
    this.country,
    this.logoUrl,
    this.searchKey,
  });

  /// What mpv receives — a canonical local path or a stream URL. Local
  /// mode only needs this.
  final String url;

  /// Channel display label; `null` for local files (they show their file
  /// name). The parser guarantees a non-null label for every channel
  /// (`name → tvg-name → tvg-id → "Unknown"`), so this is also what makes
  /// a list a *channel* list.
  final String? name;

  /// `tvg-id` / `tvg-name` as supplied — identity, not category.
  final String? tvgId;
  final String? tvgName;

  /// Category: that entry's `group-title`, else its `#EXTGRP`, else
  /// `null` (shown as `Unknown`, last — §10.2a).
  final String? group;

  /// `tvg-language` / `tvg-country`, normalised (§10.2); `null` = missing.
  final String? language;
  final String? country;

  /// Image *address* only — never image bytes (§10.4). May carry
  /// credentials: never render or log it (§10.10e).
  final String? logoUrl;

  /// Precomputed lowercase `name + group` search key (§10.10c); `null` for
  /// local files, which search by display name.
  final String? searchKey;

  /// A local file / plain URL row (every optional field `null`).
  const QueueItem.local(this.url)
      : name = null,
        tvgId = null,
        tvgName = null,
        group = null,
        language = null,
        country = null,
        logoUrl = null,
        searchKey = null;

  /// Whether this entry came from a channel list.
  bool get isChannel => name != null;

  /// What a row, an OSD card or the title prints. For a channel this is
  /// its supplied label — never a credential-bearing URL (§10.10e).
  String get label => name ?? MediaUtils.displayName(url);

  /// Lowercase text a search term is matched against (§10.9): the
  /// precomputed key for channels, the display name for local files.
  String get searchText => searchKey ?? label.toLowerCase();

  /// Stable channel identity — ID first, then name (§10.0 / §10.3):
  /// `tvg-id → tvg-name → display name`. Never the row number or the
  /// stream URL. `null` for local files.
  String? get channelKey => isChannel ? (tvgId ?? tvgName ?? name) : null;

  /// The same entry with [url] spelled canonically (applied on the way
  /// into the queue). Returns `this` when nothing changes, so channel
  /// records are never re-allocated.
  QueueItem withUrl(String canonical) {
    if (canonical == url) return this;
    return QueueItem(
      canonical,
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

  @override
  String toString() => 'QueueItem(${isChannel ? label : url})';
}
