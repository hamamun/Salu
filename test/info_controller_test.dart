import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/info_collector.dart';
import 'package:salu/core/info_controller.dart';

class ControlledCollector extends InfoCollector {
  final List<Completer<InfoSnapshot>> pending = <Completer<InfoSnapshot>>[];
  final List<String> paths = <String>[];
  @override
  Future<InfoSnapshot> collect(InfoContext context) {
    paths.add(context.path);
    final Completer<InfoSnapshot> result = Completer<InfoSnapshot>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  test(
    'closed is inert, changes coalesce, stale media reads never publish',
    () async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      final ValueNotifier<String> media = ValueNotifier<String>('a');
      final ValueNotifier<int> tracks = ValueNotifier<int>(0);
      final ControlledCollector collector = ControlledCollector();
      final List<String> logs = <String>[];
      final InfoController controller = InfoController(
        open: open,
        changes: <Listenable>[media, tracks],
        context: () => InfoContext(path: media.value),
        collector: collector,
        log: logs.add,
      );
      media.value = 'b';
      await Future<void>.delayed(Duration.zero);
      expect(collector.pending, isEmpty);
      open.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(collector.paths, <String>['b']);
      media.value = 'c';
      tracks.value++;
      tracks.value++;
      await Future<void>.delayed(Duration.zero);
      expect(collector.paths, <String>['b', 'c']);
      collector.pending[0].complete(
        const InfoSnapshot(<String, List<InfoRow>>{
          'Identity': <InfoRow>[InfoRow('Title', 'stale')],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, isNull);
      expect(logs, isEmpty);
      const InfoSnapshot current = InfoSnapshot(
        <String, List<InfoRow>>{},
        probes: <String, bool>{'file-size': true, 'container-fps': false},
      );
      collector.pending[1].complete(current);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, same(current));
      expect(
        logs.single,
        contains('answered: file-size; unavailable: container-fps'),
      );
      tracks.value++;
      await Future<void>.delayed(Duration.zero);
      collector.pending[2].complete(current);
      await Future<void>.delayed(Duration.zero);
      expect(logs, hasLength(1)); // one log per open, not per refresh
      open.value = false;
      tracks.value++;
      await Future<void>.delayed(Duration.zero);
      expect(collector.pending, hasLength(3));
      expect(controller.snapshot, isNull);
      open.value = true;
      await Future<void>.delayed(Duration.zero);
      collector.pending[3].complete(current);
      await Future<void>.delayed(Duration.zero);
      expect(logs, hasLength(2));
      controller.dispose();
      open.dispose();
      media.dispose();
      tracks.dispose();
    },
  );

  test('close and dispose invalidate in-flight passes', () async {
    final ValueNotifier<bool> open = ValueNotifier<bool>(true);
    final ControlledCollector collector = ControlledCollector();
    final InfoController controller = InfoController(
      open: open,
      changes: <Listenable>[],
      context: () => const InfoContext(path: 'a'),
      collector: collector,
    );
    int notifications = 0;
    controller.addListener(() => notifications++);
    await Future<void>.delayed(Duration.zero);
    open.value = false;
    final int before = notifications;
    collector.pending.single.complete(
      const InfoSnapshot(<String, List<InfoRow>>{}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifications, before);
    expect(controller.snapshot, isNull);
    open.value = true;
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    collector.pending.last.complete(
      const InfoSnapshot(<String, List<InfoRow>>{}),
    );
    await Future<void>.delayed(Duration.zero);
    open.dispose();
  });
}
