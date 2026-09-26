import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_power_service.dart';
import 'package:salu/core/remote/remote_protocol.dart';

class _FakePowerPlatform extends RemotePowerPlatform {
  _FakePowerPlatform({this.supported = true});

  final bool supported;
  int sleepCalls = 0;
  int shutdownCalls = 0;

  @override
  bool get available => supported;

  @override
  Future<String?> sleep() async {
    sleepCalls++;
    return null;
  }

  @override
  Future<String?> shutdown() async {
    shutdownCalls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Remote power commands (pc_part.md Part D · remote.md §17.15)', () {
    test('pc_sleep and pc_shutdown succeed with fake power service', () async {
      final _FakePowerPlatform platform = _FakePowerPlatform(supported: true);
      final RemotePowerService power = RemotePowerService(platform: platform);
      final List<String> powerActions = <String>[];

      final RemoteCommandHandler handler = RemoteCommandHandler(
        power: power,
        onPowerAction: (String act) async => powerActions.add(act),
      );

      final RemoteCommandResponse sleepResp = await handler.handle(
        const RemoteCommand(id: 1, verb: 'pc_sleep'),
      );
      expect(sleepResp.ok, isTrue);
      expect(powerActions, <String>['sleep']);

      final RemoteCommandResponse shutdownResp = await handler.handle(
        const RemoteCommand(id: 2, verb: 'pc_shutdown'),
      );
      expect(shutdownResp.ok, isTrue);
      expect(powerActions, <String>['sleep', 'shutdown']);
    });

    test('rejects commands with arguments (no arguments allowed)', () async {
      final _FakePowerPlatform platform = _FakePowerPlatform(supported: true);
      final RemotePowerService power = RemotePowerService(platform: platform);
      final RemoteCommandHandler handler = RemoteCommandHandler(power: power);

      final RemoteCommandResponse resp = await handler.handle(
        const RemoteCommand(
          id: 3,
          verb: 'pc_sleep',
          args: <String, Object?>{'force': true},
        ),
      );
      expect(resp.ok, isFalse);
      expect(resp.code, RemoteErrorCode.invalidArguments);
    });

    test('fails gracefully when power management is unsupported', () async {
      final _FakePowerPlatform platform = _FakePowerPlatform(supported: false);
      final RemotePowerService power = RemotePowerService(platform: platform);
      final RemoteCommandHandler handler = RemoteCommandHandler(power: power);

      final RemoteCommandResponse resp = await handler.handle(
        const RemoteCommand(id: 4, verb: 'pc_shutdown'),
      );
      expect(resp.ok, isFalse);
      expect(resp.code, RemoteErrorCode.invalidArguments);
    });

    test('rejects duplicate pending power commands', () async {
      final _FakePowerPlatform platform = _FakePowerPlatform(supported: true);
      final RemotePowerService power = RemotePowerService(platform: platform);
      final RemoteCommandHandler handler = RemoteCommandHandler(
        power: power,
        onPowerAction: (String act) async {
          // Keep it pending
          await Future<void>.delayed(const Duration(milliseconds: 100));
        },
      );

      // Trigger first command asynchronously
      final Future<RemoteCommandResponse> first = handler.handle(
        const RemoteCommand(id: 5, verb: 'pc_sleep'),
      );

      // Trigger second command while first is pending
      final RemoteCommandResponse second = await handler.handle(
        const RemoteCommand(id: 6, verb: 'pc_sleep'),
      );
      expect(second.ok, isFalse);
      expect(second.code, RemoteErrorCode.busy);

      final RemoteCommandResponse firstResult = await first;
      expect(firstResult.ok, isTrue);
    });
  });
}
