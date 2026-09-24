import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_input_service.dart';
import 'package:salu/core/remote/remote_protocol.dart';

/// The trackpad (pc_part.md C3 · remote.md §17.14.3): relative movement in
/// CSS pixels → device pixels, no extra gain, remainders carried so two
/// moves add up exactly; real clicks, 1 or 2, left/right/middle;
/// `no_web_mouse` when the pointer cannot be delivered; and the handler
/// never awaits page-side work.
class _Recorder extends RemotePointerInjector {
  _Recorder({this.ok = true});

  bool ok;
  bool live = true;
  int x = 0;
  int y = 0;
  final List<(int, int)> moves = <(int, int)>[];
  final List<(String, int)> clicks = <(String, int)>[];

  @override
  bool get available => live;

  @override
  bool moveBy(int dx, int dy) {
    if (!ok) return false;
    moves.add((dx, dy));
    x += dx;
    y += dy;
    return true;
  }

  @override
  bool click(String button, int count) {
    if (!ok) return false;
    clicks.add((button, count));
    return true;
  }

  @override
  ({int x, int y})? cursor() => (x: x, y: y);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('movement math', () {
    test('a dx/dy pair moves the pointer by exactly that much at DPR 1', () {
      final _Recorder r = _Recorder();
      final RemoteInputService input =
          RemoteInputService(injector: r, scale: () => 1);
      expect(input.moveBy(12, -7), isTrue);
      expect(r.moves, <(int, int)>[(12, -7)]);
    });

    test('twice in a row adds up', () {
      final _Recorder r = _Recorder();
      final RemoteInputService input =
          RemoteInputService(injector: r, scale: () => 1);
      input.moveBy(10, 5);
      input.moveBy(10, 5);
      expect((r.x, r.y), (20, 10));
    });

    test('CSS px scale by the window DPR, with sub-pixel carry', () {
      final _Recorder r = _Recorder();
      final RemoteInputService input =
          RemoteInputService(injector: r, scale: () => 1.25);
      for (int i = 0; i < 4; i++) {
        input.moveBy(1, -1);
      }
      // 4 × 1.25 = 5 device pixels exactly — nothing lost, nothing invented.
      expect((r.x, r.y), (5, -5));
    });

    test('no acceleration of our own: 3 × 10 == 1 × 30', () {
      final _Recorder a = _Recorder();
      final _Recorder b = _Recorder();
      final RemoteInputService slow =
          RemoteInputService(injector: a, scale: () => 1.5);
      final RemoteInputService fast =
          RemoteInputService(injector: b, scale: () => 1.5);
      for (int i = 0; i < 3; i++) {
        slow.moveBy(10, 0);
      }
      fast.moveBy(30, 0);
      expect(a.x, b.x);
    });

    test('each packet is clamped to ±320 CSS px', () {
      final _Recorder r = _Recorder();
      final RemoteInputService input =
          RemoteInputService(injector: r, scale: () => 1);
      input.moveBy(5000, -5000);
      expect(r.moves.single, (320, -320));
    });

    test('a zero move is fine and sends nothing', () {
      final _Recorder r = _Recorder();
      final RemoteInputService input =
          RemoteInputService(injector: r, scale: () => 1);
      expect(input.moveBy(0, 0), isTrue);
      expect(r.moves, isEmpty);
    });
  });

