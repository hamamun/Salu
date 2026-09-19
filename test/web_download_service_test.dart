import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
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

  group('where a download lands (the Save As prompt)', () {
    // Forward-slash paths on purpose: `package:path` answers the same for
    // these on Windows and everywhere else, so these tests are not a
    // platform of their own the way the row-model ones above are.
    const String suggested = '/downloads/film.mp4';
    const String chosen = '/elsewhere/film.mp4';

    final List<String> names = <String>[];
    final List<String?> dirs = <String?>[];
    int opened = 0;

    setUp(() async {
      names.clear();
      dirs.clear();
      opened = 0;
      await SettingsService.instance.setWebAskDownloadLocation(true);
      await SettingsService.instance.setWebDownloadFolder('');
    });

    tearDown(() async {
      WebDownloadService.debugSaveLocationPicker = null;
      WebDownloadService.debugFolderPicker = null;
      await SettingsService.instance.setWebAskDownloadLocation(true);
      await SettingsService.instance.setWebDownloadFolder('');
    });

    /// A seam that records the question and answers [answer].
    void answerWith(String? answer) {
      WebDownloadService.debugSaveLocationPicker =
          ({required String suggestedName, String? initialDirectory}) async {
        opened++;
        names.add(suggestedName);
        dirs.add(initialDirectory);
        return answer;
      };
    }

    test('the place chosen becomes the answer, name and folder pre-filled',
        () async {
      answerWith(chosen);

      final WebSaveAnswer answer = await svc.askWhereToSave(suggested);

      expect(answer.kind, WebSaveKind.save);
      expect(answer.path, chosen);
      expect(names, <String>['film.mp4']);
      // No folder of the viewer's own, so the dialog starts where the
      // engine suggested — Windows' own Downloads, relocated one included,
      // which is a better guess than any SALU could compute.
      expect(dirs, <String?>['/downloads']);
    });

    test('walking away from the dialog cancels, and nothing is logged',
        () async {
      answerWith(null);

      final WebSaveAnswer answer = await svc.askWhereToSave(suggested);

      expect(answer.isCancel, isTrue);
      expect(answer.path, isNull);
      expect(svc.items.value, isEmpty,
          reason: 'a refused download is not a failed one');
      expect(svc.hasBadge, isFalse);
    });

    test('asking off opens no dialog at all — the engine path stands',
        () async {
      await SettingsService.instance.setWebAskDownloadLocation(false);
      answerWith(chosen);

      final WebSaveAnswer answer = await svc.askWhereToSave(suggested);

      expect(answer.kind, WebSaveKind.engineDefault);
      expect(opened, 0);
    });

    test("the viewer's own folder is where the question starts", () async {
      await SettingsService.instance.setWebDownloadFolder('/mine/downloads');
      answerWith(chosen);

      await svc.askWhereToSave(suggested);

      expect(dirs, <String?>['/mine/downloads']);
      // The shelf's footer follows the same setting.
      expect(WebDownloadService.downloadsFolder(), '/mine/downloads');
    });

    test('a picker that throws never costs the viewer their file', () async {
      WebDownloadService.debugSaveLocationPicker =
          ({required String suggestedName, String? initialDirectory}) async {
        opened++;
        throw StateError('no window here');
      };

      final WebSaveAnswer answer = await svc.askWhereToSave(suggested);

      expect(answer.kind, WebSaveKind.engineDefault);
      expect(opened, 1);
    });

    test('three downloads at once ask one at a time', () async {
      final List<Completer<String?>> gates = <Completer<String?>>[
        Completer<String?>(),
        Completer<String?>(),
        Completer<String?>(),
      ];
      WebDownloadService.debugSaveLocationPicker =
          ({required String suggestedName, String? initialDirectory}) {
        names.add(suggestedName);
        return gates[opened++].future;
      };

      final Future<WebSaveAnswer> a = svc.askWhereToSave('/downloads/a.mp4');
      final Future<WebSaveAnswer> b = svc.askWhereToSave('/downloads/b.mp4');
      final Future<WebSaveAnswer> c = svc.askWhereToSave('/downloads/c.mp4');
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1, reason: 'one dialog at a time, never three stacked');

      gates[0].complete('/mine/a.mp4');
      await a;
      await Future<void>.delayed(Duration.zero);
      expect(opened, 2);

      gates[1].complete(null);
      await b;
      await Future<void>.delayed(Duration.zero);
      expect(opened, 3);

      gates[2].complete('/mine/c.mp4');

      expect((await a).path, '/mine/a.mp4');
      expect((await b).isCancel, isTrue);
      expect((await c).path, '/mine/c.mp4');
      expect(names, <String>['a.mp4', 'b.mp4', 'c.mp4']);
    });

    test('the switch flipped while a prompt waits in the queue wins',
        () async {
      final Completer<String?> gate = Completer<String?>();
      WebDownloadService.debugSaveLocationPicker =
          ({required String suggestedName, String? initialDirectory}) {
        opened++;
        return gate.future;
      };

      final Future<WebSaveAnswer> first =
          svc.askWhereToSave('/downloads/a.mp4');
      final Future<WebSaveAnswer> second =
          svc.askWhereToSave('/downloads/b.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(opened, 1);

      await SettingsService.instance.setWebAskDownloadLocation(false);
      gate.complete('/mine/a.mp4');

      expect((await first).path, '/mine/a.mp4');
      // The queued one reads the switch when its turn comes, not when it
      // was asked — so it never opens a dialog.
      expect((await second).kind, WebSaveKind.engineDefault);
      expect(opened, 1);
    });

    test('the folder picker moves the setting — a Cancel does not', () async {
      WebDownloadService.debugFolderPicker = () async => '/mine/downloads';
      expect(await WebDownloadService.pickDownloadFolder(), isTrue);
      expect(SettingsService.instance.webDownloadFolder.value,
          '/mine/downloads');

      WebDownloadService.debugFolderPicker = () async => null;
      expect(await WebDownloadService.pickDownloadFolder(), isFalse);
      expect(SettingsService.instance.webDownloadFolder.value,
          '/mine/downloads',
          reason: 'walking away leaves the folder in force');

      // Back to Windows' own — an empty setting, never a guessed path.
      await SettingsService.instance.setWebDownloadFolder('');
      expect(SettingsService.instance.webDownloadFolder.value, '');
    });
  });
}
