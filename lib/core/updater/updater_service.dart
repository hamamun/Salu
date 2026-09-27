import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../settings_service.dart';
import 'github_updater_client.dart';
import 'nuget_client.dart';
import 'update_installer_windows.dart';
import 'update_manifest.dart';

/// How feed documents are fetched (JSON, checksum text).
typedef UpdateTextFetcher = Future<String> Function(Uri url);

/// Progress of the file currently travelling.
typedef UpdateProgressCallback = void Function(int received, int? total);

/// How one component's payload is streamed to disk.
typedef UpdateFileDownloader = Future<void> Function(
  Uri url,
  File target,
  UpdateProgressCallback onProgress,
  bool Function() isCancelled,
);

/// How a downloaded archive is unpacked (the mpv `.7z`).
typedef UpdateArchiveExtractor = Future<void> Function(
  File archive,
  Directory dest,
);

/// The feeds could not be reached (or answered nonsense) — updater.md §8
/// State 4, "Unable to connect to update servers".
class UpdateFetchException implements Exception {
  const UpdateFetchException(this.message);
  final String message;
  @override
  String toString() => 'UpdateFetchException: $message';
}

/// A download stopped because the viewer asked it to (updater.md §8:
/// "active stream is aborted, staging folder is purged").
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
}

/// A downloaded file failed verification (x64 guard, checksum, archive
/// shape) and was refused before it could reach the installation root.
class UpdateVerifyException implements Exception {
  const UpdateVerifyException(this.message);
  final String message;
  @override
  String toString() => 'UpdateVerifyException: $message';
}

/// One live progress reading of [UpdaterService.download] (updater.md §8,
/// State 2C: "Fetching: … (1.2 MB / 2.8 MB) · Overall: 1 of 2").
class UpdateProgress {
  const UpdateProgress({
    required this.component,
    required this.received,
    required this.total,
    required this.completed,
    required this.overall,
  });

  final UpdateComponent component;

  /// Bytes of the current payload received so far.
  final int received;

  /// Total bytes of the current payload — `null` while unknown.
  final int? total;

  /// Components fully staged so far.
  final int completed;

  /// Components being staged in this round.
  final int overall;
}

/// SALU's component & engine updater — the coordinator (updater.md).
///
/// The full pipeline: **check** the three feeds → **compare** against
/// `versions.json` (+ shipped baselines) → **download & stage** into
/// `%TEMP%\salu_update\` with verification → hand the **swap** to the
/// detached `salu_updater.bat` on restart (updater.md §3).
///
/// Nothing here touches playback or the browser: checks and downloads are
/// pure file work in the background (updater.md §9 · "No Interruption of
/// Playback"), and any network failure degrades to a quiet warning.
class UpdaterService {
  UpdaterService._internal();

  /// The one updater for the whole app.
  static final UpdaterService instance = UpdaterService._internal();

  /// The User-Agent every request carries (GitHub's API requires one).
  static const String _userAgent = 'SALU-Updater';

  /// The staging directory name (updater.md §5: `%TEMP%\salu_update\`).
  static const String stagingFolderName = 'salu_update';

  /// `versions.json` — the installed-component store in the installation
  /// root (updater.md §5), written by the swap script (§6, step 4). SALU
  /// itself only ever reads it; the check phase is read-only.
  static const String versionsFileName = 'versions.json';

  /// The staged document the swap script promotes to [versionsFileName].
  static const String manifestFileName = 'manifest.json';

  /// What a fresh install runs before any update — the versions the build
  /// itself pins, so the first check can honestly show
  /// `1.0.1210.39 → 1.0.3065.39` instead of a blank (updater.md §8):
  ///
  /// * `webview2` — the `WEBVIEW_VERSION` pin the vendored
  ///   `third_party/webview_windows/windows/CMakeLists.txt` downloads at
  ///   build time;
  /// * `mpv` — the libmpv build tag
  ///   `media_kit_libs_windows_video` compiles against
  ///   (`mpv-dev-x86_64-20241021-git-0f78584.7z`);
  /// * `yt-dlp` — nothing pins it at build time; it stays untracked until
  ///   the first update writes `versions.json`.
  static const Map<UpdateComponent, String> shippedVersions =
      <UpdateComponent, String>{
    UpdateComponent.webView2Loader: '1.0.1210.39',
    UpdateComponent.mpvEngine: '20241021',
  };

