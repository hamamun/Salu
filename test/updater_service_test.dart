import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/settings_service.dart';
import 'package:salu/core/updater/update_installer_windows.dart';
import 'package:salu/core/updater/update_manifest.dart';
import 'package:salu/core/updater/updater_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'updater_test_support.dart';

/// The coordinator (updater.md §3): check → compare → download & stage →
/// hand off to the swap script. Every network and OS touch is a seam, so
/// these tests run the real pipeline against canned feeds and a real
/// staging directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final UpdaterService svc = UpdaterService.instance;

  late Directory root;
  late Directory staging;

  // ── Canned feeds ───────────────────────────────────────────────────────
  const String nugetIndex =
      '{"versions": ["1.0.864.35", "1.0.1210.39", "1.0.3065.39-rc", "1.0.3065.39"]}';
  const String mpvRelease = '''
  {
    "tag_name": "20250101",
    "assets": [
      {"name": "mpv-dev-x86_64-v3-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-x86_64-v3.7z", "size": 1},
      {"name": "mpv-dev-x86_64-20250101-git-aaaaaaa.7z",
       "browser_download_url": "https://gh.test/mpv-dev-x86_64.7z", "size": 1}
    ]
  }''';
  const String ytDlpRelease = '''
  {
    "tag_name": "2026.09.01",
    "assets": [
      {"name": "yt-dlp.exe",
       "browser_download_url": "https://gh.test/yt-dlp.exe", "size": 10},
      {"name": "yt-dlp_x86.exe",
       "browser_download_url": "https://gh.test/yt-dlp_x86.exe", "size": 1},
      {"name": "SHA2-256SUMS",
       "browser_download_url": "https://gh.test/SHA2-256SUMS", "size": 1}
    ]
  }''';

  const String nugetIndexUrl =
      'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json';
  const String mpvFeedUrl =
      'https://api.github.com/repos/media-kit/libmpv-win32-video-cmake/releases/latest';
  const String ytDlpFeedUrl =
      'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';

  /// The payloads the download seam serves per URL.
  late Map<String, List<int>> payloads;
  late String sumsText;

  void installFeeds({bool broken = false}) {
    svc.fetchText = (Uri url) async {
      switch (url.toString()) {
        case nugetIndexUrl:
          if (broken) throw const UpdateFetchException('offline');
          return nugetIndex;
        case mpvFeedUrl:
          if (broken) throw const UpdateFetchException('offline');
          return mpvRelease;
        case ytDlpFeedUrl:
          if (broken) throw const UpdateFetchException('offline');
          return ytDlpRelease;
        case 'https://gh.test/SHA2-256SUMS':
          return sumsText;
        default:
          throw UpdateFetchException('unexpected fetch: $url');
      }
    };
    svc.downloadToFile = (
      Uri url,
      File target,
      UpdateProgressCallback onProgress,
      bool Function() isCancelled,
    ) async {
      final List<int>? bytes = payloads[url.toString()];
      if (bytes == null) throw UpdateFetchException('unexpected download: $url');
      target.writeAsBytesSync(bytes);
      onProgress(bytes.length, bytes.length);
    };
    svc.extractArchive = (File archive, Directory dest) async {
      dest.createSync(recursive: true);
      File(p.join(dest.path, 'libmpv-2.dll')).writeAsBytesSync(fakePeImage());
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService.instance.load();
    // load() only overwrites the cadence when a key was stored — pin the
    // factory default so one test's setting never bleeds into the next.
    SettingsService.instance.updateCheckFrequency.value =
        UpdateCheckFrequency.weekly;
    SettingsService.instance.lastUpdateCheckTime.value = 0;
    root = await Directory.systemTemp.createTemp('salu_upd_app');
    // Staging lives INSIDE the sandbox on purpose: the swap script, its lock
    // and its log are derived from staging's parent, and a test that lets
    // them land in the real %TEMP% leaks a lock the next test then trips on.
    staging = Directory(p.join(root.path, 'salu_update'))..createSync();
    svc.debugResetForTest();
    svc.appDirOf = () => root.path;
    svc.stagingDirOf = () => staging.path;
    svc.executableOf = () => p.join(root.path, 'salu.exe');
    // The installed behaviour: SALU reopens itself. The dev-build flip is a
    // separate test below.
    svc.devBuildProbe = () => false;

    payloads = <String, List<int>>{
      'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/'
          '1.0.3065.39/microsoft.web.webview2.1.0.3065.39.nupkg':
          buildFakeNupkg(loaderDll: fakePeImage()),
      'https://gh.test/mpv-dev-x86_64.7z': asciiBytes('fake-7z'),
      'https://gh.test/yt-dlp.exe': fakePeImage(),
    };
    sumsText = '';
    installFeeds();
  });

  tearDown(() async {
    svc.debugResetForTest();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  File versionsFile() => File(p.join(root.path, 'versions.json'));

  group('local versions', () {
    test('shipped baselines stand in before any store exists', () {
      expect(svc.installedVersionOf(UpdateComponent.webView2Loader),
          '1.0.1210.39');
      expect(svc.installedVersionOf(UpdateComponent.mpvEngine), '20241021');
      expect(svc.installedVersionOf(UpdateComponent.ytDlp), isNull);
    });

    test('versions.json wins over the baselines', () {
      versionsFile().writeAsStringSync(const UpdateManifest(
        <UpdateComponent, String>{
          UpdateComponent.webView2Loader: '1.0.3065.39',
          UpdateComponent.ytDlp: '2026.09.01',
        },
      ).toJsonString());
      expect(svc.installedVersionOf(UpdateComponent.webView2Loader),
          '1.0.3065.39');
      expect(svc.installedVersionOf(UpdateComponent.mpvEngine), '20241021',
          reason: 'untouched components keep their baseline');
      expect(svc.installedVersionOf(UpdateComponent.ytDlp), '2026.09.01');
    });

    test('a corrupt store degrades to baselines, never throws', () {
      versionsFile().writeAsStringSync('{broken');
      expect(svc.installedVersionOf(UpdateComponent.webView2Loader),
          '1.0.1210.39');
    });
  });

  group('check', () {
    test('builds the three-row table and flags the upgrades', () async {
      final UpdateCheckResult result = await svc.check();
      expect(result.ok, isTrue);
      expect(result.components, hasLength(3));

      final ComponentStatus webview = result.components[0];
      expect(webview.component, UpdateComponent.webView2Loader);
      expect(webview.installed, '1.0.1210.39');
      expect(webview.latest, '1.0.3065.39');
      expect(webview.updateAvailable, isTrue);

      final ComponentStatus mpv = result.components[1];
      expect(mpv.component, UpdateComponent.mpvEngine);
      expect(mpv.installed, '20241021');
      expect(mpv.latest, '20250101');
      expect(mpv.updateAvailable, isTrue);
      expect(mpv.downloadUrl, 'https://gh.test/mpv-dev-x86_64.7z',
          reason: 'the plain x64 dev archive, never the v3 one');

      final ComponentStatus ytdlp = result.components[2];
      expect(ytdlp.component, UpdateComponent.ytDlp);
      expect(ytdlp.installed, isNull, reason: 'untracked until first update');
      expect(ytdlp.latest, '2026.09.01');
      expect(ytdlp.updateAvailable, isTrue);
      expect(ytdlp.checksumUrl, 'https://gh.test/SHA2-256SUMS');

      expect(result.hasUpdates, isTrue);
      expect(result.pendingUpdates, hasLength(3));
      expect(svc.updateAvailable.value, isTrue);
      expect(SettingsService.instance.lastUpdateCheckTime.value,
          greaterThan(0));
    });

    test('equal versions show the "(Current)" shape — no updates', () async {
      versionsFile().writeAsStringSync(const UpdateManifest(
        <UpdateComponent, String>{
          UpdateComponent.webView2Loader: '1.0.3065.39',
          UpdateComponent.mpvEngine: '20250101',
          UpdateComponent.ytDlp: '2026.09.01',
        },
      ).toJsonString());
      final UpdateCheckResult result = await svc.check();
      expect(result.ok, isTrue);
      expect(result.hasUpdates, isFalse);
      expect(result.pendingUpdates, isEmpty);
      expect(result.components.every((ComponentStatus c) => !c.updateAvailable),
          isTrue);
      expect(svc.updateAvailable.value, isFalse);
    });

    test('a local pin ahead of the feed is not an update', () async {
      versionsFile().writeAsStringSync(const UpdateManifest(
        <UpdateComponent, String>{
          UpdateComponent.mpvEngine: '20990101',
        },
      ).toJsonString());
      final UpdateCheckResult result = await svc.check();
      expect(result.components[1].updateAvailable, isFalse);
      expect(result.components[0].updateAvailable, isTrue,
          reason: 'webview2 still flags');
    });

    test('a failing feed is the quiet offline state — files untouched',
        () async {
      installFeeds(broken: true);
      final UpdateCheckResult result = await svc.check();
      expect(result.ok, isFalse);
      expect(result.components, isEmpty);
      expect(result.hasUpdates, isFalse);
      expect(SettingsService.instance.lastUpdateCheckTime.value, 0,
          reason: 'a failed round never stamps "Last checked"');
    });

    test('rememberTime: false leaves the stamp alone', () async {
      await svc.check(rememberTime: false);
      expect(SettingsService.instance.lastUpdateCheckTime.value, 0);
    });
  });

  group('scheduled checks (updater.md §7)', () {
    test('due when never checked, or past the cadence', () async {
      final DateTime now = DateTime(2026, 9, 26, 12);
      svc.now = () => now;

      expect(svc.isCheckDue, isTrue, reason: 'never checked');

      await SettingsService.instance.setLastUpdateCheckTime(
          now.subtract(const Duration(days: 8)));
      expect(svc.isCheckDue, isTrue, reason: 'weekly cadence elapsed');

      await SettingsService.instance
          .setLastUpdateCheckTime(now.subtract(const Duration(days: 1)));
      expect(svc.isCheckDue, isFalse, reason: 'inside the weekly window');
    });

    test('Off means only "Check now"', () async {
      final DateTime now = DateTime(2026, 9, 26, 12);
      svc.now = () => now;
      await SettingsService.instance.setUpdateCheckFrequency(
          UpdateCheckFrequency.off);
      expect(svc.isCheckDue, isFalse, reason: 'even when never checked');

      await SettingsService.instance
          .setUpdateCheckFrequency(UpdateCheckFrequency.daily);
      await SettingsService.instance
          .setLastUpdateCheckTime(now.subtract(const Duration(hours: 25)));
      expect(svc.isCheckDue, isTrue, reason: 'daily cadence elapsed');
    });
  });

  group('download & stage', () {
    Future<UpdateManifest> stageAll({
      void Function(UpdateProgress progress)? onProgress,
      bool Function()? isCancelled,
    }) async {
      final UpdateCheckResult result = await svc.check();
      return svc.download(
        result.pendingUpdates,
        onProgress: onProgress,
        isCancelled: isCancelled ?? () => false,
      );
    }

    test('stages every payload plus the merged manifest', () async {
      final List<UpdateProgress> events = <UpdateProgress>[];
      final UpdateManifest staged = await stageAll(
        onProgress: events.add,
      );

      expect(File(p.join(staging.path, 'WebView2Loader.dll')).existsSync(),
          isTrue);
      expect(
          File(p.join(staging.path, 'libmpv-2.dll')).existsSync(), isTrue);
      expect(File(p.join(staging.path, 'yt-dlp.exe')).existsSync(), isTrue);
      expect(File(p.join(staging.path, 'manifest.json')).existsSync(), isTrue);

      // The staged bytes are the verified payloads, nothing else.
      expect(File(p.join(staging.path, 'WebView2Loader.dll')).readAsBytesSync(),
          fakePeImage());
      expect(File(p.join(staging.path, 'yt-dlp.exe')).readAsBytesSync(),
          fakePeImage());

      // Manifest = the FULL new version picture (updater.md §6 step 4).
      final UpdateManifest parsed = UpdateManifest.tryParse(
          File(p.join(staging.path, 'manifest.json')).readAsStringSync());
      expect(parsed.components[UpdateComponent.webView2Loader], '1.0.3065.39');
      expect(parsed.components[UpdateComponent.mpvEngine], '20250101');
      expect(parsed.components[UpdateComponent.ytDlp], '2026.09.01');
      expect(staged.components, parsed.components);

      // Progress reported per payload and overall (State 2C copy).
      expect(events.last.completed, 3);
      expect(events.last.overall, 3);
      expect(events.any((UpdateProgress e) => e.received > 0), isTrue);

      expect(svc.stagedReady, isTrue);
    });

    test('the manifest carries versions of components not being staged',
        () async {
      versionsFile().writeAsStringSync(const UpdateManifest(
        <UpdateComponent, String>{
          UpdateComponent.webView2Loader: '1.0.3065.39',
        },
      ).toJsonString());
      final UpdateCheckResult result = await svc.check();
      expect(result.pendingUpdates.map((ComponentUpdate u) => u.component),
          <UpdateComponent>[
            UpdateComponent.mpvEngine,
            UpdateComponent.ytDlp,
          ]);
      await svc.download(result.pendingUpdates, isCancelled: () => false);

      final UpdateManifest parsed = UpdateManifest.tryParse(
          File(p.join(staging.path, 'manifest.json')).readAsStringSync());
      expect(parsed.components[UpdateComponent.webView2Loader], '1.0.3065.39',
          reason: 'untouched component keeps its current version in the file');
      expect(parsed.components[UpdateComponent.mpvEngine], '20250101');
    });

    test('cancel mid-round aborts and purges staging (updater.md §8)',
        () async {
      bool cancelled = false;
      svc.downloadToFile = (
        Uri url,
        File target,
        UpdateProgressCallback onProgress,
        bool Function() isCancelled,
      ) async {
        target.writeAsBytesSync(fakePeImage());
        onProgress(10, 10);
        // The viewer clicks Cancel right after the first payload lands.
        cancelled = true;
      };
      final UpdateCheckResult result = await svc.check();
      await expectLater(
        svc.download(result.pendingUpdates, isCancelled: () => cancelled),
        throwsA(isA<UpdateCancelledException>()),
      );
      expect(staging.existsSync(), isFalse,
          reason: 'a cancelled round leaves nothing staged');
    });

    test('a checksum mismatch refuses yt-dlp (updater.md §3 · integrity)',
        () async {
      sumsText =
          '${List<String>.filled(32, 'ff').join()} *yt-dlp.exe'; // wrong on purpose
      final UpdateCheckResult result = await svc.check();
      await expectLater(
        svc.download(result.pendingUpdates, isCancelled: () => false),
        throwsA(isA<UpdateVerifyException>()),
      );
      expect(staging.existsSync(), isFalse);
    });

    test('a matching checksum lets the payload through', () async {
      sumsText = '${sha256HexOf(fakePeImage())} *yt-dlp.exe';
      final UpdateCheckResult result = await svc.check();
      await svc.download(result.pendingUpdates, isCancelled: () => false);
      expect(File(p.join(staging.path, 'yt-dlp.exe')).existsSync(), isTrue);
      expect(svc.stagedReady, isTrue);
    });

    test('the x64 guard refuses a 32-bit WebView2Loader (updater.md §9)',
        () async {
      payloads['https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/'
          '1.0.3065.39/microsoft.web.webview2.1.0.3065.39.nupkg'] =
          buildFakeNupkg(loaderDll: fakePeImage(machine: 0x014c));
      final UpdateCheckResult result = await svc.check();
      await expectLater(
        svc.download(result.pendingUpdates, isCancelled: () => false),
        throwsA(isA<UpdateVerifyException>()),
      );
      expect(staging.existsSync(), isFalse);
    });

    test('a package without the loader is refused', () async {
      payloads['https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/'
          '1.0.3065.39/microsoft.web.webview2.1.0.3065.39.nupkg'] =
          buildFakeNupkg(includeLoader: false);
      final UpdateCheckResult result = await svc.check();
      await expectLater(
        svc.download(result.pendingUpdates, isCancelled: () => false),
        throwsA(isA<UpdateVerifyException>()),
      );
    });

    test('an unpacker error is a preparation error, not a network error',
        () async {
      svc.extractArchive = (File archive, Directory dest) async {
        throw const UpdateFetchException('tar failed on a downloaded 7z');
      };
      final UpdateCheckResult result = await svc.check();
      await expectLater(
        svc.download(result.pendingUpdates, isCancelled: () => false),
        throwsA(isA<UpdateVerifyException>().having(
          (UpdateVerifyException e) => e.message,
          'message',
          'Could not unpack the MPV archive.',
        )),
      );
      expect(staging.existsSync(), isFalse,
          reason: 'a failed extraction cannot leave a partial swap behind');
    });

    test('purgeStaging clears a complete staging', () async {
      await stageAll();
      expect(svc.stagedReady, isTrue);
      svc.purgeStaging();
      expect(svc.stagedReady, isFalse);
      expect(staging.existsSync(), isFalse);
    });

    test('stagedReady is false with nothing staged', () {
      expect(svc.stagedReady, isFalse);
    });
  });

  group('the swap handoff', () {
    late List<String> calls;
    late bool exited;
    late Map<String, String> lastEnv;

    void installFakeInstaller({bool spawnOk = true}) {
      calls = <String>[];
      exited = false;
      lastEnv = <String, String>{};
      svc.installer = UpdateInstallerWindows(
        scriptWriter: (String scriptPath) async {
          calls.add('write:$scriptPath');
        },
        spawner: (String scriptPath, Map<String, String> env) async {
          lastEnv = env;
          calls.add('spawn:$scriptPath:${env[swapEnvRelaunch]}');
          return spawnOk;
        },
        exitApp: () => exited = true,
        // The guards are the installer's own business and are covered by
        // update_installer_windows_test.dart; here they would only write real
        // files in the sandbox.
        writability: (String targetDir) => true,
        lockReader: (String lockPath) => null,
      );
    }

    test('Restart Now hands the swap the real paths, then exits', () async {
      installFakeInstaller();
      final bool started = await svc.restartNow();
      expect(started, isTrue);
      expect(
        calls,
        <String>[
          'write:${swapScriptPathFor(staging.path)}',
          'spawn:${swapScriptPathFor(staging.path)}:1',
        ],
      );
      expect(lastEnv[swapEnvTarget], root.path);
      expect(lastEnv[swapEnvStaging], staging.path);
      // SALU's own executable path, not a hardcoded `salu.exe` in a folder:
      // a renamed or relocated install still reopens itself.
      expect(lastEnv[swapEnvExe], p.join(root.path, 'salu.exe'));
      expect(exited, isTrue);
      expect(Directory(staging.path).existsSync(), isTrue,
          reason: 'staging must SURVIVE this close — the script reads it after '
              'SALU is gone');
    });

    test('Restart Later applies on close — relaunch off', () async {
      installFakeInstaller();
      // Stage something real first.
      final UpdateCheckResult result = await svc.check();
      await svc.download(result.pendingUpdates, isCancelled: () => false);

      await svc.applyAtClose();
      expect(
        calls,
        <String>[
          'write:${swapScriptPathFor(staging.path)}',
          'spawn:${swapScriptPathFor(staging.path)}:0',
        ],
      );
      expect(exited, isFalse, reason: 'a close-time swap never relaunches');
    });

    test('nothing staged, nothing spawned at close', () async {
      installFakeInstaller();
      await svc.applyAtClose();
      expect(calls, isEmpty);
    });

    test('a close-time swap never throws at the door', () async {
      // The close hook has one job: get out. A refusal is a log line.
      final UpdateCheckResult result = await svc.check();
      await svc.download(result.pendingUpdates, isCancelled: () => false);
      svc.installer = UpdateInstallerWindows(
        scriptWriter: (String scriptPath) async {},
        spawner: (String s, Map<String, String> e) async => true,
        writability: (String targetDir) => false,
        lockReader: (String lockPath) => null,
      );
      await svc.applyAtClose();
      expect(svc.stagedReady, isTrue, reason: 'still staged, still pending');
    });

    test('a refused spawn keeps SALU alive (Restart Now)', () async {
      installFakeInstaller(spawnOk: false);
      final bool started = await svc.restartNow();
      expect(started, isFalse);
      expect(exited, isFalse);
    });

    test('a dev build applies without reopening itself (updater.md §10)',
        () async {
      installFakeInstaller();
      svc.devBuildProbe = () => true;
      expect(svc.isDevBuild, isTrue);
      final bool started = await svc.restartNow();
      expect(started, isTrue);
      expect(exited, isTrue, reason: 'the files still need swapping, and '
          'exiting is what releases them');
      expect(lastEnv[swapEnvRelaunch], '0',
          reason: 'a dev build that reopens itself leaves the debugger behind '
              'for nothing');
    });

    test('a refusal is shown, not swallowed, and SALU stays up', () async {
      installFakeInstaller();
      svc.installer = UpdateInstallerWindows(
        scriptWriter: (String scriptPath) async {},
        spawner: (String s, Map<String, String> e) async => true,
        writability: (String targetDir) => false,
        lockReader: (String lockPath) => null,
      );
      await expectLater(svc.restartNow(),
          throwsA(isA<UpdateSwapRefusedException>()));
      expect(exited, isFalse);
      expect(svc.stagedReady, isTrue,
          reason: 'a swap that cannot run must not discard verified payloads');
    });

    test('the startup sweep drops staging whose versions are installed',
        () async {
      final UpdateCheckResult result = await svc.check();
      await svc.download(result.pendingUpdates, isCancelled: () => false);
      expect(svc.stagedReady, isTrue);
      // Half-applied (no versions.json yet): the sweep must leave it alone.
      svc.postLaunchSweep();
      expect(svc.stagedReady, isTrue,
          reason: 'dropping an unapplied update is how files get lost');

      // The swap having run: manifest.json promoted to versions.json.
      File(p.join(staging.path, 'manifest.json')).copySync(
        p.join(root.path, 'versions.json'),
      );
      expect(svc.isStagingAlreadyInstalled(), isTrue);
      svc.postLaunchSweep();
      expect(svc.stagedReady, isFalse,
          reason: 'an applied update is not a pending one');
      expect(staging.existsSync(), isFalse);
    });

    test('the startup sweep removes a stale lock and script', () async {
      final File lock = File(swapLockPathFor(staging.path))
        ..writeAsStringSync('9 9');
      final File script = File(swapScriptPathFor(staging.path))
        ..writeAsStringSync('rem');
      lock.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
      script.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
      svc.installer = UpdateInstallerWindows(
        clock: () => DateTime.now(),
      );
      svc.postLaunchSweep();
      expect(lock.existsSync(), isFalse);
      expect(script.existsSync(), isFalse);
    });
  });
}
