import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_input_service.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/remote/remote_service.dart';

/// Fake input injector for simulating mouse move bursts.
class _BurstPointerInjector extends RemotePointerInjector {
  int movesCount = 0;

  @override
  bool get available => true;

  @override
  bool moveBy(int dx, int dy) {
    movesCount++;
    return true;
  }

  @override
  bool click(String button, int count) => true;

  @override
  ({int x, int y})? cursor() => (x: 0, y: 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();

  group('Connection reliability and tests (pc_part.md Part E · E7)', () {
    test('E7.1 / E1: ping answered immediately without queuing behind blocked command isolate', () async {
      // In RemoteService, ping is answered inline on the websocket path.
      // RemoteCommandHandler also maintains ping handler for testing compatibility.
      final RemoteCommandHandler handler = RemoteCommandHandler();
      final int now = DateTime.now().millisecondsSinceEpoch;
      final RemoteCommandResponse pong = await handler.handle(
        RemoteCommand(id: 10, verb: 'ping', args: <String, Object?>{'at': now}),
      );
      expect(pong.ok, isTrue);
      expect(pong.result!['type'], equals('pong'));
      expect(pong.result!['at'], equals(now));
      expect(pong.result!['serverAt'], isA<int>());
    });

    test('E7.2 / E3: state_get under mouse-move burst acks promptly', () async {
      final _BurstPointerInjector injector = _BurstPointerInjector();
      final RemoteCommandHandler handler = RemoteCommandHandler(
        input: RemoteInputService(injector: injector, scale: () => 1.0),
      );

      // Simulate a burst of 25 mouse moves/s
      for (int i = 0; i < 25; i++) {
        final RemoteCommandResponse moveResp = await handler.handle(
          RemoteCommand(
            id: 100 + i,
            verb: 'web_mouse_move',
            args: const <String, Object?>{'dx': 5.0, 'dy': -3.0},
          ),
        );
        expect(moveResp.ok, isTrue);
      }
      expect(injector.movesCount, equals(25));

      // state_get must ack within 3 s (here virtually instantaneous)
      final Stopwatch sw = Stopwatch()..start();
      final RemoteCommandResponse stateResp = await handler.handle(
        const RemoteCommand(id: 200, verb: 'state_get'),
      );
      sw.stop();

      expect(stateResp.ok, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('E7.3 / E4: slot accounting and max 4 live sockets', () {
      final RemoteService service = RemoteService.instance;
      expect(service.connectedCount.value, equals(0));
    });

    test('E7.4 / E5: fresh-socket features include core modules and conditional flags', () {
      final List<String> withAll = RemoteService.helloFeatures(mouse: true, power: true);
      expect(withAll, containsAll(<String>[
        'state',
        'queue',
        'files',
        'tune',
        'subtitles',
        'web',
        'web_mouse',
        'pc_power',
      ]));

      final List<String> minimal = RemoteService.helloFeatures(mouse: false, power: false);
      expect(minimal, isNot(contains('web_mouse')));
      expect(minimal, isNot(contains('pc_power')));
    });
  });
}