  // ── Test seams (production defaults below) ─────────────────────────────

  /// How feed documents are fetched.
  UpdateTextFetcher fetchText = _fetchText;

  /// How payloads are streamed to disk.
  UpdateFileDownloader downloadToFile = _downloadToFile;

  /// How the mpv `.7z` is unpacked.
  UpdateArchiveExtractor extractArchive = _extractArchive;

  /// The installation root — where `salu.exe` and `versions.json` live.
  String Function() appDirOf = () => p.dirname(Platform.resolvedExecutable);

  /// The staging directory (`%TEMP%\salu_update`).
  String Function() stagingDirOf = () =>
      p.join(Directory.systemTemp.path, stagingFolderName);

  /// This process's PID — what the swap script waits on (updater.md §6).
  int Function() pidOf = () => pid;

  /// The clock. Seams so "Last checked: Just now" tests do not sleep.
  DateTime Function() now = DateTime.now;

  /// The spawn-and-exit half (updater.md §6, §8).
  UpdateInstallerWindows installer = UpdateInstallerWindows();

  // ── Live state ─────────────────────────────────────────────────────────

  /// True once a check found something newer than installed — the quiet
  /// "Update Available" flag of updater.md §3 step 2. The Settings →
  /// Updates tab surfaces it; nothing nags on its own.
  final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

  // ── Where versions live ────────────────────────────────────────────────

  /// The installed-state store (installation root, updater.md §5).
  File versionsFile() => File(p.join(appDirOf(), versionsFileName));

  /// The version in force for [component]: the store when it knows, else
  /// the shipped baseline, else `null` (untracked).
  String? installedVersionOf(UpdateComponent component) {
    return readLocalVersions().components[component];
  }

  /// The complete local picture: `versions.json` entries win, shipped
  /// baselines fill the gaps. Never throws — a missing or hand-mangled
  /// store degrades to the baselines (updater.md §9 · Offline / corrupt
  /// resilience).
  UpdateManifest readLocalVersions() {
    final UpdateManifest fromFile = _readVersionsFile();
    final Map<UpdateComponent, String> merged =
        <UpdateComponent, String>{...fromFile.components};
    for (final MapEntry<UpdateComponent, String> e in shippedVersions.entries) {
      merged.putIfAbsent(e.key, () => e.value);
    }
    return UpdateManifest(merged);
  }

  UpdateManifest _readVersionsFile() {
    try {
      final File file = versionsFile();
      if (!file.existsSync()) return const UpdateManifest({});
      return UpdateManifest.tryParse(file.readAsStringSync());
    } catch (_) {
      return const UpdateManifest({});
    }
  }

  // ── 1–2. Check & compare (updater.md §3) ───────────────────────────────

