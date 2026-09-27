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
    stagingDir = await Directory.systemTemp.createTemp('salu_dialog_stage');
    svc.debugResetForTest();
    svc.appDirOf = () => appDir.path;
    svc.stagingDirOf = () => stagingDir.path;

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
    if (stagingDir.existsSync()) await stagingDir.delete(recursive: true);
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
      scriptWriter: (String staging) async => p.join(staging, updaterScriptName),
      spawner: (String script, int pid, String app, String staging,
              bool relaunch) async =>
          false,
      exitApp: () {},
    );
    await openDialog(tester);
    await tester.tap(find.text('Update'));
    await finishDownload(tester);

    expect(find.text('✓ Downloads Complete!'), findsOneWidget);
    expect(svc.stagedReady, isTrue);
    expect(File(p.join(stagingDir.path, 'WebView2Loader.dll')).readAsBytesSync(),
        fakePeImage());
    expect(appDir.listSync(), isEmpty,
        reason: 'staging must not overwrite the running installation');

    await tester.tap(find.text('Restart Now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start the updater'), findsOneWidget);
    expect(find.textContaining('Unable to connect'), findsNothing);
    expect(svc.stagedReady, isTrue,
        reason: 'a refused installer cannot discard verified payloads');
    await closeDialog(tester);
  });
}
