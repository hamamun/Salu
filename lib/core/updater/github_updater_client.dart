import 'dart:convert';

/// SALU's GitHub release client (updater.md §1) — the Media Playback
/// Engine's and the Stream Parser's upstream.
///
/// Two feeds, one API shape (`GET /repos/{owner}/{repo}/releases/latest`):
/// * `media-kit/libmpv-win32-video-cmake` — the exact libmpv Windows builds
///   `media_kit_libs_video` itself compiles against (its CMake pulls
///   `mpv-dev-x86_64-*.7z` from here). The release tag (e.g. `20241021`)
///   is the component's version.
/// * `yt-dlp/yt-dlp` — the standalone `yt-dlp.exe`, whose release also
///   ships `SHA2-256SUMS` for the integrity check of updater.md §3.
///
/// Parsing is pure ([parseRelease], [pickMpvAsset], …); only the two
/// fetchers touch HTTP, and they are injected.
class GitHubUpdaterClient {
  GitHubUpdaterClient({required this.fetchText});

  /// How feed documents (JSON, checksum text) are fetched.
  final Future<String> Function(Uri url) fetchText;

  /// The libmpv Windows builds repo (updater.md §1 · "media-kit releases").
  static const String mpvRepo = 'media-kit/libmpv-win32-video-cmake';

  /// The yt-dlp repo (updater.md §1 · GitHub).
  static const String ytDlpRepo = 'yt-dlp/yt-dlp';

  /// `GET https://api.github.com/repos/{repo}/releases/latest` — the
  /// newest non-draft, non-prerelease release.
  static Uri latestReleaseUrl(String repo) {
    return Uri.parse('https://api.github.com/repos/$repo/releases/latest');
  }

  /// Parses one release document. Tolerant: missing pieces degrade to
  /// empty lists/strings; returns `null` only when the document is not a
  /// release object at all.
  static GithubRelease? parseRelease(String json) {
    try {
      final Object? doc = jsonDecode(json);
      if (doc is! Map<String, Object?>) return null;
      final Object? tag = doc['tag_name'];
      if (tag is! String || tag.isEmpty) return null;
      final List<GithubAsset> assets = <GithubAsset>[];
      final Object? rawAssets = doc['assets'];
      if (rawAssets is List<Object?>) {
        for (final Object? raw in rawAssets) {
          if (raw is! Map<String, Object?>) continue;
          final Object? name = raw['name'];
          final Object? url = raw['browser_download_url'];
          if (name is! String || name.isEmpty) continue;
          if (url is! String || url.isEmpty) continue;
          final Object? size = raw['size'];
          assets.add(GithubAsset(
            name: name,
            url: url,
            size: size is int ? size : 0,
          ));
        }
      }
      return GithubRelease(
        tag: tag,
        assets: assets,
        prerelease: doc['prerelease'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// The one x64 build SALU wants: `mpv-dev-x86_64-*.7z` — the dev archive
  /// `media_kit` itself extracts `libmpv-2.dll` from. Hard rules:
  /// * **x64 only** (updater.md §9 · Architecture Guard) — `i686` and
  ///   `aarch64` assets never qualify;
  /// * **no `-v3-` builds** — those need x86-64-v3 CPUs; the plain
  ///   `mpv-dev-x86_64-…` archive runs everywhere x64 runs.
  static GithubAsset? pickMpvAsset(GithubRelease release) {
    for (final GithubAsset asset in release.assets) {
      final String n = asset.name;
      if (!n.startsWith('mpv-dev-x86_64-')) continue;
      if (!n.endsWith('.7z')) continue;
      if (n.contains('-v3-')) continue;
      return asset;
    }
    return null;
  }

  /// The standalone Windows binary, exactly `yt-dlp.exe` (x64 — the
  /// `yt-dlp_x86.exe` sibling is 32-bit and never qualifies).
  static GithubAsset? pickYtDlpAsset(GithubRelease release) {
    for (final GithubAsset asset in release.assets) {
      if (asset.name == 'yt-dlp.exe') return asset;
    }
    return null;
  }

  /// The release's `SHA2-256SUMS` asset (updater.md §3 · "Verify integrity
  /// / checksums"), when it publishes one.
  static GithubAsset? pickChecksumsAsset(GithubRelease release) {
    for (final GithubAsset asset in release.assets) {
      if (asset.name == 'SHA2-256SUMS') return asset;
    }
    return null;
  }

  /// One SHA-256 hex digest from a `SHA2-256SUMS` document for [fileName].
  ///
  /// Format is coreutils `sha256sum`:
  /// `<hex> *yt-dlp.exe` (binary mode) or `<hex>  yt-dlp.exe` (text mode).
  /// `null` = the document does not mention the file.
  static String? sha256For(String sumsText, String fileName) {
    for (final String rawLine in const LineSplitter().convert(sumsText)) {
      final String line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final int sep = line.indexOf(RegExp(r'\s'));
      if (sep <= 0) continue;
      final String hash = line.substring(0, sep).toLowerCase();
      String name = line.substring(sep).trim();
      // Binary-mode marker: `*filename`.
      if (name.startsWith('*')) name = name.substring(1);
      if (name == fileName) {
        return hash.length == 64 ? hash : null;
      }
    }
    return null;
  }

  /// The newest release of [repo]. `null` when the API says nothing useful
  /// (rate-limited, renamed, malformed) — never throws for feed shape.
  Future<GithubRelease?> latestRelease(String repo) async {
    final String body = await fetchText(latestReleaseUrl(repo));
    return parseRelease(body);
  }

  /// Downloads a small text asset (the checksums file). Throws when the
  /// network cannot reach it.
  Future<String> fetchAssetText(GithubAsset asset) {
    return fetchText(Uri.parse(asset.url));
  }
}

/// One release: the tag that names its version and the assets it ships.
class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.assets,
    this.prerelease = false,
  });

  /// Version string for this feed (`2026.08.19`, `20241021`, …).
  final String tag;
  final List<GithubAsset> assets;
  final bool prerelease;
}

/// One downloadable file on a release.
class GithubAsset {
  const GithubAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;

  /// Size in bytes as the API reports it — the download's expected size
  /// (updater.md §3 · "Verify … file sizes").
  final int size;
}