  /// Queries all three feeds and compares against the local store.
  ///
  /// All-or-nothing: one unreachable feed means no honest table can be
  /// shown, so the round reports `ok: false` and the modal's quiet
  /// network state stands (updater.md §8, State 4). A successful round
  /// stamps `SettingsService.lastUpdateCheckTime` (a failed one never
  /// does — the next launch quietly tries again).
  Future<UpdateCheckResult> check({bool rememberTime = true}) async {
    final DateTime checkedAt = now();
    try {
      final NugetClient nuget = NugetClient(fetchText: fetchText);
      final GitHubUpdaterClient github =
          GitHubUpdaterClient(fetchText: fetchText);

      // ── Check phase (updater.md §3 step 1). ───────────────────────────
      final String? webviewLatest = await nuget.latestStableVersion();
      if (webviewLatest == null) {
        throw const UpdateFetchException('NuGet feed empty');
      }
      final GithubRelease? mpvRelease =
          await github.latestRelease(GitHubUpdaterClient.mpvRepo);
      if (mpvRelease == null) {
        throw const UpdateFetchException('mpv feed unreachable');
      }
      final GithubAsset? mpvAsset =
          GitHubUpdaterClient.pickMpvAsset(mpvRelease);
      if (mpvAsset == null) {
        throw const UpdateFetchException('mpv feed empty');
      }
      final GithubRelease? ytDlpRelease =
          await github.latestRelease(GitHubUpdaterClient.ytDlpRepo);
      if (ytDlpRelease == null) {
        throw const UpdateFetchException('yt-dlp feed unreachable');
      }
      final GithubAsset? ytDlpAsset =
          GitHubUpdaterClient.pickYtDlpAsset(ytDlpRelease);
      if (ytDlpAsset == null) {
        throw const UpdateFetchException('yt-dlp feed empty');
      }
      final GithubAsset? ytDlpSums =
          GitHubUpdaterClient.pickChecksumsAsset(ytDlpRelease);

      // ── Compare phase (updater.md §3 step 2). ─────────────────────────
      final UpdateManifest local = readLocalVersions();
      final List<ComponentStatus> rows = <ComponentStatus>[
        _statusFor(
          component: UpdateComponent.webView2Loader,
          installed: local.components[UpdateComponent.webView2Loader],
          latest: webviewLatest,
          downloadUrl: NugetClient.packageUrlFor(webviewLatest).toString(),
        ),
        _statusFor(
          component: UpdateComponent.mpvEngine,
          installed: local.components[UpdateComponent.mpvEngine],
          latest: mpvRelease.tag,
          downloadUrl: mpvAsset.url,
        ),
        _statusFor(
          component: UpdateComponent.ytDlp,
          installed: local.components[UpdateComponent.ytDlp],
          latest: ytDlpRelease.tag,
          downloadUrl: ytDlpAsset.url,
          checksumUrl: ytDlpSums?.url,
        ),
      ];

      final UpdateCheckResult result = UpdateCheckResult(
        ok: true,
        checkedAt: checkedAt,
        components: rows,
      );
      if (rememberTime) {
        await SettingsService.instance.setLastUpdateCheckTime(checkedAt);
      }
      updateAvailable.value = result.hasUpdates;
      return result;
    } catch (error) {
      debugPrint('[SALU] updater: check failed: $error');
      return UpdateCheckResult(ok: false, checkedAt: checkedAt);
    }
  }

  ComponentStatus _statusFor({
    required UpdateComponent component,
    required String? installed,
    required String latest,
    required String downloadUrl,
    String? checksumUrl,
  }) {
    // Untracked installed version ⇒ the update is offered: SALU cannot
    // claim currency it cannot prove (updater.md §3: "If remote version >
    // local version: flag as Update Available").
    final bool available =
        installed == null || compareUpdateVersions(latest, installed) > 0;
    return ComponentStatus(
      component: component,
      installed: installed,
      latest: latest,
      downloadUrl: downloadUrl,
      checksumUrl: checksumUrl,
      updateAvailable: available,
    );
  }

  // ── 3. Download & stage (updater.md §3) ────────────────────────────────

