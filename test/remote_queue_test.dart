import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/queue_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/ui/osd/osd_controller.dart';

/// The queue verbs (remote.md §17.4) — the phone's playlist card.
///
/// Two facts the card's whole design rests on: `queue_get` hands out
/// **titles only, never a path** (A3/§17.4), and `queue_clear` is the phone's
/// ✕ — stop + empty, through the same `TransportActions.clearQueue` the PC's
/// own bin uses, idempotent on an already-empty queue, and still undoable
/// from the PC screen for the five seconds its card is up.
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

  setUp(() {
    queue.clear();
    player.hasMedia.value = false;
    player.currentPath.value = null;
    player.stopMemory.value = null;
    player.transportState.value = TransportState.idle;
    OsdController.instance.dismiss();
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
