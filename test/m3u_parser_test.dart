import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/m3u/channel_list_loader.dart';
import 'package:salu/core/m3u/channel_mapper.dart';
import 'package:salu/core/m3u/m3u_aliases.dart';
import 'package:salu/core/m3u/m3u_parser.dart';
import 'package:salu/core/queue_item.dart';

List<M3uEntry> parseAll(String text, {int chunk = 0}) {
  final M3uDirectoryParser p = M3uDirectoryParser();
  final List<M3uEntry> out = <M3uEntry>[];
  if (chunk <= 0) {
    out.addAll(p.feed(text));
  } else {
    for (int i = 0; i < text.length; i += chunk) {
      out.addAll(p.feed(
          text.substring(i, i + chunk > text.length ? text.length : i + chunk)));
    }
  }
  out.addAll(p.finish());
  return out;
}

List<QueueItem> mapAll(String text, {Uri? base}) {
  final ChannelMapper m = ChannelMapper(base: base);
  return parseAll(text).map(m.map).whereType<QueueItem>().toList();
}

Stream<List<int>> bytesOf(String text, {int chunk = 7}) async* {
  final List<int> b = utf8.encode(text);
  for (int i = 0; i < b.length; i += chunk) {
    yield b.sublist(i, i + chunk > b.length ? b.length : i + chunk);
  }
}