  /// Stages every pending update into `%TEMP%\salu_update\`, verified, and
  /// writes `manifest.json` — the complete new version picture (updates
  /// merged over what stays).
  ///
  /// Throws [UpdateCancelledException] when [isCancelled] turns true (the
  /// staging folder is purged first), [UpdateVerifyException] when a
  /// payload fails its integrity checks, [UpdateFetchException] when the
  /// network drops. Any failure leaves no half-staged state behind.
  Future<UpdateManifest> download(
    List<ComponentUpdate> updates, {
    void Function(UpdateProgress progress)? onProgress,
    required bool Function() isCancelled,
  }) async {
    purgeStaging();
    final Directory staging = Directory(stagingDirOf());
    await staging.create(recursive: true);
    final int overall = updates.length;
    int completed = 0;
    try {
      for (final ComponentUpdate update in updates) {
        if (isCancelled()) throw const UpdateCancelledException();
        _emit(onProgress, update.component, 0, null, completed, overall);
        switch (update.component) {
          case UpdateComponent.webView2Loader:
            await _stageWebView2(update, staging, isCancelled, onProgress,
                completed, overall);
          case UpdateComponent.mpvEngine:
            await _stageMpv(update, staging, isCancelled, onProgress,
                completed, overall);
          case UpdateComponent.ytDlp:
            await _stageYtDlp(update, staging, isCancelled, onProgress,
                completed, overall);
        }
        completed++;
        _emit(onProgress, update.component, 0, null, completed, overall);
      }

      // The staged manifest carries the FULL version picture — updater.md
      // §6 promotes it to `versions.json` verbatim, so untouched components
      // must keep their current versions in it.
      if (isCancelled()) throw const UpdateCancelledException();
      final UpdateManifest merged =
          readLocalVersions().copyWith(<UpdateComponent, String>{
        for (final ComponentUpdate u in updates) u.component: u.toVersion,
      });
      await File(p.join(staging.path, manifestFileName))
          .writeAsString(merged.toJsonString(), flush: true);
      return merged;
    } catch (error) {
      // Cancel or failure — never leave a half-staged swap behind
      // (updater.md §8's Cancel rules).
      purgeStaging();
      rethrow;
    }
  }

  Future<void> _stageWebView2(
    ComponentUpdate update,
    Directory staging,
    bool Function() isCancelled,
    void Function(UpdateProgress progress)? onProgress,
    int completed,
    int overall,
  ) async {
    final File tmp = File(p.join(staging.path, 'webview2.nupkg'));
    await downloadToFile(
      Uri.parse(update.downloadUrl),
      tmp,
      (int received, int? total) =>
          _emit(onProgress, update.component, received, total, completed, overall),
      isCancelled,
    );
    if (isCancelled()) throw const UpdateCancelledException();
    final List<int>? dll = NugetClient.extractLoaderDll(await tmp.readAsBytes());
    if (tmp.existsSync()) await tmp.delete();
    if (dll == null || dll.isEmpty) {
      throw const UpdateVerifyException('WebView2Loader.dll missing from package');
    }
    if (!isX64PeImage(dll)) {
      throw const UpdateVerifyException('WebView2Loader.dll is not a 64-bit build');
    }
    await File(p.join(staging.path, update.fileName))
        .writeAsBytes(dll, flush: true);
  }

  Future<void> _stageMpv(
    ComponentUpdate update,
    Directory staging,
    bool Function() isCancelled,
    void Function(UpdateProgress progress)? onProgress,
    int completed,
    int overall,
  ) async {
    final File tmp = File(p.join(staging.path, 'mpv.7z'));
    final Directory unpack = Directory(p.join(staging.path, 'mpv_unpacked'));
    await downloadToFile(
      Uri.parse(update.downloadUrl),
      tmp,
      (int received, int? total) =>
          _emit(onProgress, update.component, received, total, completed, overall),
      isCancelled,
    );
    if (isCancelled()) throw const UpdateCancelledException();
    await extractArchive(tmp, unpack);
    // The archive root holds `libmpv-2.dll` beside the headers — but walk
    // the tree anyway; packaging moves, the file name does not.
    File? dll;
    for (final FileSystemEntity e in unpack.listSync(recursive: true)) {
      if (e is File && p.basename(e.path) == update.fileName) {
        dll = e;
        break;
      }
    }
    if (dll == null) {
      throw const UpdateVerifyException('libmpv-2.dll missing from archive');
    }
    final List<int> bytes = await dll.readAsBytes();
    if (!isX64PeImage(bytes)) {
      throw const UpdateVerifyException('libmpv-2.dll is not a 64-bit build');
    }
    await File(p.join(staging.path, update.fileName))
        .writeAsBytes(bytes, flush: true);
    if (tmp.existsSync()) await tmp.delete();
    if (unpack.existsSync()) await unpack.delete(recursive: true);
  }

