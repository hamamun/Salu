import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/sub_delay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The subtitle-sync store and the offset's one spelling (cc.md D19,
/// owner 2026-09-13).
///
/// These are the guarantees the panel's sync row and the Z/X keys
/// silently depend on: the number the viewer drags must be the number
/// that comes back on the next launch (or every restart re-breaks a file
/// they already fixed), putting a file back in sync must DELETE the
/// memory rather than store a zero, and a stream must never carry one —
/// a live stream's delay is the stream's business.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final SubDelayService store = SubDelayService.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await store.load();
  });

  group('formatSubDelay — the one spelling', () {
    test('zero is bare, positive and negative carry their sign', () {
      expect(formatSubDelay(0), '0.0 s');
      expect(formatSubDelay(0.4), '+0.4 s');
      expect(formatSubDelay(-1.0), '-1.0 s');
      expect(formatSubDelay(5.0), '+5.0 s');
      expect(formatSubDelay(-5.0), '-5.0 s');
    });

    test('one decimal is the step, so the label never over-claims', () {
      expect(formatSubDelay(0.1), '+0.1 s');
      expect(formatSubDelay(2.3), '+2.3 s');
    });
  });

  group('SubDelayService — per-file memory', () {
    test('what is written is what comes back, in milliseconds', () {
      const String path = r'C:\Videos\Show.S01E01.mkv';
      store.update(path, const Duration(milliseconds: 400));
      expect(store.savedOffsetFor(path), const Duration(milliseconds: 400));

      store.update(path, const Duration(milliseconds: -1200));
      expect(store.savedOffsetFor(path), const Duration(milliseconds: -1200));
    });

    test('back in sync DELETES the memory (the keep rule)', () {
      const String path = r'C:\Videos\Other.mkv';
      store.update(path, const Duration(milliseconds: 700));
      expect(store.savedOffsetFor(path), const Duration(milliseconds: 700));

      store.update(path, Duration.zero);
      expect(store.savedOffsetFor(path), Duration.zero);
    });

    test('a file nobody touched starts in sync', () {
      expect(store.savedOffsetFor(r'C:\Videos\Never.mkv'), Duration.zero);
    });

    test('streams never carry an offset', () {
      const String url = 'https://h/live/channel.m3u8';
      store.update(url, const Duration(milliseconds: 900));
      expect(store.savedOffsetFor(url), Duration.zero);
    });
  });
}
