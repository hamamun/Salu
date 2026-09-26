import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/channel_grouping.dart';
import 'package:salu/core/channel_view_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_grouping_cache.dart';
import 'package:salu/core/queue_service.dart';
import 'package:salu/core/remote/queue_pages.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/remote/remote_service.dart';

QueueItem _ch(
  String url,
  String name, {
  String? group,
  String? language,
  String? country,
}) =>
    QueueItem(
      url,
      name: name,
      group: group,
      language: language,
      country: country,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();

  final QueueService queue = QueueService.instance;
  final RemoteCommandHandler handler = RemoteCommandHandler();

  Future<RemoteCommandResponse> send(
    String verb, [
    Map<String, Object?> args = const <String, Object?>{},
    int id = 7,
  ]) =>
      handler.handle(RemoteCommand(id: id, verb: verb, args: args));

  setUp(() {
    queue.clear();
    ChannelViewService.instance.reset();
    QueueGroupingCache.instance.clear();
    QueueGroupingCache.forceIsolateForTest = false;
    QueuePageHooks.reset();
    ChannelGrouping.availabilityScansForTest = 0;
  });

  tearDown(QueuePageHooks.reset);

  group('content revision', () {
    test('is a non-empty process token and ignores index and grouping', () {
      final String before = queue.contentRevision;
      expect(before, matches(RegExp(r'^q[0-9a-f]{16}-\d+$')));

      queue.setItems(<QueueItem>[_ch('http://h/1', 'One', country: 'BD')], 0);
      final String loaded = queue.contentRevision;
      expect(loaded, isNot(before));

      queue.setIndex(0);
      ChannelViewService.instance.applyMode(
        ChannelGroupMode.country,
        items: queue.items.value,
        playingIndex: 0,
      );
      expect(queue.contentRevision, loaded);
      expect(queue.index.value, 0);
      expect(queue.items.value.single.label, 'One');

      queue.appendItems(<QueueItem>[_ch('http://h/2', 'Two', country: 'US')]);
      expect(queue.contentRevision, isNot(loaded));
      final String appended = queue.contentRevision;

      queue.move(1, 0);
      expect(queue.contentRevision, isNot(appended));
      queue.removeAt(0);
      final String removed = queue.contentRevision;
      expect(removed, isNot(appended));
      queue.clear();
      expect(queue.contentRevision, isNot(removed));
    });

    test('the queue block carries revision and not the snapshot rev', () {
      queue.setItems(<QueueItem>[_ch('http://h/1', 'One', group: 'News')], 0);
      final Map<String, Object?> block = remoteQueueBlock(
        kind: 'channels',
        count: 1,
        index: 0,
        revision: queue.contentRevision,
        grouping: remoteQueueGrouping(
          queue.items.value,
          ChannelGroupMode.flat,
        ),
      );
      expect(block['revision'], queue.contentRevision);
      expect(block.containsKey('rev'), isFalse);
      expect(block['index'], 0);
      queue.setIndex(0);
      expect(queue.contentRevision, block['revision']);
    });

    test('availability is not rescanned for the same published list', () {
      final List<QueueItem> items = <QueueItem>[
        _ch('http://h/1', 'One', group: 'News', language: 'Urdu'),
      ];
      QueueGroupingCache.instance.availability(items);
      QueueGroupingCache.instance.availability(items);
      remoteQueueGrouping(items, ChannelGroupMode.flat);
      expect(ChannelGrouping.availabilityScansForTest, 1);
    });
  });

  group('queue_get byte budget', () {
    test('a huge title is shortened, the index is not, and the frame fits',
        () async {
      queue.setItems(
        <QueueItem>[
          _ch('http://secret.example/token', '🎵' * 4000),
        ],
        0,
      );
      final String revision = queue.contentRevision;
      final RemoteCommandResponse reply = await send(
        'queue_get',
        <String, Object?>{'from': 0, 'count': 10, 'revision': revision},
      );
      expect(reply.ok, isTrue);
      final Map<String, Object?> body = reply.result!;
      expect(body['revision'], revision);
      expect(body['ok'], isTrue);
      final List<Object?> rows = body['rows']! as List<Object?>;
      expect(rows, hasLength(1));
      final Map<String, Object?> row = rows.single! as Map<String, Object?>;
      expect(row['index'], 0);
      expect((row['title']! as String).length, lessThan(400));
      final String wire = jsonEncode(<String, Object?>{
        'id': 7,
        'proto': 1,
        ...body,
      });
      expect(utf8.encode(wire).length, lessThanOrEqualTo(maxRemoteMessageBytes));
      expect(wire.contains('secret.example'), isFalse);
      expect(wire.contains('token'), isFalse);
    });

    test('long titles return fewer consecutive rows instead of busy', () async {
      queue.setItems(
        List<QueueItem>.generate(
          30,
          (int i) => _ch('http://h/$i', '名' * 400, group: 'G'),
        ),
        0,
      );
      final RemoteCommandResponse reply = await send(
        'queue_get',
        <String, Object?>{'from': 2, 'count': 30},
      );
      expect(reply.ok, isTrue);
      expect(reply.code, isNull);
      final List<Object?> rows = reply.result!['rows']! as List<Object?>;
      expect(rows.length, lessThan(30));
      expect(rows, isNotEmpty);
      for (int i = 0; i < rows.length; i++) {
        expect((rows[i]! as Map<String, Object?>)['index'], 2 + i);
      }
      final String wire = jsonEncode(<String, Object?>{
        'id': 7,
        'proto': 1,
        ...reply.result!,
      });
      expect(utf8.encode(wire).length, lessThanOrEqualTo(maxRemoteMessageBytes));
    });

    test('a stale revision returns no rows', () async {
      queue.setItems(<QueueItem>[_ch('http://h/1', 'One')], 0);
      final RemoteCommandResponse reply = await send(
        'queue_get',
        <String, Object?>{'revision': 'not-current', 'from': 0, 'count': 10},
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.staleQueue);
      expect(reply.result, isNull);
    });

    test('an old phone without revision still gets titles plus the token',
        () async {
      queue.setQueue(<String>[r'C:\Videos\Show.mkv'], 0);
      final RemoteCommandResponse reply = await send('queue_get');
      expect(reply.ok, isTrue);
      expect(reply.result!['revision'], queue.contentRevision);
      expect(
        ((reply.result!['rows']! as List<Object?>).single!
                as Map<String, Object?>)['title'],
        'Show',
      );
    });
  });

  group('queue_groups_page', () {
    List<QueueItem> scattered() => <QueueItem>[
          _ch('http://h/0', 'A', country: 'Bangladesh', group: 'News'),
          _ch('http://h/1', 'B', country: 'Albania', group: 'Sports'),
          _ch('http://h/2', 'C', country: 'Bangladesh', group: 'News'),
          _ch('http://h/3', 'D'),
        ];

    test('membership is explicit and not a start/count range', () async {
      queue.setItems(scattered(), 0);
      final String revision = queue.contentRevision;
      final RemoteCommandResponse reply = await send(
        queueGroupsPageVerb,
        <String, Object?>{
          'by': 'country',
          'revision': revision,
          'from': 0,
          'count': 20,
        },
      );
      expect(reply.ok, isTrue);
      final Map<String, Object?> body = reply.result!;
      expect(body['type'], 'queue_groups_result');
      expect(body['ok'], isTrue);
      expect(body['revision'], revision);
      expect(body['by'], 'country');
      expect(body['next'], isNull);
      final List<Object?> groups = body['groups']! as List<Object?>;
      expect(
        groups.map((Object? g) => (g! as Map<String, Object?>)['name']),
        <String>['Albania', 'Bangladesh', 'Unknown'],
      );
      final Map<String, Object?> albania = groups[0]! as Map<String, Object?>;
      expect(albania['indexes'], <int>[1]);
      expect(albania['start'], 1);
      expect(albania['count'], 1);
      expect((groups[1]! as Map<String, Object?>)['indexes'], <int>[0, 2]);
      expect((groups[2]! as Map<String, Object?>)['indexes'], <int>[3]);
    });

    test('fragments split a group, and the cursor does not depend on count',
        () async {
      final List<QueueItem> items = List<QueueItem>.generate(
        250,
        (int i) => _ch('http://h/$i', 'Ch $i', country: i.isEven ? 'BD' : 'US'),
      );
      final QueueFragmentPayload payload = buildQueueFragments(
        items: items,
        mode: ChannelGroupMode.country,
        revision: 'token',
        by: 'country',
      );
      expect(payload.fragments.length, greaterThan(2));
      final QueueGroupFragment first = payload.fragments.first;
      expect(first.indexes.length, lessThanOrEqualTo(queueFragmentMaxIndexes));
      expect(first.indexes, isNot(List<int>.generate(first.count, (int i) => first.start + i)));

      final QueueGroupsPage small = packGroupFragments(
        id: 7,
        revision: 'token',
        by: 'country',
        fragments: payload.fragments,
        from: 0,
        count: 1,
      );
      final QueueGroupsPage wide = packGroupFragments(
        id: 7,
        revision: 'token',
        by: 'country',
        fragments: payload.fragments,
        from: 0,
        count: 20,
      );
      expect(small.groups.single['indexes'], first.indexes);
      expect(wide.groups.first['indexes'], first.indexes);
      expect(small.next, 1);
      expect(wide.groups.length, greaterThan(1));

      final Set<int> seen = <int>{};
      String? sharedKey;
      for (final QueueGroupFragment fragment in payload.fragments) {
        if (sharedKey == null || sharedKey != fragment.key) {
          sharedKey = fragment.key;
        } else {
          expect(fragment.name, payload.fragments.firstWhere((QueueGroupFragment f) => f.key == fragment.key).name);
          expect(fragment.count, payload.fragments.firstWhere((QueueGroupFragment f) => f.key == fragment.key).count);
          expect(fragment.start, payload.fragments.firstWhere((QueueGroupFragment f) => f.key == fragment.key).start);
        }
        for (final int index in fragment.indexes) {
          expect(seen.add(index), isTrue, reason: 'duplicate $index');
        }
      }
      expect(seen.length, items.length);
    });

    test('pages stay inside 8 KiB and the cursor is monotonic', () async {
      final List<QueueItem> items = List<QueueItem>.generate(
        80,
        (int i) => _ch('http://h/$i', '名' * 180, country: 'C$i'),
      );
      queue.setItems(items, 0);
      final String revision = queue.contentRevision;
      int? cursor = 0;
      int pages = 0;
      final Set<int> seen = <int>{};
      while (cursor != null) {
        final RemoteCommandResponse reply = await send(
          queueGroupsPageVerb,
          <String, Object?>{
            'by': 'country',
            'revision': revision,
            'from': cursor,
            'count': 20,
          },
        );
        expect(reply.ok, isTrue, reason: reply.message);
        final Map<String, Object?> body = reply.result!;
        final String wire = jsonEncode(<String, Object?>{
          'id': 7,
          'proto': 1,
          ...body,
        });
        expect(utf8.encode(wire).length, lessThanOrEqualTo(maxRemoteMessageBytes));
        final List<Object?> groups = body['groups']! as List<Object?>;
        expect(groups, isNotEmpty);
        for (final Object? raw in groups) {
          final Map<String, Object?> group = raw! as Map<String, Object?>;
          for (final Object? index in group['indexes']! as List<Object?>) {
            expect(seen.add(index! as int), isTrue);
          }
        }
        final Object? next = body['next'];
        if (next != null) {
          expect(next, greaterThan(cursor));
          cursor = next as int;
        } else {
          cursor = null;
        }
        pages++;
        expect(pages, lessThan(40));
      }
      expect(seen.length, items.length);
    });

    test('a changed playlist while preparing fails stale_queue', () async {
      queue.setItems(scattered(), 0);
      final String revision = queue.contentRevision;
      QueuePageHooks.beforePublish = () async {
        queue.appendItems(<QueueItem>[_ch('http://h/9', 'New', country: 'ZZ')]);
      };
      final RemoteCommandResponse reply = await send(
        queueGroupsPageVerb,
        <String, Object?>{
          'by': 'country',
          'revision': revision,
          'from': 0,
          'count': 20,
        },
      );
      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.staleQueue);
      expect(reply.result, isNull);
    });

    test('invalid mode and a missing revision are invalid_arguments', () async {
      queue.setItems(scattered(), 0);
      expect(
        (await send(queueGroupsPageVerb, <String, Object?>{
          'by': 'flat',
          'revision': queue.contentRevision,
        }))
            .code,
        RemoteErrorCode.invalidArguments,
      );
      expect(
        (await send(queueGroupsPageVerb, <String, Object?>{
          'by': 'country',
        }))
            .code,
        RemoteErrorCode.invalidArguments,
      );
      expect(
        (await send(queueGroupsPageVerb, <String, Object?>{
          'by': 'country',
          'revision': queue.contentRevision,
          'from': -1,
        }))
            .code,
        RemoteErrorCode.invalidArguments,
      );
    });

    test('the requested mode ignores the panel setting', () async {
      queue.setItems(scattered(), 2);
      ChannelViewService.instance.applyMode(
        ChannelGroupMode.category,
        items: queue.items.value,
        playingIndex: 2,
      );
      final RemoteCommandResponse reply = await send(
        queueGroupsPageVerb,
        <String, Object?>{
          'by': 'country',
          'revision': queue.contentRevision,
        },
      );
      expect(reply.ok, isTrue);
      expect(reply.result!['by'], 'country');
      expect(ChannelViewService.instance.groupMode.value, ChannelGroupMode.category);
      expect(queue.index.value, 2);
    });

    test('10 000 channels: every frame fits and coverage is exact', () {
      final List<QueueItem> items = List<QueueItem>.generate(
        10000,
        (int i) => _ch(
          'http://h/$i',
          i.isEven ? 'Channel $i ${'名' * 40}' : 'C$i',
          country: 'C${i % 30}',
          group: 'G${i % 17}',
        ),
      );
      final QueueFragmentPayload payload = buildQueueFragments(
        items: items,
        mode: ChannelGroupMode.country,
        revision: 'rev-10000',
        by: 'country',
      );
      _expectFullCoverage(payload.fragments, items.length, 'rev-10000', 'country');
    });

    test('50 000 channels and thousands of heads stay inside 8 KiB', () {
      final List<QueueItem> items = List<QueueItem>.generate(
        50000,
        (int i) => _ch('http://h/$i', '频道$i', group: 'Group ${i % 4000}'),
      );
      final QueueFragmentPayload payload = buildQueueFragments(
        items: items,
        mode: ChannelGroupMode.category,
        revision: 'rev-50000',
        by: 'category',
      );
      expect(payload.groups.length, 4000);
      _expectFullCoverage(payload.fragments, items.length, 'rev-50000', 'category');
    });
  });

  group('advertised capability', () {
    test('hello features include queue_groups_paged without a proto bump', () {
      expect(protocolVersion, 1);
      expect(
        RemoteService.helloFeatures(mouse: false),
        contains(remoteFeatureQueueGroupsPaged),
      );
      expect(RemoteService.quietVerbs, contains(queueGroupsPageVerb));
      expect(RemoteService.quietVerbs, contains('queue_get'));
    });
  });
}