  Future<void> _stageYtDlp(
    ComponentUpdate update,
    Directory staging,
    bool Function() isCancelled,
    void Function(UpdateProgress progress)? onProgress,
    int completed,
    int overall,
  ) async {
    final File target = File(p.join(staging.path, update.fileName));
    await downloadToFile(
      Uri.parse(update.downloadUrl),
      target,
      (int received, int? total) =>
          _emit(onProgress, update.component, received, total, completed, overall),
      isCancelled,
    );
    if (isCancelled()) throw const UpdateCancelledException();
    final List<int> bytes = await target.readAsBytes();
    if (bytes.isEmpty) {
      throw const UpdateVerifyException('yt-dlp.exe is empty');
    }
    if (!isX64PeImage(bytes)) {
      throw const UpdateVerifyException('yt-dlp.exe is not a 64-bit build');
    }
    // Integrity (updater.md §3 · "Verify integrity / checksums"): the
    // release publishes `SHA2-256SUMS` beside the binary.
    final String? checksumUrl = update.checksumUrl;
    if (checksumUrl != null) {
      final String sums = await fetchText(Uri.parse(checksumUrl));
      final String? expected =
          GitHubUpdaterClient.sha256For(sums, update.fileName);
      if (expected != null) {
        final String actual = sha256.convert(bytes).toString();
        if (actual != expected) {
          throw const UpdateVerifyException('yt-dlp.exe checksum mismatch');
        }
      }
    }
  }

  void _emit(
    void Function(UpdateProgress progress)? onProgress,
    UpdateComponent component,
    int received,
    int? total,
    int completed,
    int overall,
  ) {
    onProgress?.call(UpdateProgress(
      component: component,
      received: received,
      total: total,
      completed: completed,
      overall: overall,
    ));
  }

  // ── Staging & swap (updater.md §5–§6) ──────────────────────────────────

