import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/channel_grouping.dart';
import 'package:salu/core/channel_view_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/remote/remote_service.dart';
import 'package:salu/ui/osd/osd_controller.dart';

/// The queue verbs (remote.md §17.4) — the phone's playlist card.
///
/// Two facts the card's whole design rests on: `queue_get` hands out
/// **titles only, never a path** (A3/§17.4), and `queue_clear` is the phone's
/// ✕ — stop + empty, through the same `TransportActions.clearQueue` the PC's
/// own bin uses, idempotent on an already-empty queue, and still undoable
/// from the PC screen for the five seconds its card is up.
///
/// Plus the channel-grouping verbs (pc_part.md §11): `queue_groups` answers
/// the current mode's groups in exactly [ChannelGrouping]'s descriptor-head
/// order, `queue_group_set` is the phone's chip moving the PC pill — a pure
/// view change that the next snapshot's `queue.grouping` carries.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These verbs only read notifiers and park the queue, so they are testable
  // without loading a Windows DLL (`PlayerService` installed notifier-only —
  // the door `info_panel_test.dart` / `right_menu_test.dart` use): a clear
  // with nothing playing never reaches the engine.
  PlayerService.installNotifierOnlyForTesting();

  final PlayerService player = PlayerService.instance;
  final QueueService queue = QueueService.instance;
  final RemoteCommandHandler handler = RemoteCommandHandler();

  Future<RemoteCommandResponse> send(
    String verb, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) =>
      handler.handle(RemoteCommand(id: 7, verb: verb, args: args));

  /// The channel fixture the grouping tests share: News appears first,
  /// Sports second, one channel has no category (the Unknown bucket), and
  /// the languages are on purpose unsorted (Urdu, English, Urdu, —).
  final List<QueueItem> channels = const <QueueItem>[
    QueueItem('http://h/1', name: 'One', group: 'News', language: 'Urdu'),
    QueueItem('http://h/2', name: 'Two', group: 'Sports', language: 'English'),
    QueueItem('http://h/3', name: 'Three', group: 'News', language: 'Urdu'),
    QueueItem('http://h/4', name: 'Four'),
    QueueItem('http://h/5', name: 'Five', group: 'Sports'),
  ];

  setUp(() {
    queue.clear();
    player.hasMedia.value = false;
    player.currentPath.value = null;
    player.stopMemory.value = null;
    player.transportState.value = TransportState.idle;
    OsdController.instance.dismiss();
    // The grouping verbs write the shared channel view — never let a test
    // hand its mode or open group to the next one.
    ChannelViewService.instance.reset();
  });

  tearDown(() => OsdController.instance.dismiss());

  group('queue_get — titles only, paged', () {
    test('a local row is its file name; the path never leaves the PC',
        () async {
      queue.setQueue(<String>[
        r'C:\Videos\Show.S01E01.mkv',
        r'C:\Videos\Show.S01E02.mkv',
      ], 1);

      final RemoteCommandResponse reply =
          await send('queue_get', <String, Object?>{'from': 0, 'count': 10});

      expect(reply.ok, isTrue);
      final Map<String, Object?> result = reply.result!;
      expect(result['type'], 'queue_result');
      expect(result['total'], 2);
      expect(result['from'], 0);

      final List<Object?> rows = result['rows']! as List<Object?>;
      expect(rows.length, 2);
      final Map<String, Object?> first = rows.first! as Map<String, Object?>;
      expect(first['index'], 0);
      expect(first['title'], 'Show.S01E01');
      expect(first['now'], isFalse);
      expect((rows[1]! as Map<String, Object?>)['now'], isTrue);

      // A3's rule, asserted on the wire: the payload the phone receives
      // carries the display name and nothing that looks like a folder.
      final String wire = jsonEncode(rows);
      expect(wire.contains('Show.S01E01'), isTrue);
      expect(wire.contains(r'C:\Videos'), isFalse);
    });

    test('a channel row is its label; the stream URL stays hidden', () async {
      queue.setItems(
        const <QueueItem>[QueueItem('http://h/secret-token/1', name: 'BBC One')],
        0,
      );

      final RemoteCommandResponse reply = await send('queue_get');
      expect(reply.ok, isTrue);
      final String wire = jsonEncode(reply.result!['rows']);

      expect(wire.contains('BBC One'), isTrue);
      expect(wire.contains('secret-token'), isFalse);
    });

    test('count is capped at the protocol maximum of 100', () async {
      queue.setQueue(
        List<String>.generate(150, (int i) => 'C:/Videos/$i.mkv'),
        0,
      );

      final RemoteCommandResponse reply =
          await send('queue_get', <String, Object?>{'from': 0, 'count': 500});
      expect(reply.ok, isTrue);
      final List<Object?> rows = reply.result!['rows']! as List<Object?>;

      expect(rows.length, 100);
      expect((rows.last! as Map<String, Object?>)['index'], 99);
      expect(reply.result!['total'], 150);
    });

    test('a window past the end is an empty page, not an error', () async {
      queue.setQueue(<String>['C:/Videos/a.mkv'], 0);

      final RemoteCommandResponse reply =
          await send('queue_get', <String, Object?>{'from': 40, 'count': 20});

      expect(reply.ok, isTrue);
      expect(reply.result!['count'], 0);
      expect(reply.result!['rows'], isEmpty);
    });
  });

  group('queue_groups — the phone\'s group chips (pc_part §11)', () {
    test('flat answers an empty list', () async {
      queue.setItems(channels, 0);

      final RemoteCommandResponse reply = await send('queue_groups');

      expect(reply.ok, isTrue);
      expect(reply.result!['groups'], isEmpty);
    });

    test(
        'category answers first-appearance order, Unknown last — parity '
        'with the ChannelGrouping descriptors', () async {
      queue.setItems(channels, 0);
      ChannelViewService.instance.groupMode.value = ChannelGroupMode.category;

      final RemoteCommandResponse reply = await send('queue_groups');
      expect(reply.ok, isTrue);
      final List<Object?> groups = reply.result!['groups']! as List<Object?>;

      expect(groups.map((Object? g) => (g! as Map<String, Object?>)['name']),
          <String>['News', 'Sports', 'Unknown']);

      // Parity, asserted against the model the PC panel paints: same heads,
      // same order, same stable keys, same absolute first-row indexes.
      final List<ChannelGroup> expected = ChannelGrouping.buildGroups(
        channels,
        List<int>.generate(channels.length, (int i) => i),
        ChannelGroupMode.category,
      );
      expect(groups.length, expected.length);
      for (int i = 0; i < expected.length; i++) {
        final Map<String, Object?> g = groups[i]! as Map<String, Object?>;
        final ChannelGroup e = expected[i];
        expect(g['key'], e.key, reason: 'group $i');
        expect(g['name'], e.label, reason: 'group $i');
        expect(g['count'], e.indexes.length, reason: 'group $i');
        expect(g['start'], e.indexes.first, reason: 'group $i');
      }
      // The phone plays a group by `queue_jump {index: start}` — the
      // starts are REAL queue indexes, in the order the accordion shows.
      expect(
        groups.map((Object? g) => (g! as Map<String, Object?>)['start']),
        <int>[0, 1, 3],
      );
    });

    test('language sorts alphabetically, Unknown still last', () async {
      queue.setItems(channels, 0);
      ChannelViewService.instance.groupMode.value = ChannelGroupMode.language;

      final RemoteCommandResponse reply = await send('queue_groups');

      final List<Object?> groups = reply.result!['groups']! as List<Object?>;
      expect(groups.map((Object? g) => (g! as Map<String, Object?>)['name']),
          <String>['English', 'Urdu', 'Unknown']);
      // 'English' holds row 1, 'Urdu' rows 0 and 2 — first row 0; Unknown
      // (the two category-only channels) first row 3.
      expect(
        groups.map((Object? g) => (g! as Map<String, Object?>)['start']),
        <int>[1, 0, 3],
      );
    });

    test('a file queue answers empty — the chips are a channel surface',
        () async {
      queue.setQueue(<String>[r'C:\Videos\Show.S01E01.mkv'], 0);

      final RemoteCommandResponse reply = await send('queue_groups');

      expect(reply.ok, isTrue);
      expect(reply.result!['groups'], isEmpty);
    });

    test('an empty queue answers empty, not an error', () async {
      final RemoteCommandResponse reply = await send('queue_groups');

      expect(reply.ok, isTrue);
      expect(reply.result!['groups'], isEmpty);
    });
  });

  group('queue_group_set — the chip moves the PC pill (pc_part §11)', () {
    test('sets the mode and opens the group holding the playing channel',
        () async {
      // Row 2 is 'Three' — the News group.
      queue.setItems(channels, 2);

      final RemoteCommandResponse reply = await send(
        'queue_group_set',
        <String, Object?>{'by': 'category'},
      );

      expect(reply.ok, isTrue);
      final ChannelViewService view = ChannelViewService.instance;
      expect(view.groupMode.value, ChannelGroupMode.category);
      expect(
        view.openGroup.value,
        ChannelGrouping.keyFor(channels, 2, ChannelGroupMode.category),
      );
      // The queue was never touched.
      expect(queue.length, channels.length);
      expect(queue.index.value, 2);
    });

    test('flat closes the accordion', () async {
      queue.setItems(channels, 2);
      ChannelViewService.instance
        ..groupMode.value = ChannelGroupMode.category
        ..openGroup.value = ChannelGrouping.keyFor(
            channels, 2, ChannelGroupMode.category);

      final RemoteCommandResponse reply = await send(
        'queue_group_set',
        <String, Object?>{'by': 'flat'},
      );

      expect(reply.ok, isTrue);
      expect(ChannelViewService.instance.groupMode.value, ChannelGroupMode.flat);
      expect(ChannelViewService.instance.openGroup.value, isNull);
    });

    test('an unknown by is invalid_arguments', () async {
      queue.setItems(channels, 0);

      final RemoteCommandResponse reply = await send(
        'queue_group_set',
        <String, Object?>{'by': 'alphabetical'},
      );

      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.invalidArguments);
    });

    test('the snapshot roundtrip: the block carries the new mode', () async {
      queue.setItems(channels, 0);

      await send('queue_group_set', <String, Object?>{'by': 'language'});

      // The very block `_snapshot` puts on the wire next.
      final Map<String, Object?>? grouping = remoteQueueGrouping(
        queue.items.value,
        ChannelViewService.instance.groupMode.value,
      );
      expect(grouping, isNotNull);
      expect(grouping!['mode'], 'language');
      // This fixture carries categories and languages, no countries.
      expect(grouping['available'], <String>['category', 'language']);
    });

    test('a file queue keeps the grouping block absent', () {
      queue.setQueue(<String>[r'C:\Videos\a.mkv'], 0);
      expect(
        remoteQueueGrouping(
            queue.items.value, ChannelGroupMode.flat),
        isNull,
      );
    });
  });

  group('remote m3u doors keep channel names (pc_part §11.6)', () {
    test('an m3u via fs_open queues through the channel loader', () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('salu_fs_open');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          // The temporary directory may already have been removed.
        }
      });
      final File m3u = File(p.join(tmp.path, 'list.m3u'));
      m3u.writeAsStringSync(
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="News",Alpha\n'
        'http://h/alpha\n'
        '#EXTINF:-1 group-title="Sports",Beta\n'
        'http://h/beta\n',
      );

      // The notifier-only test player has no engine: the play the loader
      // triggers once the first batch lands dies with a
      // LateInitializationError — the expected, harmless death here,
      // because the assertion is the ROUTE (the channel loader owned the
      // m3u), not the engine.
      Object? zoneError;
      RemoteCommandResponse? reply;
      await runZonedGuarded(() async {
        reply = await send(
          'fs_open',
          <String, Object?>{'paths': <String>[m3u.path]},
        );
        // Let the loader's engine-less play dispatch its error into the
        // zone handler before the assertions run.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (Object error, StackTrace stack) {
        // Late-initialized engine fields are expected to fail in this
        // notifier-only fixture. Keep all other zone errors visible.
        if (error.runtimeType.toString() != 'LateInitializationError') {
          zoneError = error;
        }
      });

      expect(zoneError, isNull);
      expect(reply, isNotNull);
      expect(reply!.ok, isTrue);
      // The panel's channel header — and the phone's grouping — both
      // depend on the items keeping their channel names.
      expect(queue.isChannelList, isTrue);
      expect(queue.length, 2);
      expect(
        queue.items.value.map((QueueItem item) => item.label),
        <String>['Alpha', 'Beta'],
      );
      expect(queue.items.value.first.group, 'News');
    });
  });

  group('queue_clear — the phone\'s ✕', () {
    test('stops and empties: the snapshot the phone expects next', () async {
      queue.setQueue(
        <String>[r'C:\Videos\a.mkv', r'C:\Videos\b.mkv'],
        1,
      );

      final RemoteCommandResponse reply = await send('queue_clear');

      expect(reply.ok, isTrue);
      expect(queue.hasQueue, isFalse);
      expect(queue.length, 0);
      expect(queue.index.value, -1);
    });

    test('an already-empty queue is ok — never an error', () async {
      final RemoteCommandResponse reply = await send('queue_clear');

      expect(reply.ok, isTrue);
      expect(OsdController.instance.current.value, isNull);
    });

    test('the PC keeps its own Undo door open for a remote clear', () async {
      queue.setQueue(<String>[r'C:\Videos\a.mkv'], 0);

      await send('queue_clear');
      expect(queue.hasQueue, isFalse);

      // The card is not a remote invention: it is the one the PC's own bin
      // raises, wording and all.
      final OsdCard? card = OsdController.instance.current.value;
      expect(card, isA<OsdUndoCard>());
      final OsdUndoCard undo = card! as OsdUndoCard;
      expect(undo.label, 'Playlist cleared');

      undo.onUndo();
      await Future<void>.delayed(Duration.zero);

      expect(queue.length, 1);
      expect(queue.paths.single, 'C:/Videos/a.mkv');
      expect(queue.index.value, 0);
    });

    test('clearing a channel list leaves nothing behind either', () async {
      queue.setItems(
        const <QueueItem>[
          QueueItem('http://h/1', name: 'BBC One'),
          QueueItem('http://h/2', name: 'BBC Two'),
        ],
        0,
      );

      final RemoteCommandResponse reply = await send('queue_clear');

      expect(reply.ok, isTrue);
      expect(queue.hasQueue, isFalse);
      expect(queue.index.value, -1);
      expect(queue.isChannelList, isFalse);
    });
  });
}
