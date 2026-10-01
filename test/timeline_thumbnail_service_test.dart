import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/timeline_thumbnail_service.dart';

/// A controllable fake decoder: records every (path, second) it is asked
/// for, waits [latency] per call, can fail, and tracks the highest number
/// of calls running at once (the serial-worker proof).
class FakeExtractor {
  FakeExtractor({this.latency = Duration.zero, this.fail = false, this.gate});

  Duration latency;
  bool fail;

  /// When set, the FIRST call waits on this completer — a hung decode.
  Completer<void>? gate;

  final List<(String, int)> calls = <(String, int)>[];
  int inFlight = 0;
  int maxInFlight = 0;

  Future<Uint8List?> invoke(String path, int timeMs) async {
    calls.add((path, timeMs));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final Completer<void>? g = gate;
    gate = null; // only the first call hangs
    if (g != null) await g.future;
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    inFlight--;
    if (fail) throw StateError('undecodable');
    return Uint8List.fromList(<int>[
      path.length % 251,
      (timeMs ~/ 1000) % 251,
    ]);
  }
}

void main() {
  const String path = r'C:\media\clip.mp4';
  const String pathB = r'C:\media\other.mp4';
  const String remote = 'https://example.com/stream.m3u8';

  TimelineThumbnailService service(
    FakeExtractor x, {
    Duration stripStartDelay = Duration.zero,
    Duration pacing = Duration.zero,
    int maxCacheEntries = 192,
    int maxFineQueue = 24,
  }) {
    return TimelineThumbnailService(
      extractor: x.invoke,
      stripStartDelay: stripStartDelay,
      pacing: pacing,
      maxCacheEntries: maxCacheEntries,
      maxFineQueue: maxFineQueue,
    );
  }

  group('computeStripTimes', () {
    test('one second apart while within the frame cap', () {
      final List<int> times = TimelineThumbnailService.computeStripTimes(
        const Duration(seconds: 60),
      );
      expect(times, hasLength(60));
      expect(times.first, 0);
      expect(times.last, 59000);
    });

    test('a whole-second stride beyond the cap, final second included', () {
      final List<int> times =
          TimelineThumbnailService.computeStripTimes(const Duration(hours: 1));
      // 3600000 ~/ 120 = 30000 ms stride → 120 grid seconds + 3599000.
      expect(times, hasLength(121));
      expect(times.first, 0);
      expect(times[1], 30000);
      expect(times.last, 3599000);
    });

    test('every grid second is a whole-second mark', () {
      for (final int t
          in TimelineThumbnailService.computeStripTimes(
            const Duration(minutes: 10),
          )) {
        expect(t % 1000, 0);
      }
    });

    test('zero duration is an empty grid', () {
      expect(
        TimelineThumbnailService.computeStripTimes(Duration.zero),
        isEmpty,
      );
    });
  });

  group('strip lane', () {
    test('decodes the grid in the background, one frame per grid second',
        () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 5));
      await pumpEventQueue();
      expect(x.calls.map((c) => c.$2), <int>[0, 1000, 2000, 3000, 4000]);
      expect(s.lookup(path, 2000), isNotNull);
    });

    test('starts only after stripStartDelay', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x,
          stripStartDelay: const Duration(milliseconds: 50));
      s.ensureStrip(path, const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(x.calls, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(x.calls, hasLength(5));
    });

    test('re-arming the same video is a no-op', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 5));
      await pumpEventQueue();
      final int before = x.calls.length;
      s.ensureStrip(path, const Duration(seconds: 5));
      await pumpEventQueue();
      expect(x.calls.length, before);
    });

    test('a new video cancels the previous grid entirely', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 300));
      s.ensureStrip(pathB, const Duration(seconds: 5));
      await pumpEventQueue();
      expect(x.calls, isNotEmpty);
      expect(x.calls.every((c) => c.$1 == pathB), isTrue);
    });

    test('release stops an armed strip', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 5));
      s.release();
      await pumpEventQueue();
      expect(x.calls, isEmpty);
    });

    test('a re-arm during a slow decode still runs the new grid', () async {
      final FakeExtractor x = FakeExtractor(gate: Completer<void>());
      final TimelineThumbnailService s = service(x,
          stripStartDelay: const Duration(milliseconds: 50));
      s.ensureStrip(path, const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Grid A is armed; its first decode is in flight and hung.
      expect(x.calls, hasLength(1));
      s.ensureStrip(pathB, const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Grid B has fired its timer while A's decode is still in flight —
      // B's jobs are queued but must not be stranded when A bails.
      expect(x.calls, hasLength(1));
      x.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(x.calls.where((c) => c.$1 == pathB), hasLength(5));
    });

    test('remote paths never enter a queue', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(remote, const Duration(seconds: 60));
      s.requestFine(remote, 1000);
      await pumpEventQueue();
      expect(x.calls, isEmpty);
    });
  });

  group('fine lane (hover)', () {
    test('runs before the strip grid', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 200));
      // 123000 is not on the grid (stride 2000 for a 200 s video).
      s.requestFine(path, 123000);
      await pumpEventQueue();
      expect(x.calls.first, (path, 123000));
    });

    test('a second the grid already covers is not decoded twice',
        () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 5));
      await pumpEventQueue();
      final int before = x.calls.length;
      s.requestFine(path, 1000); // on the grid
      await pumpEventQueue();
      expect(x.calls.length, before);
      expect(s.lookup(path, 1000), isNotNull);
    });

    test('the same second is queued only once while in flight', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      s.requestFine(path, 3000);
      s.requestFine(path, 3000);
      s.requestFine(path, 3000);
      await pumpEventQueue();
      expect(x.calls, <(String, int)>[(path, 3000)]);
    });

    test('onFrame notifies every decoded frame', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x);
      final List<(String, int, Uint8List)> frames =
          <(String, int, Uint8List)>[];
      s.onFrame = (String p, int t, Uint8List b) => frames.add((p, t, b));
      s.requestFine(path, 7000);
      await pumpEventQueue();
      expect(frames, hasLength(1));
      expect(frames.single.$1, path);
      expect(frames.single.$2, 7000);
    });
  });

  group('safety', () {
    test('one decode in flight, ever', () async {
      final FakeExtractor x = FakeExtractor(
        latency: const Duration(milliseconds: 10),
      );
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 4));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(x.calls.length, 4);
      expect(x.maxInFlight, 1);
    });

    test('a file that cannot decode is marked dead after a few failures',
        () async {
      final FakeExtractor x = FakeExtractor(fail: true);
      final TimelineThumbnailService s = service(x);
      s.ensureStrip(path, const Duration(seconds: 50));
      await pumpEventQueue();
      expect(x.calls.length, 3);
      s.requestFine(path, 42000); // dead path — ignored
      await pumpEventQueue();
      expect(x.calls.length, 3);
    });

    test('the LRU cap evicts the oldest frames', () async {
      final FakeExtractor x = FakeExtractor();
      final TimelineThumbnailService s = service(x, maxCacheEntries: 4);
      for (int i = 0; i < 5; i++) {
        s.requestFine(path, i * 1000);
        await pumpEventQueue();
      }
      expect(s.lookup(path, 0), isNull);
      expect(s.lookup(path, 4000), isNotNull);
    });
  });
}