  /// True when a complete staged update is waiting to be swapped in —
  /// `manifest.json` plus at least one component file (updater.md §8 ·
  /// "Restart Later": staged files are applied on the next normal close).
  bool get stagedReady {
    try {
      final Directory staging = Directory(stagingDirOf());
      if (!File(p.join(staging.path, manifestFileName)).existsSync()) {
        return false;
      }
      for (final UpdateComponent c in UpdateComponent.values) {
        if (File(p.join(staging.path, c.fileName)).existsSync()) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the staging directory. Cancel's cleanup (updater.md §8) and
  /// the fresh-download prelude both land here.
  void purgeStaging() {
    try {
      final Directory staging = Directory(stagingDirOf());
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    } catch (_) {
      // Locked or already gone — a later download purges again.
    }
  }

  /// updater.md §8 · `[ Restart Now ]`: spawn the detached swap script and
  /// `exit(0)`. The script waits for this PID to die, backs up, swaps,
  /// and relaunches `salu.exe`. Returns false when the script could not be
  /// spawned (SALU stays up; the staged files remain for the close-time
  /// applier).
  Future<bool> restartNow() {
    return installer.applyAndExit(
      stagingDir: stagingDirOf(),
      targetDir: appDirOf(),
      saluPid: pidOf(),
    );
  }

  /// updater.md §8 · `[ Restart Later ]`'s second half: the staged files
  /// are applied on the next normal close. The same script, spawned just
  /// before `exit(0)` — with `relaunch: 0` so closing SALU stays closing.
  Future<void> applyAtClose() async {
    if (!stagedReady) return;
    await installer.startSwap(
      stagingDir: stagingDirOf(),
      targetDir: appDirOf(),
      saluPid: pidOf(),
      relaunch: false,
    );
  }

  // ── Scheduled checks (updater.md §7 · persistence) ─────────────────────

  /// Whether the configured cadence has elapsed since the last successful
  /// check (and the cadence is not Off).
  bool get isCheckDue {
    final Duration? interval =
        SettingsService.instance.updateCheckFrequency.value.interval;
    if (interval == null) return false;
    final int lastMs = SettingsService.instance.lastUpdateCheckTime.value;
    if (lastMs <= 0) return true;
    return now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) >=
        interval;
  }

  /// Startup hook (updater.md §7): "if interval has elapsed (and not
  /// `off`), runs silent check in background". Silent = no dialog, no
  /// playback interference — it only raises [updateAvailable].
  void scheduleStartupCheck() {
    if (!isCheckDue) return;
    unawaited(_silentCheck());
  }

  Future<void> _silentCheck() async {
    try {
      final UpdateCheckResult result = await check();
      updateAvailable.value = result.hasUpdates;
    } catch (_) {
      // Offline resilience (updater.md §9): log and carry on — the
      // player never hears about it.
    }
  }

  /// Test seam reset — production defaults, no cached flags.
  void debugResetForTest() {
    fetchText = _fetchText;
    downloadToFile = _downloadToFile;
    extractArchive = _extractArchive;
    appDirOf = () => p.dirname(Platform.resolvedExecutable);
    stagingDirOf = () =>
        p.join(Directory.systemTemp.path, stagingFolderName);
    pidOf = () => pid;
    now = DateTime.now;
    installer = UpdateInstallerWindows();
    updateAvailable.value = false;
  }
}

// ── Production HTTP & extraction (the seams' defaults) ─────────────────────

Future<String> _fetchText(Uri url) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final HttpClientRequest request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, UpdaterService._userAgent);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      throw UpdateFetchException('HTTP ${response.statusCode} from $url');
    }
    return await response.transform(utf8.decoder).join();
  } on UpdateFetchException {
    rethrow;
  } catch (error) {
    throw UpdateFetchException('cannot reach $url ($error)');
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadToFile(
  Uri url,
  File target,
  UpdateProgressCallback onProgress,
  bool Function() isCancelled,
) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, UpdaterService._userAgent);
    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      throw UpdateFetchException('HTTP ${response.statusCode} from $url');
    }
    final int? total =
        response.contentLength >= 0 ? response.contentLength : null;
    final IOSink sink = target.openWrite();
    int received = 0;
    bool cancelled = false;
    final Completer<void> done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = response.listen(
      (List<int> chunk) {
        if (isCancelled()) {
          cancelled = true;
          // Abort the stream at once (updater.md §8 · mid-download Cancel).
          sub.cancel().whenComplete(() {
            if (!done.isCompleted) done.complete();
          });
          return;
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      },
      onError: (Object error) {
        if (!done.isCompleted) {
          done.completeError(UpdateFetchException('download failed ($error)'));
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      await done.future;
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (cancelled || isCancelled()) {
      if (target.existsSync()) {
        try {
          await target.delete();
        } catch (_) {}
      }
      throw const UpdateCancelledException();
    }
  } on UpdateCancelledException {
    rethrow;
  } on UpdateFetchException {
    rethrow;
  } catch (error) {
    throw UpdateFetchException('download failed ($error)');
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractArchive(File archive, Directory dest) async {
  if (!dest.existsSync()) {
    await dest.create(recursive: true);
  }
  // Windows 10+ ships bsdtar as `tar`, and it reads 7z — the same
  // fallback `media_kit_libs_windows_video`'s own CMake uses when 7-Zip
  // is not installed. No new dependency, and the exact archives media_kit
  // builds against unpack the same way here.
  final ProcessResult result = await Process.run(
    'tar',
    <String>['-xf', archive.path, '-C', dest.path],
  );
  if (result.exitCode != 0) {
    throw UpdateFetchException('extract failed (${result.exitCode})');
  }
}