void main() {
  group('M3uDirectoryParser — attributes and titles', () {
    test('quoted, single-quoted and unquoted attributes', () {
      final List<M3uEntry> e = parseAll('''
#EXTM3U
#EXTINF:-1 tvg-id="bbc.uk" tvg-name='BBC One' group-title=News tvg-logo="http://x/l.png",BBC One HD
http://h/1.ts
''');
      expect(e, hasLength(1));
      expect(e[0]['tvg-id'], 'bbc.uk');
      expect(e[0]['tvg-name'], 'BBC One');
      expect(e[0]['group-title'], 'News');
      expect(e[0]['tvg-logo'], 'http://x/l.png');
      expect(e[0].title, 'BBC One HD');
      expect(e[0].url, 'http://h/1.ts');
    });

    test('keys are case-insensitive, values keep their case', () {
      final List<M3uEntry> e =
          parseAll('#EXTINF:-1 TVG-ID="A" Group-Title="Sport",X\nhttp://h\n');
      expect(e[0]['tvg-id'], 'A');
      expect(e[0]['group-title'], 'Sport');
    });

    test('title is everything after the first comma outside quotes', () {
      final List<M3uEntry> e = parseAll(
          '#EXTINF:-1 group-title="UK, News" tvg-name="A, B",Sky News, Live & Uncut\nhttp://h\n');
      expect(e[0]['group-title'], 'UK, News');
      expect(e[0]['tvg-name'], 'A, B');
      expect(e[0].title, 'Sky News, Live & Uncut');
    });

    test('blank and empty attributes arrive as empty strings here', () {
      final List<M3uEntry> e =
          parseAll('#EXTINF:-1 tvg-id="" group-title=" " tvg-logo=,Name\nhttp://h\n');
      expect(e[0]['tvg-id'], '');
      expect(e[0]['group-title'], ' ');
      expect(e[0]['tvg-logo'], '');
      expect(e[0].title, 'Name');
    });

    test('no attributes, plain duration and title', () {
      final List<M3uEntry> e = parseAll('#EXTINF:123,Some Track\nfile.mp3\n');
      expect(e[0].attributes, isEmpty);
      expect(e[0].title, 'Some Track');
      expect(e[0].url, 'file.mp3');
    });

    test('no comma at all → no title, attributes still parsed', () {
      final List<M3uEntry> e = parseAll('#EXTINF:-1 tvg-id="a"\nhttp://h\n');
      expect(e[0].title, isNull);
      expect(e[0]['tvg-id'], 'a');
    });

    test('stray bare tokens between attributes are skipped', () {
      final List<M3uEntry> e =
          parseAll('#EXTINF:-1 junk tvg-id="a" more group-title="G",T\nhttp://h\n');
      expect(e[0]['tvg-id'], 'a');
      expect(e[0]['group-title'], 'G');
      expect(e[0].title, 'T');
    });

    test('an apostrophe inside an unquoted value does not open a quote', () {
      final List<M3uEntry> e =
          parseAll("#EXTINF:-1 tvg-name=Bob's group-title=\"Kids\",Bob's Burgers\nhttp://h\n");
      expect(e[0]['tvg-name'], "Bob's");
      expect(e[0]['group-title'], 'Kids');
      expect(e[0].title, "Bob's Burgers");
    });

    test('unterminated quote takes the rest of the attribute text', () {
      final List<M3uEntry> e = parseAll('#EXTINF:-1 tvg-id="abc,T\nhttp://h\n');
      expect(e[0]['tvg-id'], 'abc,T');
      expect(e[0].title, isNull);
      expect(e[0].url, 'http://h');
    });
  });

  group('M3uDirectoryParser — line state', () {
    test('BOM before a headerless first #EXTINF is stripped', () {
      final List<M3uEntry> e =
          parseAll('\uFEFF#EXTINF:-1,First\nhttp://h/1\n#EXTINF:-1,Second\nhttp://h/2\n');
      expect(e.map((M3uEntry x) => x.title), <String>['First', 'Second']);
    });

    test('CRLF line endings', () {
      final List<M3uEntry> e =
          parseAll('#EXTM3U\r\n#EXTINF:-1 tvg-id="a",A\r\nhttp://h/a\r\n#EXTINF:-1,B\r\nhttp://h/b\r\n');
      expect(e, hasLength(2));
      expect(e[0]['tvg-id'], 'a');
      expect(e[0].url, 'http://h/a');
      expect(e[1].title, 'B');
    });

    test('missing #EXTM3U header and blank lines are tolerated', () {
      final List<M3uEntry> e = parseAll('\n\n#EXTINF:-1,A\n\n\nhttp://h/a\n\n');
      expect(e, hasLength(1));
      expect(e[0].title, 'A');
    });

    test('junk # lines between #EXTINF and URL do not mis-pair', () {
      final List<M3uEntry> e = parseAll('''
#EXTINF:-1,A
#EXTVLCOPT:http-user-agent=X
#KODIPROP:inputstream=Y
http://h/a
#EXTINF:-1,B
http://h/b
''');
      expect(e.map((M3uEntry x) => '${x.title}=${x.url}'),
          <String>['A=http://h/a', 'B=http://h/b']);
    });

    test('an #EXTINF with no URL is dropped, never fused', () {
      final List<M3uEntry> e = parseAll('''
#EXTINF:-1 tvg-id="lost",Lost
#EXTINF:-1 tvg-id="kept",Kept
http://h/kept
#EXTINF:-1,Trailing without url
''');
      expect(e, hasLength(1));
      expect(e[0]['tvg-id'], 'kept');
      expect(e[0].title, 'Kept');
    });

    test('a URL with no #EXTINF is still an entry', () {
      final List<M3uEntry> e = parseAll('#EXTM3U\nhttp://h/bare\n');
      expect(e, hasLength(1));
      expect(e[0].title, isNull);
      expect(e[0].attributes, isEmpty);
    });

    test('#EXTGRP before or after #EXTINF binds to the next URL only', () {
      final List<M3uEntry> e = parseAll('''
#EXTGRP:Before
#EXTINF:-1,A
http://h/a
#EXTINF:-1,B
#EXTGRP:After
http://h/b
#EXTINF:-1,C
http://h/c
''');
      expect(e[0].extgrp, 'Before');
      expect(e[1].extgrp, 'After');
      expect(e[2].extgrp, isNull);
    });

    test('final line without a trailing newline is flushed by finish()', () {
      final List<M3uEntry> e = parseAll('#EXTINF:-1,A\nhttp://h/a');
      expect(e, hasLength(1));
      expect(e[0].url, 'http://h/a');
    });

    test('chunk boundaries anywhere give identical results', () {
      const String text =
          '\uFEFF#EXTM3U\r\n#EXTINF:-1 tvg-id="x" group-title="G, H",Name, With Comma\r\n#EXTGRP:Z\r\nhttp://h/1\r\n#EXTINF:-1,Two\r\nhttp://h/2';
      final List<M3uEntry> whole = parseAll(text);
      for (final int chunk in <int>[1, 2, 3, 5, 8, 13, 64]) {
        final List<M3uEntry> parts = parseAll(text, chunk: chunk);
        expect(parts.length, whole.length, reason: 'chunk $chunk');
        for (int i = 0; i < whole.length; i++) {
          expect(parts[i].url, whole[i].url, reason: 'chunk $chunk');
          expect(parts[i].title, whole[i].title, reason: 'chunk $chunk');
          expect(parts[i].extgrp, whole[i].extgrp, reason: 'chunk $chunk');
          expect(parts[i].attributes, whole[i].attributes,
              reason: 'chunk $chunk');
        }
      }
    });
  });

  group('M3uDirectoryParser — HLS vs directory', () {
    test('a media manifest is detected before any entry', () {
      final M3uDirectoryParser p = M3uDirectoryParser();
      final List<M3uEntry> out = p.feed(
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXTINF:6.0,\nseg1.ts\n');
      out.addAll(p.finish());
      expect(p.isHls, isTrue);
      expect(out, isEmpty);
    });

    test('a master manifest is detected', () {
      final M3uDirectoryParser p = M3uDirectoryParser();
      p.feed('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\nlow/index.m3u8\n');
      expect(p.isHls, isTrue);
    });

    test('a directory with stray #EXT-X lines after entries stays a directory',
        () {
      final M3uDirectoryParser p = M3uDirectoryParser();
      final List<M3uEntry> out = p.feed(
          '#EXTM3U\n#EXTINF:-1,A\nhttp://h/a\n#EXT-X-SOMETHING\n#EXTINF:-1,B\nhttp://h/b\n');
      out.addAll(p.finish());
      expect(p.isHls, isFalse);
      expect(out, hasLength(2));
    });

    test('#EXT-X between a pending #EXTINF and its URL is not HLS', () {
      final M3uDirectoryParser p = M3uDirectoryParser();
      final List<M3uEntry> out =
          p.feed('#EXTINF:-1,A\n#EXT-X-DISCONTINUITY\nhttp://h/a\n');
      expect(p.isHls, isFalse);
      expect(out, hasLength(1));
    });
  });

  group('ChannelMapper — point 2 / point 5 boundary rules', () {
    test('blank attributes become null; label falls back id-first', () {
      final List<QueueItem> c = mapAll('''
#EXTINF:-1 tvg-id="" tvg-name="" group-title="" tvg-logo="",
http://h/1
#EXTINF:-1 tvg-id="id.only" tvg-name="" group-title=" ",
http://h/2
#EXTINF:-1 tvg-id="id2" tvg-name="Named",
http://h/3
#EXTINF:-1 tvg-id="id3" tvg-name="Named3",Title Wins
http://h/4
http://h/5
''');
      expect(c[0].name, 'Unknown');
      expect(c[0].tvgId, isNull);
      expect(c[0].tvgName, isNull);
      expect(c[0].group, isNull);
      expect(c[0].logoUrl, isNull);
      expect(c[1].name, 'id.only');
      expect(c[2].name, 'Named');
      expect(c[3].name, 'Title Wins');
      expect(c[4].name, 'Unknown');
      expect(c[4].isChannel, isTrue);
      expect(c.every((QueueItem i) => i.isChannel), isTrue);
    });

    test('group-title wins; blank/absent falls back to #EXTGRP', () {
      final List<QueueItem> c = mapAll('''
#EXTGRP:Fallback
#EXTINF:-1 group-title="Explicit",A
http://h/a
#EXTINF:-1 group-title="",B
#EXTGRP:FromGrp
http://h/b
#EXTGRP:   
#EXTINF:-1 group-title="  ",C
http://h/c
#EXTINF:-1,D
http://h/d
''');
      expect(c[0].group, 'Explicit');
      expect(c[1].group, 'FromGrp');
      expect(c[2].group, isNull);
      expect(c[3].group, isNull);
    });

    test('identity chain and search keys', () {
      final List<QueueItem> c = mapAll('''
#EXTINF:-1 tvg-id="bbc.uk" tvg-name="BBC" group-title="UK | News",BBC One HD
http://user:pass@h/live/1234.ts
''');
      expect(c[0].channelKey, 'bbc.uk');
      // The `UK |` part became the channel's country (§10.2a rev. 2026-09-09),
      // so the category — and the search key built from it — reads `News`.
      expect(c[0].group, 'News');
      expect(c[0].country, 'United Kingdom');
      expect(c[0].searchKey, 'bbc one hd news');
      // The URL never leaks into the label or the search text (§10.10e).
      expect(c[0].label, 'BBC One HD');
      expect(c[0].searchText.contains('pass'), isFalse);
      expect(c[0].searchText.contains('1234'), isFalse);
    });

    test('language / country aliases normalise, a compound tag takes its '
        'primary value', () {
      final List<QueueItem> c = mapAll('''
#EXTINF:-1 tvg-language="en" tvg-country="UK",A
http://h/a
#EXTINF:-1 tvg-language="English" tvg-country="gb",B
http://h/b
#EXTINF:-1 tvg-language="eng" tvg-country="United Kingdom",C
http://h/c
#EXTINF:-1 tvg-language="English;Spanish" tvg-country="US;CA",D
http://h/d
#EXTINF:-1 tvg-language="Klingon" tvg-country="Atlantis",E
http://h/e
#EXTINF:-1 tvg-language="bn" tvg-country="BD",F
http://h/f
''');
      expect(c.take(3).map((QueueItem i) => i.language).toSet(), <String>{'English'});
      expect(c.take(3).map((QueueItem i) => i.country).toSet(),
          <String>{'United Kingdom'});
      // One channel sits in one group, so a multi-value tag groups by its
      // first value instead of fragmenting into `US;CA` (§10.2a rev. M8).
      expect(c[3].language, 'English');
      expect(c[3].country, 'United States');
      expect(c[4].language, 'Klingon');
      expect(c[4].country, 'Atlantis');
      expect(c[5].language, 'Bangla');
      expect(c[5].country, 'Bangladesh');
    });

    test('alias tables directly', () {
      expect(normaliseCountry(' usa '), 'United States');
      expect(normaliseCountry('Deutschland'), 'Germany');
      expect(normaliseCountry(''), isNull);
      expect(normaliseCountry(null), isNull);
      expect(normaliseLanguage('JA'), 'Japanese');
      expect(normaliseLanguage('français'), 'French');
      expect(normaliseLanguage('  '), isNull);
    });

    test('group / language / country strings are interned per load', () {
      final StringBuffer b = StringBuffer('#EXTM3U\n');
      for (int i = 0; i < 300; i++) {
        b.writeln(
            '#EXTINF:-1 tvg-language="en" tvg-country="uk" group-title="Group ${i % 3}",Ch $i');
        b.writeln('http://h/$i');
      }
      final ChannelMapper m = ChannelMapper();
      final List<QueueItem> c =
          parseAll(b.toString()).map(m.map).whereType<QueueItem>().toList();
      expect(c, hasLength(300));
      expect(m.internedCount, 5); // 3 groups + English + United Kingdom
      expect(identical(c[0].group, c[3].group), isTrue);
      expect(identical(c[0].language, c[299].language), isTrue);
      expect(identical(c[0].country, c[299].country), isTrue);
    });

    test('relative stream and logo URLs resolve against an http base', () {
      final List<QueueItem> c = mapAll('''
#EXTINF:-1 tvg-logo="logos/a.png",A
live/a.m3u8
#EXTINF:-1 tvg-logo="/img/b.png",B
//cdn.example/b.ts
#EXTINF:-1 tvg-logo="https://img.example/c.png",C
https://other.example/c.ts
''', base: Uri.parse('https://provider.example/lists/main.m3u?u=1&p=2'));
      expect(c[0].url, 'https://provider.example/lists/live/a.m3u8');
      expect(c[0].logoUrl, 'https://provider.example/lists/logos/a.png');
      expect(c[1].url, 'https://cdn.example/b.ts');
      expect(c[1].logoUrl, 'https://provider.example/img/b.png');
      expect(c[2].url, 'https://other.example/c.ts');
      expect(c[2].logoUrl, 'https://img.example/c.png');
    });

    test('relative paths in a local playlist resolve to file paths', () {
      final List<QueueItem> c = mapAll('''
#EXTINF:-1,A
media/a.mkv
#EXTINF:-1,B
C:\\Other\\b.mkv
#EXTINF:-1,C
http://h/c.ts
''', base: Uri.file(r'C:\Lists\tv.m3u', windows: true));
      expect(c[0].url, r'C:\Lists\media\a.mkv');
      expect(c[1].url, r'C:\Other\b.mkv');
      expect(c[2].url, 'http://h/c.ts');
    });

    test('no base leaves URLs exactly as written', () {
      final List<QueueItem> c = mapAll('#EXTINF:-1,A\nlive/a.m3u8\n');
      expect(c[0].url, 'live/a.m3u8');
    });
  });

  group('ChannelListLoader — pipeline', () {
    test('progressive batches: first ~200 rows, then the rest, total right',
        () async {
      final StringBuffer b = StringBuffer('#EXTM3U\n');
      for (int i = 0; i < 1000; i++) {
        b.writeln('#EXTINF:-1 group-title="G",Ch $i');
        b.writeln('http://h/$i');
      }
      final List<List<QueueItem>> batches = <List<QueueItem>>[];
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf(b.toString(), chunk: 512),
        onBatch: batches.add,
      );
      expect(end, isA<ChannelListDone>());
      expect((end as ChannelListDone).total, 1000);
      expect(batches.length, greaterThanOrEqualTo(2));
      expect(batches.first.length, ChannelListLoader.firstBatchRows);
      final List<QueueItem> all =
          batches.expand((List<QueueItem> x) => x).toList();
      expect(all, hasLength(1000));
      expect(all.first.name, 'Ch 0');
      expect(all.last.name, 'Ch 999');
      expect(() => batches.first.add(all.first), throwsUnsupportedError);
    });

    test('byte ceiling aborts the load as tooLarge', () async {
      final StringBuffer b = StringBuffer('#EXTM3U\n');
      for (int i = 0; i < 500; i++) {
        b.writeln('#EXTINF:-1,Ch $i');
        b.writeln('http://h/$i');
      }
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf(b.toString(), chunk: 256),
        byteCeiling: 2048,
        onBatch: (_) {},
      );
      expect(end, isA<ChannelListFailed>());
      expect((end as ChannelListFailed).reason, ChannelListFailure.tooLarge);
    });

    test('an HLS manifest URL is reported, no channels', () async {
      final List<List<QueueItem>> batches = <List<QueueItem>>[];
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf('#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:6.0,\nseg1.ts\n'),
        onBatch: batches.add,
      );
      expect(end, isA<ChannelListHls>());
      expect(batches, isEmpty);
    });

    test('a non-playlist body is reported as such (URL mode)', () async {
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf('<html><body>login</body></html>\n'),
        onBatch: (_) {},
      );
      expect(end, isA<ChannelListNotPlaylist>());
    });

    test('a binary stream body with no newline is rejected quickly', () async {
      final String junk = String.fromCharCodes(List<int>.filled(5000, 0x47));
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf(junk, chunk: 1024),
        onBatch: (_) {},
      );
      expect(end, isA<ChannelListNotPlaylist>());
    });

    test('a file source is lenient: headerless first line still parses',
        () async {
      final List<List<QueueItem>> batches = <List<QueueItem>>[];
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf('# my list\n#EXTINF:-1,A\nhttp://h/a\n'),
        lenient: true,
        onBatch: batches.add,
      );
      expect(end, isA<ChannelListDone>());
      expect(batches.single.single.name, 'A');
    });

    test('BOM + CRLF + headerless through the whole pipeline', () async {
      final List<List<QueueItem>> batches = <List<QueueItem>>[];
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        bytesOf('\uFEFF#EXTINF:-1 tvg-id="a",A\r\nhttp://h/a\r\n', chunk: 3),
        onBatch: batches.add,
      );
      expect(end, isA<ChannelListDone>());
      expect(batches.single.single.tvgId, 'a');
    });

    test('a stalled source times out as a network failure', () async {
      final StreamController<List<int>> c = StreamController<List<int>>();
      c.add(utf8.encode('#EXTM3U\n#EXTINF:-1,A\n'));
      final ChannelListEvent end = await ChannelListLoader.parseForTest(
        c.stream,
        idle: const Duration(milliseconds: 50),
        onBatch: (_) {},
      );
      expect(end, isA<ChannelListFailed>());
      expect((end as ChannelListFailed).reason, ChannelListFailure.network);
      await c.close();
    });

    test('sniffHead', () {
      expect(ChannelListLoader.sniffHead('#EXTM3U\n'), HeadSniff.playlist);
      expect(ChannelListLoader.sniffHead('\uFEFF\r\n#extinf:-1,A\n'),
          HeadSniff.playlist);
      expect(ChannelListLoader.sniffHead('#EXTM3'), HeadSniff.undecided);
      expect(ChannelListLoader.sniffHead('#EXTM3U'), HeadSniff.undecided);
      expect(ChannelListLoader.sniffHead('#EXTM3U', atEnd: true),
          HeadSniff.playlist);
      expect(ChannelListLoader.sniffHead('<html>\n'), HeadSniff.notPlaylist);
      expect(ChannelListLoader.sniffHead('', atEnd: true), HeadSniff.notPlaylist);
      expect(ChannelListLoader.sniffHead('\n\n', atEnd: true),
          HeadSniff.notPlaylist);
    });
  });

  group('ChannelListLoader — isolate worker', () {
    test('cancellation stops the stream without a terminal event', () async {
      // A file that does not exist fails fast on the worker; cancelling
      // before that must simply close the stream.
      final Stream<ChannelListEvent> s = ChannelListLoader.open(
        '/definitely/not/here.m3u',
        isFile: true,
      );
      final StreamSubscription<ChannelListEvent> sub =
          s.listen((_) => fail('no events after cancel'));
      await sub.cancel();
    });

    test('a missing file ends in a failed load', () async {
      final List<ChannelListEvent> events = await ChannelListLoader.open(
        '/definitely/not/here.m3u',
        isFile: true,
      ).toList();
      expect(events, hasLength(1));
      expect(events.single, isA<ChannelListFailed>());
    });

    test('a real local .m3u file streams channels through the worker (M55)',
        () async {
      // M55: a local playlist takes the SAME route as an m3u URL — only
      // the fetch differs. This drives the real isolate over a real file.
      final Directory dir =
          await Directory.systemTemp.createTemp('salu_m3u_test');
      addTearDown(() => dir.delete(recursive: true));
      final File file = File('${dir.path}/tv.m3u');
      await file.writeAsString('''
#EXTM3U
#EXTINF:-1 tvg-id="one" tvg-logo="logos/one.png" group-title="News",One
http://h/one.ts
#EXTINF:-1 group-title="News",Two
http://h/two.ts
#EXTINF:-1,Three
media/three.mkv
''');

      final List<QueueItem> channels = <QueueItem>[];
      ChannelListEvent? terminal;
      await for (final ChannelListEvent e
          in ChannelListLoader.open(file.path, isFile: true)) {
        if (e is ChannelBatch) {
          channels.addAll(e.items);
        } else {
          terminal = e;
        }
      }

      expect(terminal, isA<ChannelListDone>());
      expect((terminal! as ChannelListDone).total, 3);
      expect(channels.map((QueueItem c) => c.name).toList(),
          <String>['One', 'Two', 'Three']);
      expect(channels[0].tvgId, 'one');
      expect(channels[0].group, 'News');
      // Relative entries resolve against the playlist's own folder.
      // The mapper spells a resolved file path Windows-style, so
      // normalise before comparing (this suite runs on the CI host).
      expect(channels[2].url.replaceAll('\\', '/'),
          endsWith('/media/three.mkv'));
      // Every parsed channel carries a label, so this IS a channel list.
      expect(channels.every((QueueItem c) => c.name != null), isTrue);
    });
  });
}
