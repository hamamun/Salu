import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/m3u/channel_skip_policy.dart';
import 'package:salu/core/m3u/channel_source.dart';

/// M-3 / M-4b unit cover (playlist_imp.md §10.12): what counts as a
/// channel directory, what such a source is called in a toast, and the
/// failure-skip rule with its cascade guard.
void main() {
  group('ChannelSource — what SALU parses itself (M-3 · M55)', () {
    test('local .m3u / .m3u8 files are directories, media files are not', () {
      expect(ChannelSource.looksLikeDirectory(r'C:\Lists\tv.m3u'), isTrue);
      expect(ChannelSource.looksLikeDirectory(r'C:\Lists\tv.M3U8'), isTrue);
      expect(ChannelSource.looksLikeDirectory('/home/u/tv.m3u'), isTrue);
      expect(ChannelSource.looksLikeDirectory(r'C:\Videos\a.mkv'), isFalse);
      expect(ChannelSource.looksLikeDirectory(''), isFalse);
      expect(ChannelSource.looksLikeDirectory('   '), isFalse);
    });

    test('a file: URI is treated as the local file it names', () {
      expect(ChannelSource.isRemote('file:///C:/Lists/tv.m3u'), isFalse);
      expect(
          ChannelSource.looksLikeDirectory('file:///C:/Lists/tv.m3u'), isTrue);
      expect(ChannelSource.localPath('file:///C:/Lists/tv.m3u'),
          'C:/Lists/tv.m3u');
    });

    test('http(s) URLs qualify by path or by an m3u-shaped query', () {
      expect(
        ChannelSource.looksLikeDirectory('https://h/lists/all.m3u'),
        isTrue,
      );
      expect(
        ChannelSource.looksLikeDirectory('http://h:8080/x/y.M3U8?a=1'),
        isTrue,
      );
      expect(
        ChannelSource.looksLikeDirectory(
            'http://h/get.php?username=u&password=p&type=m3u_plus'),
        isTrue,
      );
      expect(
        ChannelSource.looksLikeDirectory('http://h/api?output=m3u8'),
        isTrue,
      );
    });

    test('plain streams and non-fetchable schemes stay with the engine', () {
      expect(ChannelSource.looksLikeDirectory('http://h/live/1234.ts'),
          isFalse);
      expect(ChannelSource.looksLikeDirectory('https://h/movie.mp4'), isFalse);
      // A channel's own HLS manifest reached by a bare stream URL is not
      // a directory by spelling; the loader's sniff is the second net.
      expect(ChannelSource.looksLikeDirectory('rtsp://h/stream'), isFalse);
      expect(ChannelSource.looksLikeDirectory('udp://@239.0.0.1:1234'),
          isFalse);
      // …but an `.m3u8` served over rtsp is still not fetchable by us.
      expect(ChannelSource.looksLikeDirectory('rtsp://h/x.m3u8'), isFalse);
    });

    test('a toast never gets a URL — remote sources report their host',
        () {
      // §10.10e: path and query carry credentials.
      expect(
        ChannelSource.displayName(
            'http://provider.example:8080/get.php?username=bob&password=hunter2&type=m3u'),
        'provider.example',
      );
      expect(
        ChannelSource.displayName('https://cdn.example/lists/all.m3u'),
        'cdn.example',
      );
      expect(ChannelSource.displayName(r'C:\Lists\My TV.m3u'), 'My TV');
      expect(ChannelSource.displayName(''), 'Playlist');
    });

    test('a displayed name never contains credentials or the path', () {
      const String url =
          'http://user:pass@provider.example/live/user/pass/all.m3u8';
      final String shown = ChannelSource.displayName(url);
      expect(shown, 'provider.example');
      expect(shown.contains('pass'), isFalse);
      expect(shown.contains('/'), isFalse);
    });
  });

  group('ChannelSkipPolicy — the failure skip (§10.8 · §10.8a-ii)', () {
    test('a failed channel skips to the next one', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      expect(p.onFailure(index: 0, count: 10), ChannelSkipAction.skip);
      expect(p.strikes, 1);
    });

    test('three consecutive failures stop the cascade', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      expect(p.onFailure(index: 0, count: 50000), ChannelSkipAction.skip);
      p.settle();
      expect(p.onFailure(index: 1, count: 50000), ChannelSkipAction.skip);
      p.settle();
      expect(p.onFailure(index: 2, count: 50000), ChannelSkipAction.stop);
      expect(p.stopped, isTrue);
      // And it stays stopped — no stampede past the third.
      p.settle();
      expect(p.onFailure(index: 3, count: 50000), ChannelSkipAction.stop);
    });

    test('successful playback resets the counter', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      p.onFailure(index: 0, count: 10);
      p.settle();
      p.onFailure(index: 1, count: 10);
      p.settle();
      expect(p.strikes, 2);
      p.recordSuccess();
      expect(p.strikes, 0);
      expect(p.onFailure(index: 2, count: 10), ChannelSkipAction.skip);
    });

    test('a manual pick resets the counter, so skipping works again', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      for (int i = 0; i < 3; i++) {
        p.onFailure(index: i, count: 10);
        p.settle();
      }
      expect(p.stopped, isTrue);
      p.recordManualPick();
      expect(p.strikes, 0);
      expect(p.onFailure(index: 7, count: 10), ChannelSkipAction.skip);
    });

    test('the last channel failing stops — it never wraps to index 0', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      expect(p.onFailure(index: 9, count: 10), ChannelSkipAction.stop);
      expect(p.strikes, 1); // it WAS a failure, it just has nowhere to go
    });

    test('a burst of error lines for one dead channel fires one skip', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      expect(p.onFailure(index: 4, count: 10), ChannelSkipAction.skip);
      // More mpv lines for the same channel, and lines arriving while the
      // skip's own open is still in flight.
      expect(p.onFailure(index: 4, count: 10), ChannelSkipAction.ignore);
      expect(p.onFailure(index: 5, count: 10), ChannelSkipAction.ignore);
      expect(p.strikes, 1);
      p.settle();
      expect(p.onFailure(index: 5, count: 10), ChannelSkipAction.skip);
      expect(p.strikes, 2);
    });

    test('an out-of-range report is ignored', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      expect(p.onFailure(index: -1, count: 10), ChannelSkipAction.ignore);
      expect(p.onFailure(index: 10, count: 10), ChannelSkipAction.ignore);
      expect(p.onFailure(index: 0, count: 0), ChannelSkipAction.ignore);
      expect(p.strikes, 0);
    });

    test('reset forgets everything (a fresh list, a clear)', () {
      final ChannelSkipPolicy p = ChannelSkipPolicy();
      p.onFailure(index: 0, count: 10);
      p.reset();
      expect(p.strikes, 0);
      expect(p.stopped, isFalse);
      expect(p.onFailure(index: 0, count: 10), ChannelSkipAction.skip);
    });

    test('the strike limit is the locked 3', () {
      expect(ChannelSkipPolicy.strikeLimit, 3);
    });
  });
}
