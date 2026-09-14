import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/lyric_locator.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('salu_lrc_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String audio(String name) {
    final String path = p.join(dir.path, name);
    File(path).writeAsBytesSync(const <int>[]);
    return path;
  }

  void lrc(String name, [String body = '[00:01.00]line']) {
    File(p.join(dir.path, name)).writeAsStringSync(body);
  }

  group('LyricLocator — basename match (lrc.md L10 / L23)', () {
    test('exact song.lrc beats song.<lang>.lrc', () {
      final String mp3 = audio('song.mp3');
      lrc('song.en.lrc', '[00:01.00]en');
      lrc('song.lrc', '[00:01.00]exact');
      final String? found = LyricLocator.findSidecar(mp3);
      expect(found, isNotNull);
      expect(p.basename(found!), 'song.lrc');
    });

    test('without an exact match, song.<lang>.lrc is first in natural order',
        () {
      final String mp3 = audio('song.mp3');
      lrc('song.fr.lrc');
      lrc('song.en.lrc');
      final String? found = LyricLocator.findSidecar(mp3);
      expect(found, isNotNull);
      expect(p.basename(found!), 'song.en.lrc');
    });

    test('the match is case-insensitive', () {
      final String mp3 = audio('Song.mp3');
      lrc('Song.LRC');
      final String? found = LyricLocator.findSidecar(mp3);
      expect(found, isNotNull);
      expect(p.basename(found!).toLowerCase(), 'song.lrc');
    });

    test('a commentary-style name is not a match', () {
      final String mp3 = audio('song.mp3');
      lrc('song commentary.lrc');
      lrc('other.lrc');
      expect(LyricLocator.findSidecar(mp3), isNull);
    });

    test('no sidecar at all is a miss', () {
      final String mp3 = audio('song.mp3');
      expect(LyricLocator.findSidecar(mp3), isNull);
    });

    test('a remote URL is never probed', () {
      expect(
        LyricLocator.findSidecar('https://h/song.mp3'),
        isNull,
      );
    });

    test('load returns null for a header-only file', () {
      final String mp3 = audio('empty.mp3');
      lrc('empty.lrc', '[ti:Nothing]\n');
      expect(LyricLocator.load(mp3), isNull);
    });

    test('load parses a real sidecar', () {
      final String mp3 = audio('real.mp3');
      lrc('real.lrc', '[00:02.00]hello\n[00:04.00]world');
      final LyricDocument? doc = LyricLocator.load(mp3);
      expect(doc, isNotNull);
      expect(doc!.lines, hasLength(2));
      expect(doc.lines.first.text, 'hello');
    });
  });
}
