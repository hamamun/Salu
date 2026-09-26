import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/browser_service.dart';
import 'package:salu/core/remote/guarded_script.dart';
import 'package:salu/core/remote/web_media_poller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a timeout does not clear the guard or submit a second script',
      (WidgetTester tester) async {
    final Completer<Object?> hung = Completer<Object?>();
    var calls = 0;
    final GuardedBrowserScript guard = GuardedBrowserScript(
      execute: (String script) {
        calls++;
        return hung.future;
      },
    );

    final Future<Object?> first = guard.run(
      'find',
      timeout: const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(calls, 1);
    expect(guard.pending, 1);
    // The caller is released at the timeout. The guard is not.
    expect(await first, isNull);
    final Future<Object?> second = guard.run('read');
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, 1);

    hung.complete(true);
    await tester.pump();
    expect(await second, isTrue);
    expect(calls, 2);
    expect(guard.pending, 0);
  });

  test('a failed script does not block the next one', () async {
    var calls = 0;
    final GuardedBrowserScript guard = GuardedBrowserScript(
      execute: (String script) async {
        calls++;
        if (calls == 1) throw StateError('script failed');
        return 'ok';
      },
    );
    expect(await guard.run('a'), isNull);
    expect(await guard.run('b'), 'ok');
    expect(guard.pending, 0);
  });

  test('a generation change drops the result', () async {
    var generation = 1;
    final GuardedBrowserScript guard = GuardedBrowserScript(
      execute: (String script) async {
        generation = 2;
        return true;
      },
    );
    final Object? value = await guard.run(
      'find',
      generation: 1,
      generationOf: () => generation,
    );
    expect(value, isNull);
  });

  testWidgets('restarting the poller does not overlap reads',
      (WidgetTester tester) async {
    var inFlight = 0;
    var maxInFlight = 0;
    var applied = 0;
    var polling = true;
    final WebMediaPoller poller = WebMediaPoller(
      shouldPoll: () => polling,
      interval: const Duration(milliseconds: 15),
      generationOf: () => 1,
      read: () async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        inFlight--;
        return true;
      },
      apply: (Object? raw) {
        applied++;
      },
    );
    poller.start();
    poller.start();
    await tester.pump(const Duration(milliseconds: 20));
    expect(maxInFlight, 1);
    expect(poller.active, isTrue);
    await tester.pump(const Duration(milliseconds: 80));
    expect(maxInFlight, 1);
    expect(applied, greaterThan(0));
    polling = false;
    poller.stop();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a thrown read does not stop the loop', (WidgetTester tester) async {
    var calls = 0;
    final WebMediaPoller poller = WebMediaPoller(
      shouldPoll: () => true,
      interval: const Duration(milliseconds: 10),
      generationOf: () => 0,
      read: () async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return false;
      },
      apply: (Object? raw) {},
    );
    poller.start();
    await tester.pump(const Duration(milliseconds: 80));
    poller.stop();
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, greaterThan(1));
  });

  testWidgets('a restart during a read does not overlap or drop the result',
      (WidgetTester tester) async {
    final Completer<Object?> gate = Completer<Object?>();
    var calls = 0;
    var applied = 0;
    final WebMediaPoller poller = WebMediaPoller(
      shouldPoll: () => true,
      interval: const Duration(milliseconds: 500),
      generationOf: () => 1,
      read: () async {
        calls++;
        return gate.future;
      },
      apply: (Object? raw) {
        applied++;
      },
    );
    poller.start();
    await tester.pump();
    expect(calls, 1);
    poller.start();
    await tester.pump();
    expect(calls, 1);
    gate.complete(true);
    await tester.pump();
    expect(applied, 1);
    poller.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  test('navigation bumps the media generation; a title refresh does not', () {
    final BrowserService browser = BrowserService.instance;
    final int start = browser.mediaGeneration;
    browser.noteMediaSurface(tabId: 3, url: 'https://a.example/watch');
    expect(browser.mediaGeneration, start + 1);
    final int bound = browser.mediaGeneration;
    browser.noteMediaSurface(tabId: 3, url: 'https://a.example/watch');
    expect(browser.mediaGeneration, bound);
    browser.noteMediaSurface(tabId: 3, url: 'https://a.example/other');
    expect(browser.mediaGeneration, bound + 1);
    browser.detachMediaSurface();
    expect(browser.mediaGeneration, bound + 2);
  });
}
