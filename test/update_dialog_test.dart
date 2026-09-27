import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/settings_service.dart';
import 'package:salu/core/ui_lock.dart';
import 'package:salu/core/updater/github_updater_client.dart';
import 'package:salu/core/updater/nuget_client.dart';
import 'package:salu/core/updater/update_installer_windows.dart';
import 'package:salu/core/updater/updater_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/widgets/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'updater_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final UpdaterService svc = UpdaterService.instance;
  late Directory appDir;
  late Directory stagingDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService.instance.load();
    appDir = await Directory.systemTemp.createTemp('salu_dialog_app');
    // Staging INSIDE the sandbox: the swap script, its lock and its log are
    // derived from staging's parent, and a test that lets them land in the
    // machine's real %TEMP% leaves a lock behind for whoever runs next.
    stagingDir = Directory(p.join(appDir.path, 'salu_update'))..createSync();
    svc.debugResetForTest();
    svc.appDirOf = () => appDir.path;
    svc.stagingDirOf = () => stagingDir.path;
    // Widget tests run in a debug build, where the modal's promise is
    // different (updater.md §10) — the installed flow first, dev after.
    svc.devBuildProbe = () => false;

    svc.fetchText = (Uri url) async {
      if (url == NugetClient.indexUrl()) {
        return '{"versions": ["1.0.1210.39", "1.0.3065.39"]}';
      }
      if (url == GitHubUpdaterClient.latestReleaseUrl(
          GitHubUpdaterClient.mpvRepo)) {
        // No MPV download in this round: the installed build is current.
        return '{"tag_name":"20241021","assets":['
            '{"name":"mpv-dev-x86_64-20241021-git-aaaaaaa.7z",'
            '"browser_download_url":"https://gh.test/mpv.7z"}]}';
      }
      if (url == GitHubUpdaterClient.latestReleaseUrl(
          GitHubUpdaterClient.ytDlpRepo)) {
        return '{"tag_name":"2026.09.01","assets":['
            '{"name":"yt-dlp.exe",'
            '"browser_download_url":"https://gh.test/yt-dlp.exe"}]}';
      }
      throw UpdateFetchException('unexpected feed: $url');
    };
    svc.downloadToFile = (Uri url, File target,
        UpdateProgressCallback onProgress, bool Function() isCancelled) async {
      final List<int> bytes = url == NugetClient.packageUrlFor('1.0.3065.39')
          ? buildFakeNupkg(loaderDll: fakePeImage())
          : fakePeImage();
      target.writeAsBytesSync(bytes);
      onProgress(bytes.length, bytes.length);
    };
  });

  tearDown(() async {
    svc.debugResetForTest();
    if (appDir.existsSync()) await appDir.delete(recursive: true);
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(builder: (BuildContext context) {
          return TextButton(
            onPressed: () => unawaited(showUpdateDialog(context)),
            child: const Text('Open updater'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open updater'));
    await tester.pumpAndSettle();
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(ChromeLock.instance.isLocked, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> finishDownload(WidgetTester tester) async {
    // download() creates and writes real temp files. testWidgets' fake async
    // clock does not drive those OS completions: briefly yield to real I/O,
    // then pump the dialog until it leaves the progress screen.
    await tester.pump();
    for (int attempt = 0;
        attempt < 100 &&
            find.text('Downloading components...').evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Downloading components...'), findsNothing,
        reason: 'Dialog still shows: '
            '${tester.widgetList<Text>(find.byType(Text)).map((Text t) => t.data).toList()}');
  }

  testWidgets('a failed check reports a connection issue', (tester) async {
    svc.fetchText = (Uri url) async {
      throw const UpdateFetchException('offline');
    };
    await openDialog(tester);
    expect(find.textContaining('Unable to connect to update servers'),
        findsOneWidget);
    expect(find.textContaining('UpdateFetchException'), findsNothing);
    await closeDialog(tester);
  });

  testWidgets('a downloaded package that cannot be read does not blame the network',
      (tester) async {
    svc.downloadToFile = (Uri url, File target,
        UpdateProgressCallback onProgress, bool Function() isCancelled) async {
      target.writeAsBytesSync(buildFakeNupkg(includeLoader: false));
    };
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.textContaining('could not be prepared or verified'),
        findsOneWidget);
    expect(find.textContaining('WebView2Loader.dll'), findsOneWidget);
    expect(find.textContaining('Your current files were not changed'),
        findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('UpdateVerifyException'), findsNothing);
    expect(stagingDir.existsSync(), isFalse);
    expect(appDir.listSync(), isEmpty);
    await closeDialog(tester);
  });

  testWidgets('a download error shows a download message, not a raw exception',
      (tester) async {
    svc.downloadToFile = (Uri url, File target,
        UpdateProgressCallback onProgress, bool Function() isCancelled) async {
      throw const UpdateFetchException('HTTP 503 from secret URL');
    };
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.textContaining('Could not finish downloading'), findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('UpdateFetchException'), findsNothing);
    expect(find.textContaining('secret URL'), findsNothing);
    await closeDialog(tester);
  });

  testWidgets('an unexpected local error does not blame the network',
      (tester) async {
    svc.downloadToFile = (Uri url, File target,
        UpdateProgressCallback onProgress, bool Function() isCancelled) async {
      throw const FileSystemException('disk full');
    };
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.textContaining('could not be prepared or verified'),
        findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('FileSystemException'), findsNothing);
    await closeDialog(tester);
  });

  testWidgets('valid ZIP goes through staging; a refused installer is not a network error',
      (tester) async {
    svc.installer = UpdateInstallerWindows(
      scriptWriter: (String scriptPath) async {},
      spawner: (String scriptPath, Map<String, String> env) async => false,
      exitApp: () {},
      writability: (String targetDir) => true,
      lockReader: (String lockPath) => null,
    );
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.text('✓ Downloads Complete!'), findsOneWidget);
    expect(svc.stagedReady, isTrue);
    expect(File(p.join(stagingDir.path, 'WebView2Loader.dll')).readAsBytesSync(),
        fakePeImage());
    // The install root gained the staging folder and NOTHING else: no
    // component file, no versions.json, no swap leftovers.
    expect(
      appDir
          .listSync()
          .map((FileSystemEntity e) => p.basename(e.path))
          .toList(),
      <String>['salu_update'],
      reason: 'staging must not overwrite the running installation',
    );

    await tester.tap(find.text('Restart Now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start the updater'), findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(svc.stagedReady, isTrue,
        reason: 'a refused installer cannot discard verified payloads');
    await closeDialog(tester);
  });

  testWidgets('a dev build swaps without reopening itself, and says so',
      (tester) async {
    // updater.md §10: under `flutter run` / F5, a SALU that restarts itself
    // comes back OUTSIDE the debugger, and the next build copies the pinned
    // files over the swapped ones anyway. The modal says what will happen.
    svc.devBuildProbe = () => true;
    final List<String> relaunchFlags = <String>[];
    svc.installer = UpdateInstallerWindows(
      scriptWriter: (String scriptPath) async {},
      spawner: (String scriptPath, Map<String, String> env) async {
        relaunchFlags.add(env[swapEnvRelaunch] ?? '');
        return true;
      },
      exitApp: () {},
      writability: (String targetDir) => true,
      lockReader: (String lockPath) => null,
    );
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.textContaining('start it again from VS Code'), findsOneWidget);
    expect(find.textContaining('SALU will close, install the new files, and '
        'reopen by itself'), findsNothing);
    expect(find.text('Apply & Close'), findsOneWidget);
    expect(find.text('Restart Now'), findsNothing);

    await tester.tap(find.text('Apply & Close'));
    await tester.pumpAndSettle();
    expect(relaunchFlags, <String>['0'],
        reason: 'a debug build that reopens itself leaves the debugger behind '
            'for nothing');
    // The fake exitApp is a no-op, so the dialog is still up: close it the
    // honest way, or the ChromeLock stays held for the next test.
    await tester.tap(find.text('Restart Later'));
    await tester.pumpAndSettle();
    expect(ChromeLock.instance.isLocked, isFalse);
  });

  testWidgets('a swap that cannot land where SALU is installed is explained',
      (tester) async {
    // Not a network error, not a raw OS error, and SALU keeps running: the
    // message names the thing the user can actually do about it.
    svc.installer = UpdateInstallerWindows(
      scriptWriter: (String scriptPath) async {},
      spawner: (String scriptPath, Map<String, String> env) async => true,
      exitApp: () {},
      writability: (String targetDir) => false,
      lockReader: (String lockPath) => null,
    );
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);
    await tester.tap(find.text('Restart Now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start the updater'), findsOneWidget);
    expect(find.textContaining('Program Files'), findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(find.textContaining('UpdateSwapRefusedException'), findsNothing);
    expect(svc.stagedReady, isTrue,
        reason: 'a swap that was refused cannot discard verified payloads');
    await closeDialog(tester);
  });

}
