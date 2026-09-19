import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The download log (web.md · Downloads): the engine's own reports —
/// start, progress, completion — turned into the rows the badge counts
/// and the shelf shows. Nothing here touches the plugin: `WebTab` hands
/// the service plain values, which is exactly what these tests do.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final WebDownloadService svc = WebDownloadService.instance;
  const String file = r'C:\Users\me\Downloads\film.mp4';
  const String url = 'https://cdn.test/film.mp4';

  DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    svc.debugResetForTest();
    await svc.load();
  });

  // The stale sweep arms a periodic timer while anything travels; never
  // leave one behind for the next test (or the runner).
  tearDown(() => svc.debugResetForTest());

  group('one download, start to finish', () {
    test('a start report opens a running row and lights the badge', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 0, total: 1000, at: at(1000));

      expect(svc.items.value, hasLength(1));
      expect(svc.items.value.first.state, WebDownloadState.running);
      expect(svc.items.value.first.startedMs, 1000);
      expect(svc.running.value, 1);
      expect(svc.unseen.value, 0);
      expect(svc.hasBadge, isTrue);
      expect(svc.items.value.first.fileName, 'film.mp4');
      expect(svc.items.value.first.progress, 0.0);
    });

    test('completion closes the row, drops the count, raises the unseen',
        () async {
      final List<WebDownloadItem> seen = <WebDownloadItem>[];
      final StreamSubscription<WebDownloadItem> sub =
          svc.finished.listen(seen.add);

      svc.report(WebDownloadState.running,
          url: url, path: file, received: 0, total: 1000, at: at(1000));
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 1000, total: 1000, at: at(5000));

      expect(svc.items.value.single.state, WebDownloadState.completed);
      expect(svc.items.value.single.endedMs, 5000);
      expect(svc.running.value, 0);
      // The badge stays: a finish nobody has looked at is its whole point.
      expect(svc.unseen.value, 1);
      expect(svc.hasBadge, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      expect(seen.single.fileName, 'film.mp4');
      expect(seen.single.isCompleted, isTrue);
      await sub.cancel();
    });
  });

  group('the progress throttle', () {
    test('reports inside the window collapse; the last byte never does', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 0, total: 1000, at: at(0));

      // 50 ms after the start — inside the 200 ms window: dropped.
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 100, total: 1000, at: at(50));
      expect(svc.items.value.single.received, 0);

      // Past the window: lands.
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 400, total: 1000, at: at(260));
      expect(svc.items.value.single.received, 400);

      // Inside the window again, but this one COMPLETES the row — a
      // finished download is never swallowed by the throttle.
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 1000, total: 1000, at: at(300));
      expect(svc.items.value.single.received, 1000);
      expect(svc.items.value.single.progress, 1.0);
    });
  });

  group('the badge and the open shelf', () {
    test('an open shelf has seen everything, and keeps seeing', () {
      svc.setShelfOpen(true);
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 10, total: 10, at: at(0));
      expect(svc.unseen.value, 0);
      expect(svc.hasBadge, isFalse, reason: 'no running, nothing unseen');
    });

    test('a closed shelf lets the next finish raise the unseen count', () {
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 10, total: 10, at: at(0));
      svc.report(WebDownloadState.completed,
          url: 'https://cdn.test/two.mp4',
          path: r'C:\Users\me\Downloads\two.mp4',
          received: 10,
          total: 10,
          at: at(1));
      expect(svc.unseen.value, 2);

      svc.setShelfOpen(true); // the badge's tap
      expect(svc.unseen.value, 0);
      expect(svc.hasBadge, isFalse);
    });
  });

  group('rows and keys', () {
    test('the engine path is the key, so one URL can hold two files', () {
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 1, total: 1, at: at(0));
      svc.report(WebDownloadState.completed,
          url: url,
          path: r'C:\Users\me\Downloads\film (1).mp4',
          received: 1,
          total: 1,
          at: at(1));

      expect(svc.items.value, hasLength(2));
      // Newest first.
      expect(svc.items.value.first.fileName, 'film (1).mp4');
    });

    test('remove drops one row; clearFinished keeps the travellers', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 5, total: 10, at: at(0));
      svc.report(WebDownloadState.completed,
          url: 'https://cdn.test/two.mp4',
          path: r'C:\Users\me\Downloads\two.mp4',
          received: 1,
          total: 1,
          at: at(1));

      svc.clearFinished();
      expect(svc.items.value, hasLength(1));
      expect(svc.items.value.single.isRunning, isTrue);

      svc.remove(file);
      expect(svc.items.value, isEmpty);
      expect(svc.running.value, 0);
      expect(svc.hasBadge, isFalse);
    });

    test('clear empties the log — the badge goes with it', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 5, total: 10, at: at(0));
      svc.report(WebDownloadState.completed,
          url: 'https://cdn.test/two.mp4',
          path: r'C:\Users\me\Downloads\two.mp4',
          received: 1,
          total: 1,
          at: at(1));

      svc.clear();
      expect(svc.items.value, isEmpty);
      expect(svc.running.value, 0);
      expect(svc.unseen.value, 0);
      expect(svc.hasBadge, isFalse);
    });
  });

  group('persistence', () {
    test('finished rows reach disk; a running row never does', () async {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 5, total: 10, at: at(0));
      svc.report(WebDownloadState.completed,
          url: 'https://cdn.test/two.mp4',
          path: r'C:\Users\me\Downloads\two.mp4',
          received: 7,
          total: 7,
          at: at(1));
      await svc.flush();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(WebDownloadService.prefsKey);
      expect(raw, isNotNull);
      final List<dynamic> rows = jsonDecode(raw!) as List<dynamic>;
      expect(rows, hasLength(1), reason: 'the traveller is not a record');
      expect((rows.single as Map<String, dynamic>)['path'],
          r'C:\Users\me\Downloads\two.mp4');
    });

    test('a cold start brings the finished rows back, seen and quiet',
        () async {
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 9, total: 9, at: at(42));
      await svc.flush();

      svc.debugResetForTest();
      await svc.load();

      expect(svc.items.value, hasLength(1));
      expect(svc.items.value.single.fileName, 'film.mp4');
      expect(svc.items.value.single.isCompleted, isTrue);
      expect(svc.items.value.single.startedMs, 42);
      expect(svc.unseen.value, 0, reason: 'an old row is not news');
      expect(svc.hasBadge, isFalse);
    });

    test('an empty log leaves no key behind', () async {
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 1, total: 1, at: at(0));
      await svc.flush();
      svc.clear();
      await svc.flush();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WebDownloadService.prefsKey), isNull);
    });
  });

  group('the stale sweep', () {
    test('a motionless traveller is called interrupted past the window', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 100, total: 100000, at: at(0));
      final WebDownloadItem row = svc.items.value.single;
      final int grace = WebDownloadService.staleAfter.inMilliseconds;

      // Exactly at the window: still alive. One millisecond past: called.
      expect(WebDownloadService.isStale(row, at(grace)), isFalse);
      expect(WebDownloadService.isStale(row, at(grace + 1)), isTrue);
    });

    test('any real report resets the clock', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 1, total: 9, at: at(0));
      final int grace = WebDownloadService.staleAfter.inMilliseconds;
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 2, total: 9, at: at(grace));

      final WebDownloadItem row = svc.items.value.single;
      expect(row.lastEventMs, grace);
      // A byte arrived at `grace`, so the row is young again.
      expect(WebDownloadService.isStale(row, at(grace + 1)), isFalse);
      expect(WebDownloadService.isStale(row, at(grace * 2 + 1)), isTrue);
    });

    test('a finished row never ages', () {
      svc.report(WebDownloadState.completed,
          url: url, path: file, received: 9, total: 9, at: at(0));
      final WebDownloadItem row = svc.items.value.single;
      expect(WebDownloadService.isStale(row, at(999999999)), isFalse);
    });
  });

  group('the row model', () {
    test('no size from the server means no percentage to fake', () {
      svc.report(WebDownloadState.running,
          url: url, path: file, received: 512, total: 0, at: at(0));
      expect(svc.items.value.single.progress, isNull);
      expect(svc.items.value.single.total, 0);
    });

    test('the name falls back to the URL, query and fragment stripped', () {
      const WebDownloadItem item = WebDownloadItem(
        key: 'https://cdn.test/a/b.zip?token=secret#x',
        url: 'https://cdn.test/a/b.zip?token=secret#x',
        path: '',
        received: 0,
        total: 0,
        state: WebDownloadState.running,
        startedMs: 0,
      );
      expect(item.fileName, 'b.zip');
    });

    test('a row persisted mid-flight comes back failed, never spinning', () {
      final WebDownloadItem? revived = WebDownloadItem.fromJson(<String, Object?>{
        'url': url,
        'path': file,
        'received': 3,
        'total': 9,
        'state': WebDownloadState.running.index,
        'at': 7,
      });
      expect(revived, isNotNull);
      expect(revived!.state, WebDownloadState.failed);
      expect(revived.fileName, 'film.mp4');
    });

    test('a row with no path is not a row', () {
      expect(
        WebDownloadItem.fromJson(<String, Object?>{
          'url': url,
          'path': '',
          'at': 1,
          'state': WebDownloadState.completed.index,
        }),
        isNull,
      );
      expect(WebDownloadItem.fromJson('nope'), isNull);
    });
  });
}
