import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/lyric_parser.dart';
import 'package:salu/core/media_utils.dart';

void main() {
  group('MediaUtils — lyrics are not subtitles (lrc.md L7 / L25)', () {
    test('.lrc is lyrics, never a subtitle, never media', () {
      expect(MediaUtils.isLyrics(r'C:\Music\song.lrc'), isTrue);
      expect(MediaUtils.isLyrics(r'C:\Music\song.LRC'), isTrue);
      expect(MediaUtils.isSubtitle(r'C:\Music\song.lrc'), isFalse);
      expect(MediaUtils.isMedia(r'C:\Music\song.lrc'), isFalse);
      expect(MediaUtils.isLyrics(r'C:\Music\song.lyr'), isFalse);
      expect(MediaUtils.isLyrics(r'C:\Music\song.srt'), isFalse);
    });
  });

  group('LrcParser — real-world quirks (lrc.md L9 / L24)', () {
    test('a simple timed line', () {
      final LyricDocument doc = LrcParser.parse('[00:12.50]Hello world');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.first.text, 'Hello world');
      expect(doc.lines.first.timestamp, const Duration(seconds: 12, milliseconds: 500));
    });

    test('multiple timestamps on one line duplicate the text', () {
      final LyricDocument doc =
          LrcParser.parse('[00:10.00][00:20.00]the refrain');
      expect(doc.lines, hasLength(2));
      expect(doc.lines[0].timestamp, const Duration(seconds: 10));
      expect(doc.lines[1].timestamp, const Duration(seconds: 20));
      expect(doc.lines[0].text, 'the refrain');
      expect(doc.lines[1].text, 'the refrain');
    });

    test('enhanced LRC word timing is stripped, the line is kept', () {
      final LyricDocument doc = LrcParser.parse(
        '[00:10.00]Hello <00:10.50>world <00:11.00>again',
      );
      expect(doc.lines, hasLength(1));
      expect(doc.lines.first.text, 'Hello world again');
    });

    test('headers are read and are not timed lines', () {
      final LyricDocument doc = LrcParser.parse('''
[ti:Song Title]
[ar:The Artist]
[al:The Album]
[by:Someone]
[00:01.00]first
''');
      expect(doc.title, 'Song Title');
      expect(doc.artist, 'The Artist');
      expect(doc.album, 'The Album');
      expect(doc.by, 'Someone');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.first.text, 'first');
    });

    test('[offset:] is APPLIED to every timestamp', () {
      final LyricDocument doc = LrcParser.parse('''
[offset:+500]
[00:10.00]later
''');
      expect(doc.offset, const Duration(milliseconds: 500));
      expect(doc.lines.first.timestamp, const Duration(seconds: 10, milliseconds: 500));
    });

    test('a negative offset shifts timestamps earlier', () {
      final LyricDocument doc = LrcParser.parse('''
[offset:-200]
[00:10.00]earlier
''');
      expect(doc.lines.first.timestamp, const Duration(seconds: 9, milliseconds: 800));
    });

    test('blank lines and untimed lines are ignored', () {
      final LyricDocument doc = LrcParser.parse('''

this is just a comment
[00:01.00]kept

[re:SALU]
''');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.first.text, 'kept');
    });

    test('centiseconds and milliseconds both land on the same grid', () {
      expect(
        LrcParser.parse('[00:01.5]a').lines.first.timestamp,
        const Duration(seconds: 1, milliseconds: 500),
      );
      expect(
        LrcParser.parse('[00:01.50]a').lines.first.timestamp,
        const Duration(seconds: 1, milliseconds: 500),
      );
      expect(
        LrcParser.parse('[00:01.500]a').lines.first.timestamp,
        const Duration(seconds: 1, milliseconds: 500),
      );
    });

    test('a UTF-8 BOM is stripped', () {
      final LyricDocument doc = LrcParser.parse('\uFEFF[00:01.00]bom');
      expect(doc.lines, hasLength(1));
      expect(doc.lines.first.text, 'bom');
    });

    test('an empty / header-only file yields no lines', () {
      expect(LrcParser.parse('[ti:Nothing]').isEmpty, isTrue);
      expect(LrcParser.parse('').isEmpty, isTrue);
    });
  });

  group('LrcParser.indexAt — the subDelay bridge (lrc.md L12 / L20)', () {
    final List<LyricLine> lines = <LyricLine>[
      const LyricLine(timestamp: Duration(seconds: 10), text: 'a'),
      const LyricLine(timestamp: Duration(seconds: 20), text: 'b'),
      const LyricLine(timestamp: Duration(seconds: 30), text: 'c'),
    ];

    test('before the first line there is no current line', () {
      expect(LrcParser.indexAt(lines, const Duration(seconds: 3)), -1);
    });

    test('a timestamp lands on its line until the next one', () {
      expect(LrcParser.indexAt(lines, const Duration(seconds: 10)), 0);
      expect(LrcParser.indexAt(lines, const Duration(seconds: 19)), 0);
      expect(LrcParser.indexAt(lines, const Duration(seconds: 20)), 1);
      expect(LrcParser.indexAt(lines, const Duration(seconds: 40)), 2);
    });

    test('positive subDelay makes the text run LATER', () {
      // At 10.0s with +0.5s delay the 10s line is not yet current.
      expect(
        LrcParser.indexAt(
          lines,
          const Duration(seconds: 10),
          subDelaySeconds: 0.5,
        ),
        -1,
      );
      expect(
        LrcParser.indexAt(
          lines,
          const Duration(milliseconds: 10500),
          subDelaySeconds: 0.5,
        ),
        0,
      );
    });

    test('negative subDelay makes the text run EARLIER', () {
      expect(
        LrcParser.indexAt(
          lines,
          const Duration(milliseconds: 9500),
          subDelaySeconds: -0.5,
        ),
        0,
      );
    });
  });
}
