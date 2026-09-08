import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/queue_service.dart';

void main() {
  final QueueService q = QueueService.instance;

  setUp(() => q.clear());

  group('QueueItem', () {
    test('local rows carry the path only and label by file name', () {
      const QueueItem item = QueueItem.local('C:/Videos/Show.S01E01.mkv');
      expect(item.isChannel, isFalse);
      expect(item.label, 'Show.S01E01');
      expect(item.searchText, 'show.s01e01');
      expect(item.channelKey, isNull);
    });

    test('channel identity is id → tvg-name → name', () {
      expect(
        const QueueItem('u', name: 'A', tvgName: 'B', tvgId: 'C').channelKey,
        'C',
      );
      expect(const QueueItem('u', name: 'A', tvgName: 'B').channelKey, 'B');
      expect(const QueueItem('u', name: 'A').channelKey, 'A');
    });

    test('withUrl keeps the record when nothing changes', () {
      const QueueItem item = QueueItem('http://h/x', name: 'X');
      expect(identical(item.withUrl('http://h/x'), item), isTrue);
      expect(item.withUrl('http://h/y').name, 'X');
    });
  });

  group('QueueService (Phase A behaviour)', () {
    test('setQueue canonicalises and points at the start row', () {
      q.setQueue(<String>[r'C:\a\b.mkv', '/C:/a/c.mkv'], 1);
      expect(q.paths, <String>['C:/a/b.mkv', 'C:/a/c.mkv']);
      expect(q.index.value, 1);
      expect(q.isChannelList, isFalse);
      expect(q.current!.url, 'C:/a/c.mkv');
    });

    test('paths view is cached per published list', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv'], 0);
      final List<String> first = q.paths;
      expect(identical(first, q.paths), isTrue);
      q.append(<String>['C:/c.mkv']);
      expect(identical(first, q.paths), isFalse);
      expect(q.paths.length, 3);
    });

    test('items are unmodifiable', () {
      q.setQueue(<String>['C:/a.mkv'], 0);
      expect(() => q.items.value.add(const QueueItem.local('x')),
          throwsUnsupportedError);
    });

    test('insert before the current row shifts the pointer', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv'], 1);
      q.insert(0, const QueueItem.local('C:/z.mkv'));
      expect(q.paths, <String>['C:/z.mkv', 'C:/a.mkv', 'C:/b.mkv']);
      expect(q.index.value, 2);
    });

    test('removeAt keeps the pointer honest', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv', 'C:/c.mkv'], 1);
      expect(q.removeAt(0)!.url, 'C:/a.mkv');
      expect(q.index.value, 0);
      expect(q.removeAt(0)!.url, 'C:/b.mkv');
      expect(q.index.value, 0); // c slid into place
      expect(q.removeAt(0)!.url, 'C:/c.mkv');
      expect(q.index.value, -1);
      expect(q.removeAt(0), isNull);
    });

    test('move follows the same entry', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv', 'C:/c.mkv'], 2);
      expect(q.move(2, 0), isTrue);
      expect(q.paths, <String>['C:/c.mkv', 'C:/a.mkv', 'C:/b.mkv']);
      expect(q.index.value, 0);
      expect(q.move(5, 0), isFalse);
    });

    test('indexOfUrl and itemAt', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv'], 0);
      expect(q.indexOfUrl('C:/b.mkv'), 1);
      expect(q.indexOfUrl('C:/nope.mkv'), -1);
      expect(q.itemAt(1)!.url, 'C:/b.mkv');
      expect(q.itemAt(2), isNull);
      expect(q.itemAt(-1), isNull);
    });

    test('shuffle pass never leads with the item just heard', () {
      q.setQueue(<String>['C:/a.mkv', 'C:/b.mkv', 'C:/c.mkv'], 0);
      q.recordPlayed(0);
      final Set<int> seen = <int>{};
      for (int i = 0; i < 2; i++) {
        seen.add(q.takeNextShuffle()!);
      }
      expect(seen, <int>{1, 2});
      expect(q.takeNextShuffle(), isNull);
      expect(q.peekPreviousHeard, 1 + 2 - seen.last);
    });
  });

  group('QueueService (channel lists)', () {
    test('setItems keeps channel records and derives isChannelList', () {
      q.setItems(const <QueueItem>[
        QueueItem('http://h/1.m3u8', name: 'One', group: 'News'),
        QueueItem('http://h/2.m3u8', name: 'Two'),
      ], 0);
      expect(q.isChannelList, isTrue);
      expect(q.length, 2);
      expect(q.current!.label, 'One');
      // URLs are never rewritten (a URL's spelling is its key).
      expect(q.items.value[0].url, 'http://h/1.m3u8');
      // The value is cached per list, and flips back with the data.
      q.setQueue(<String>['C:/a.mkv'], 0);
      expect(q.isChannelList, isFalse);
    });

    test('a URL row without a name is a local row (plain URL open)', () {
      q.setQueue(<String>['http://h/stream'], 0);
      expect(q.isChannelList, isFalse);
      expect(q.current!.label, 'stream');
    });

    test('progressive batches append behind the playing channel (M-3)', () {
      // Batch 1 installs the list and row 0 starts playing (§10.10b).
      q.setItems(<QueueItem>[
        const QueueItem('http://h/0', name: 'Ch 0'),
        const QueueItem('http://h/1', name: 'Ch 1'),
      ], 0);
      int fires = 0;
      void count() => fires++;
      q.items.addListener(count);

      // The tail arrives while channel 0 plays: the index never moves and
      // the list is published exactly once per batch.
      q.appendItems(<QueueItem>[
        const QueueItem('http://h/2', name: 'Ch 2'),
        const QueueItem('http://h/3', name: 'Ch 3'),
      ]);
      expect(fires, 1);
      expect(q.index.value, 0);
      expect(q.length, 4);
      expect(q.isChannelList, isTrue);

      // An empty batch is not a publish.
      q.appendItems(const <QueueItem>[]);
      expect(fires, 1);

      // Next becomes possible only as rows land — the M56 frontier park.
      expect(q.hasNext, isTrue);
      q.setIndex(3);
      expect(q.hasNext, isFalse);
      q.appendItems(<QueueItem>[const QueueItem('http://h/4', name: 'Ch 4')]);
      expect(q.hasNext, isTrue);
      expect(q.index.value, 3);

      q.items.removeListener(count);
    });

    test('appended rows get the same canonical spelling as the first batch',
        () {
      q.setItems(<QueueItem>[
        const QueueItem(r'C:\Lists\media\a.mkv', name: 'A'),
      ], 0);
      q.appendItems(<QueueItem>[
        // A local path inside a local .m3u (the mapper resolved it
        // already); a stream URL keeps its exact spelling.
        const QueueItem(r'C:\Lists\media\b.mkv', name: 'B'),
        const QueueItem('http://h/live/1?a=1', name: 'C'),
      ]);
      expect(q.items.value[0].url, 'C:/Lists/media/a.mkv');
      expect(q.items.value[1].url, 'C:/Lists/media/b.mkv');
      expect(q.items.value[2].url, 'http://h/live/1?a=1');
      // Channel details survive the canonical rewrite.
      expect(q.items.value[1].name, 'B');
    });
  });

  group('playlistRowOf', () {
    test('thirds', () {
      expect(playlistRowOf(-1, 0), -1);
      expect(<int>[for (int i = 0; i < 5; i++) playlistRowOf(i, 5)],
          <int>[0, 0, 1, 1, 2]);
      expect(<int>[for (int i = 0; i < 3; i++) playlistRowOf(i, 3)],
          <int>[0, 1, 2]);
      expect(playlistRowOf(0, 1), 0);
    });
  });
}