void _expectFullCoverage(
  List<QueueGroupFragment> fragments,
  int count,
  String revision,
  String by,
) {
  final Set<int> seen = <int>{};
  final Map<String, QueueGroupFragment> firstByKey = <String, QueueGroupFragment>{};
  int? cursor = 0;
  var pages = 0;
  while (cursor != null) {
    final QueueGroupsPage page = packGroupFragments(
      id: 42,
      revision: revision,
      by: by,
      fragments: fragments,
      from: cursor,
      count: 20,
    );
    expect(page.tooLarge, isFalse);
    expect(page.groups, isNotEmpty);
    final int bytes = queueWireBytes(queueGroupsResultWire(
      id: 42,
      revision: revision,
      by: by,
      groups: page.groups,
      next: page.next,
    ));
    expect(bytes, lessThanOrEqualTo(maxRemoteMessageBytes));
    for (final Map<String, Object?> group in page.groups) {
      final String key = group['key']! as String;
      final QueueGroupFragment? first = firstByKey[key];
      if (first == null) {
        firstByKey[key] = QueueGroupFragment(
          key: key,
          name: group['name']! as String,
          count: group['count']! as int,
          start: group['start']! as int,
          indexes: const <int>[],
        );
      } else {
        expect(group['name'], first.name);
        expect(group['count'], first.count);
        expect(group['start'], first.start);
      }
      for (final Object? index in group['indexes']! as List<Object?>) {
        expect(seen.add(index! as int), isTrue);
      }
    }
    if (page.next != null) {
      expect(page.next!, greaterThan(cursor));
      expect(page.next!, lessThanOrEqualTo(fragments.length));
    }
    cursor = page.next;
    pages++;
    expect(pages, lessThan(count));
  }
  expect(seen.length, count);
}
