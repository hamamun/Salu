import '../media_utils.dart';

/// What counts as a **channel directory** source, and what such a source
/// is called out loud (playlist_imp.md §10.0 · M-3 · M55).
///
/// Two questions, one place, so the router, the loader and the toast can
/// never disagree:
///
/// - [looksLikeDirectory] — should SALU read this itself instead of
///   handing it to mpv? An `.m3u` / `.m3u8` **file** always qualifies
///   (M55: only the fetch differs); a URL qualifies on its own spelling
///   (`…/list.m3u8`, `get.php?type=m3u_plus`). Anything else stays a
///   plain stream. A source that qualifies but turns out to be an HLS
///   manifest or not M3U text at all is handed back to mpv by the loader
///   (`ChannelListHls` / `ChannelListNotPlaylist`), so a false positive
///   costs one sniffed request, never a broken open.
/// - [displayName] — the playlist's **name** for the "Failed to load"
///   toast (§10.10b). A remote source reports its **host only**: a
///   provider URL carries credentials in its path and query, and those
///   may never be rendered or logged (§10.10e).
class ChannelSource {
  ChannelSource._();

  /// Whether [source] is a network source rather than a local path.
  static bool isRemote(String source) {
    final String s = source.trim();
    if (!s.contains('://')) return false;
    return !_isFileUri(s);
  }

  static bool _isFileUri(String source) =>
      source.length >= 5 && source.substring(0, 5).toLowerCase() == 'file:';

  /// The local path behind [source] (`file:` URIs are unwrapped), in
  /// SALU's one canonical spelling; the trimmed source itself for
  /// anything else. `MediaUtils.canonicalPath` alone would return a
  /// `file:` URI untouched (it treats every `://` as a stream key), so
  /// the URI is decoded first — the loader needs a real path to read.
  static String localPath(String source) {
    final String s = source.trim();
    if (_isFileUri(s)) {
      final Uri? uri = Uri.tryParse(s);
      if (uri != null) {
        try {
          return MediaUtils.canonicalPath(
              uri.toFilePath(windows: _windows(uri)));
        } on UnsupportedError {
          // A malformed file: URI — fall through to the raw text.
        }
      }
    }
    return MediaUtils.canonicalPath(s);
  }

  /// `file:///C:/x` is a Windows path, `file:///home/x` a POSIX one —
  /// decided by the URI itself so tests do not depend on the host OS.
  static bool _windows(Uri uri) {
    final String p = uri.path;
    return p.length >= 3 &&
        p.codeUnitAt(0) == 0x2F &&
        p.codeUnitAt(2) == 0x3A;
  }

  /// Whether SALU should read [source] as a channel directory (M-3).
  static bool looksLikeDirectory(String source) {
    final String s = source.trim();
    if (s.isEmpty) return false;
    if (!isRemote(s)) return MediaUtils.isPlaylist(localPath(s));

    final Uri? uri = Uri.tryParse(s);
    if (uri == null) return false;
    final String scheme = uri.scheme.toLowerCase();
    // Only the two schemes the loader can fetch. `udp://`, `rtsp://`,
    // `srt://`… are live transports — never directories.
    if (scheme != 'http' && scheme != 'https') return false;

    final String path = uri.path.toLowerCase();
    if (path.endsWith('.m3u') || path.endsWith('.m3u8')) return true;

    // Xtream-style directories: `get.php?username=…&type=m3u_plus`.
    final String query = uri.query.toLowerCase();
    return query.contains('type=m3u') ||
        query.contains('format=m3u') ||
        query.contains('output=m3u');
  }

  /// The playlist's name for a toast — never its URL (§10.10e).
  ///
  /// A local file reports its file name; a remote source reports its
  /// **host**, which is the most that can be shown without exposing the
  /// credentials a provider URL keeps in its path, query or user-info.
  static String displayName(String source) {
    final String s = source.trim();
    if (s.isEmpty) return 'Playlist';
    if (!isRemote(s)) {
      final String name = MediaUtils.displayName(localPath(s));
      return name.isEmpty ? 'Playlist' : name;
    }
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return 'Playlist';
    return uri.host;
  }
}
