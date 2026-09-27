import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/updater/github_updater_client.dart';

/// The GitHub half (updater.md §1): release parsing, the two asset picks
/// (x64-only for libmpv — the Architecture Guard of §9 — and exactly
/// `yt-dlp.exe` for the parser), and `SHA2-256SUMS` reading.

void main() {
  const String mpvReleaseJson = '''
  {
    "tag_name": "20250101",
    "prerelease": false,
    "assets": [
      {"name": "mpv-aarch64-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-aarch64.7z", "size": 11},
      {"name": "mpv-dev-aarch64-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-aarch64.7z", "size": 12},
      {"name": "mpv-dev-i686-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-i686.7z", "size": 13},
      {"name": "mpv-dev-x86_64-v3-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-x86_64-v3.7z", "size": 14},
      {"name": "mpv-dev-x86_64-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-x86_64.7z", "size": 15},
      {"name": "mpv-x86_64-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-x86_64.7z", "size": 16}
    ]
  }''';

  const String ytDlpReleaseJson = '''
  {
    "tag_name": "2026.08.19",
    "prerelease": false,
    "assets": [
      {"name": "SHA2-256SUMS",
       "browser_download_url": "https://gh.test/SHA2-256SUMS", "size": 100},
      {"name": "SHA2-512SUMS",
       "browser_download_url": "https://gh.test/SHA2-512SUMS", "size": 100},
      {"name": "yt-dlp",
       "browser_download_url": "https://gh.test/yt-dlp", "size": 1},
      {"name": "yt-dlp.exe",
       "browser_download_url": "https://gh.test/yt-dlp.exe", "size": 17840399},
      {"name": "yt-dlp_x86.exe",
       "browser_download_url": "https://gh.test/yt-dlp_x86.exe", "size": 1}
    ]
  }''';

  group('parseRelease', () {
    test('reads the tag and its assets', () {
      final GithubRelease? release =
          GitHubUpdaterClient.parseRelease(ytDlpReleaseJson);
      expect(release, isNotNull);
      expect(release!.tag, '2026.08.19');
      expect(release.assets, hasLength(5));
      expect(release.assets.first.name, 'SHA2-256SUMS');
      expect(release.assets.first.url, 'https://gh.test/SHA2-256SUMS');
    });

    test('tolerates missing pieces but refuses non-releases', () {
      expect(GitHubUpdaterClient.parseRelease('{"tag_name": "1"}')!.assets,
          isEmpty);
      expect(GitHubUpdaterClient.parseRelease('{"assets": []}'), isNull);
      expect(GitHubUpdaterClient.parseRelease('nonsense'), isNull);
      expect(GitHubUpdaterClient.parseRelease('[]'), isNull);
    });

    test('skips assets without a usable name or URL', () {
      final GithubRelease? release = GitHubUpdaterClient.parseRelease('''
      {
        "tag_name": "1",
        "assets": [
          {"name": "", "browser_download_url": "https://gh.test/x"},
          {"name": "keep.exe", "browser_download_url": ""},
          {"name": "keep.exe", "browser_download_url": "https://gh.test/keep"}
        ]
      }''');
      expect(release!.assets, hasLength(1));
      expect(release.assets.single.url, 'https://gh.test/keep');
    });
  });

  group('pickMpvAsset', () {
    test('takes the plain x64 dev archive and nothing else', () {
      final GithubRelease release =
          GitHubUpdaterClient.parseRelease(mpvReleaseJson)!;
      final GithubAsset? asset = GitHubUpdaterClient.pickMpvAsset(release);
      expect(asset, isNotNull);
      expect(asset!.name, 'mpv-dev-x86_64-20250101-git-aaaaaaa.7z');
      expect(asset.url, 'https://gh.test/mpv-dev-x86_64.7z');
    });

    test('never a 32-bit, ARM64, v3, or player-only archive', () {
      final GithubRelease release =
          GitHubUpdaterClient.parseRelease(mpvReleaseJson)!;
      final String? picked = GitHubUpdaterClient.pickMpvAsset(release)?.name;
      expect(picked, isNot(contains('i686')));
      expect(picked, isNot(contains('aarch64')));
      expect(picked, isNot(contains('v3')));
      expect(picked, startsWith('mpv-dev-'));
    });

    test('a release without a qualifying asset answers null', () {
      final GithubRelease release = GitHubUpdaterClient.parseRelease('''
      {"tag_name": "2", "assets": [
        {"name": "mpv-dev-i686-2-git-x.7z",
         "browser_download_url": "https://gh.test/a", "size": 1}
      ]}''')!;
      expect(GitHubUpdaterClient.pickMpvAsset(release), isNull);
    });
  });

  group('pickYtDlpAsset', () {
    test('takes exactly yt-dlp.exe — the x64 standalone', () {
      final GithubRelease release =
          GitHubUpdaterClient.parseRelease(ytDlpReleaseJson)!;
      final GithubAsset? asset = GitHubUpdaterClient.pickYtDlpAsset(release);
      expect(asset!.name, 'yt-dlp.exe');
      expect(asset.size, 17840399);
    });

    test('ignores the x86 sibling and the unix builds', () {
      final GithubRelease release = GitHubUpdaterClient.parseRelease('''
      {"tag_name": "1", "assets": [
        {"name": "yt-dlp_x86.exe",
         "browser_download_url": "https://gh.test/x86", "size": 1},
        {"name": "yt-dlp",
         "browser_download_url": "https://gh.test/u", "size": 1}
      ]}''')!;
      expect(GitHubUpdaterClient.pickYtDlpAsset(release), isNull);
    });
  });

  group('pickChecksumsAsset', () {
    test('finds SHA2-256SUMS among the signature siblings', () {
      final GithubRelease release =
          GitHubUpdaterClient.parseRelease(ytDlpReleaseJson)!;
      expect(GitHubUpdaterClient.pickChecksumsAsset(release)!.name,
          'SHA2-256SUMS');
    });
  });

  group('sha256For', () {
    String hex(String unit, int units) => List<String>.filled(units, unit).join();
    final String hashA = hex('ab', 32); // 64 chars
    final String hashB = hex('11', 32);
    final String hashC = hex('22', 32);
    final String sums = '$hashA *yt-dlp.exe\n$hashB  yt-dlp\n$hashC *yt-dlp_x86.exe';

    test('reads the binary-mode line (`*name`)', () {
      expect(GitHubUpdaterClient.sha256For(sums, 'yt-dlp.exe'), hashA);
    });

    test('reads text-mode lines and ignores other files', () {
      expect(GitHubUpdaterClient.sha256For(sums, 'yt-dlp'), hashB);
      expect(GitHubUpdaterClient.sha256For(sums, 'libmpv-2.dll'), isNull);
    });

    test('is case-insensitive on the digest, exact on the name', () {
      final String upper = '${hashA.toUpperCase()} *yt-dlp.exe';
      expect(GitHubUpdaterClient.sha256For(upper, 'yt-dlp.exe'), hashA);
      // A file that merely CONTAINS the name does not match.
      expect(GitHubUpdaterClient.sha256For(upper, 'yt-dlp'), isNull);
    });

    test('a line with no real digest yields no hash', () {
      expect(GitHubUpdaterClient.sha256For('zz *yt-dlp.exe', 'yt-dlp.exe'),
          isNull);
    });
  });

  group('fetchers', () {
    test('latestRelease and fetchAssetText hand the right URLs to the seam',
        () async {
      final List<Uri> asked = <Uri>[];
      final GitHubUpdaterClient client = GitHubUpdaterClient(
        fetchText: (Uri url) async {
          asked.add(url);
          return '{"tag_name": "1", "assets": []}';
        },
      );
      await client.latestRelease(GitHubUpdaterClient.ytDlpRepo);
      await client.fetchAssetText(const GithubAsset(
        name: 'SHA2-256SUMS',
        url: 'https://gh.test/SHA2-256SUMS',
        size: 1,
      ));
      expect(asked, <Uri>[
        Uri.parse('https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'),
        Uri.parse('https://gh.test/SHA2-256SUMS'),
      ]);
    });
  });
}
