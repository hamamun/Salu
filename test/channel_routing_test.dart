import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/m3u/channel_source.dart';

/// M-3 / M-4b unit cover (playlist_imp.md §10.12): what counts as a
/// channel directory and what such a source is called in a toast.
/// (A failed channel only toasts — there is no auto-advance to cover.)
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
}