  group('the verbs', () {
    RemoteCommandHandler handlerWith(_Recorder r) => RemoteCommandHandler(
          input: RemoteInputService(injector: r, scale: () => 1),
        );

    test('web_mouse_move acks and moves', () async {
      final _Recorder r = _Recorder();
      final RemoteCommandResponse reply = await handlerWith(r).handle(
        const RemoteCommand(
          id: 1,
          verb: 'web_mouse_move',
          args: <String, Object?>{'dx': 4, 'dy': 9.0},
        ),
      );
      expect(reply.ok, isTrue);
      expect(r.moves.single, (4, 9));
    });

    test('web_mouse_move with missing numbers is invalid_arguments', () async {
      final RemoteCommandResponse reply = await handlerWith(_Recorder()).handle(
        const RemoteCommand(
          id: 2,
          verb: 'web_mouse_move',
          args: <String, Object?>{'dx': 'left'},
        ),
      );
      expect(reply.code, RemoteErrorCode.invalidArguments);
    });

    test('click count 1 vs 2', () async {
      final _Recorder r = _Recorder();
      final RemoteCommandHandler h = handlerWith(r);
      await h.handle(const RemoteCommand(
        id: 3,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'left', 'count': 1},
      ));
      await h.handle(const RemoteCommand(
        id: 4,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'left', 'count': 2},
      ));
      expect(r.clicks, <(String, int)>[('left', 1), ('left', 2)]);
    });

    test('middle and right buttons; defaults are left × 1', () async {
      final _Recorder r = _Recorder();
      final RemoteCommandHandler h = handlerWith(r);
      await h.handle(const RemoteCommand(
        id: 5,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'middle', 'count': 1},
      ));
      await h.handle(const RemoteCommand(
        id: 6,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'right', 'count': 1},
      ));
      await h.handle(const RemoteCommand(id: 7, verb: 'web_mouse_click'));
      expect(r.clicks,
          <(String, int)>[('middle', 1), ('right', 1), ('left', 1)]);
    });

    test('an unknown button or a triple click is invalid_arguments',
        () async {
      final _Recorder r = _Recorder();
      final RemoteCommandHandler h = handlerWith(r);
      final RemoteCommandResponse a = await h.handle(const RemoteCommand(
        id: 8,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'thumb', 'count': 1},
      ));
      final RemoteCommandResponse b = await h.handle(const RemoteCommand(
        id: 9,
        verb: 'web_mouse_click',
        args: <String, Object?>{'button': 'left', 'count': 3},
      ));
      expect(a.code, RemoteErrorCode.invalidArguments);
      expect(b.code, RemoteErrorCode.invalidArguments);
      expect(r.clicks, isEmpty);
    });

    test('no injector → no_web_mouse, for both verbs', () async {
      final _Recorder r = _Recorder()..live = false;
      final RemoteCommandHandler h = handlerWith(r);
      final RemoteCommandResponse move = await h.handle(const RemoteCommand(
        id: 10,
        verb: 'web_mouse_move',
        args: <String, Object?>{'dx': 1, 'dy': 1},
      ));
      final RemoteCommandResponse click = await h.handle(
          const RemoteCommand(id: 11, verb: 'web_mouse_click'));
      expect(move.code, RemoteErrorCode.noWebMouse);
      expect(click.code, RemoteErrorCode.noWebMouse);
    });

    test('a blocked SendInput (locked session) → no_web_mouse', () async {
      final _Recorder r = _Recorder(ok: false);
      final RemoteCommandResponse reply = await handlerWith(r).handle(
        const RemoteCommand(
          id: 12,
          verb: 'web_mouse_move',
          args: <String, Object?>{'dx': 3, 'dy': 3},
        ),
      );
      expect(reply.code, RemoteErrorCode.noWebMouse);
    });

    test('the handler never awaits page-side work', () async {
      // No web page, no script seam, no timers: the move completes in the
      // same microtask turn it was issued in.
      final _Recorder r = _Recorder();
      final RemoteCommandHandler h = handlerWith(r);
      bool done = false;
      final Future<RemoteCommandResponse> pending = h.handle(
        const RemoteCommand(
          id: 13,
          verb: 'web_mouse_move',
          args: <String, Object?>{'dx': 2, 'dy': 2},
        ),
      )..then((_) => done = true);
      for (int i = 0; i < 5; i++) {
        await Future<void>.value();
      }
      expect(done, isTrue);
      expect((await pending).ok, isTrue);
    });

    test('the platform injector is unavailable off Windows', () {
      final RemotePointerInjector injector = RemotePointerInjector.platform();
      // Off Windows the flag must stay unadvertised.
      if (!Platform.isWindows) expect(injector.available, isFalse);
    });
  });
}
