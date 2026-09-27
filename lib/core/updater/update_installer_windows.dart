/// SALU's Windows swap step (updater.md §2, §5–§6, §9, §10): the detached
/// updater script, the way it is spawned, and the x64 architecture guard
/// every staged binary must pass before it is allowed into the
/// installation root.
///
/// Windows will not let SALU overwrite the DLLs it is running from — so the
/// new files are staged in `%TEMP%\salu_update\`, this script swaps them
/// once the install root lets it, and relaunches (or stays down when the
/// swap rides a normal close, or when the build is a dev one — §10).
///
/// Two rules this file exists to honour, both learned the hard way
/// (updater.md §6.1): the swap must create **no console windows**, and it
/// must never *wait on a process id*.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// True when [bytes] is a 64-bit x86-64 PE image (`WebView2Loader.dll`,
/// `libmpv-2.dll`, `yt-dlp.exe` all are).
///
/// updater.md §9 · Architecture Guard: "Always check that the downloaded
/// DLL is 64-bit (x64) so 32-bit (x86) files are never placed into a
/// 64-bit SALU installation." Checked by reading the PE header's machine
/// field: `MZ` → `e_lfanew` → `PE\0\0` + machine `0x8664`.
/// x86 (`0x014c`) and ARM64 (`0xAA64`) fail, as does anything that is not
/// a PE at all — an HTML error page from a captive portal can never become
/// a DLL.
bool isX64PeImage(List<int> bytes) {
  if (bytes.length < 64) return false;
  // 'MZ' — the DOS stub every PE starts with.
  if (bytes[0] != 0x4D || bytes[1] != 0x5A) return false;
  final int eLfanew =
      bytes[0x3C] | (bytes[0x3D] << 8) | (bytes[0x3E] << 16) | (bytes[0x3F] << 24);
  if (eLfanew < 0 || eLfanew + 6 > bytes.length) return false;
  // 'PE\0\0'.
  if (bytes[eLfanew] != 0x50 ||
      bytes[eLfanew + 1] != 0x45 ||
      bytes[eLfanew + 2] != 0x00 ||
      bytes[eLfanew + 3] != 0x00) {
    return false;
  }
  final int machine = bytes[eLfanew + 4] | (bytes[eLfanew + 5] << 8);
  return machine == 0x8664;
}

/// The three files the script swaps, in slot order. The same names
/// `UpdateComponent.fileName` owns — written out here because the script is
/// cmd, not Dart, and `for %%f in (...)` must list them literally. The test
/// suite pins the two lists against each other so they cannot drift.
const List<String> swapComponentFiles = <String>[
  'WebView2Loader.dll',
  'libmpv-2.dll',
  'yt-dlp.exe',
];

/// The script's file name (updater.md §5).
const String swapScriptName = 'salu_swap.bat';

/// The swap's own log, beside the script in `%TEMP%` — `%TEMP%` and not the
/// staging folder, because it has to outlive the success cleanup and a
/// failure that deliberately keeps staging.
const String swapLogName = 'salu_swap.log';

/// The "a swap is in flight" marker. Written before the script starts and
/// deleted by the script's last step, so a swap that was killed instead of
/// finished cannot block SALU forever: [UpdateInstallerWindows] treats it as
/// stale after [swapLockLifetime].
const String swapLockName = 'salu_swap.lock';

/// How long a lock may block a second swap before it is ignored.
const Duration swapLockLifetime = Duration(minutes: 5);

/// How many times the script re-attempts the swap while the files are
/// still held busy (§6.1). One attempt per second. The script writes the
/// number into `set MAX=`, and the test suite pins the two together.
const int swapAttempts = 10;

/// The environment keys the job travels in. Everything the script cannot
/// safely derive — and everything it must NOT re-parse off a command line,
/// where one quoted path is enough for cmd to mis-split an argument.
const String swapEnvTarget = 'SALU_SWAP_TARGET';
const String swapEnvStaging = 'SALU_SWAP_STAGING';
const String swapEnvExe = 'SALU_SWAP_EXE';
const String swapEnvRelaunch = 'SALU_SWAP_RELAUNCH';
const String swapEnvLock = 'SALU_SWAP_LOCK';
const String swapEnvHidden = 'SALU_SWAP_HIDDEN';

/// The script body (updater.md §6), with CRLF endings — cmd's `goto` over
/// LF-only batch files is not a safe bet. ASCII throughout: cmd reads a
/// batch file in the console's OEM codepage, so a non-ASCII byte in an
/// `echo`/`title` line would print as mojibake.
const String saluUpdaterScript =
    '@echo off\r\n'
    'rem == SALU component swap (updater.md section 6) ==\r\n'
    'rem\r\n'
    'rem The job arrives in THIS process\'s environment block, set by SALU when it\r\n'
    'rem started this script - so no quoted path ever sits on a command line for\r\n'
    'rem cmd to re-split:\r\n'
    'rem   SALU_SWAP_TARGET    installation root the new files land in\r\n'
    'rem   SALU_SWAP_STAGING   folder holding them (+ manifest.json)\r\n'
    'rem   SALU_SWAP_EXE       what to reopen once the swap is done\r\n'
    'rem   SALU_SWAP_RELAUNCH  1 = reopen SALU, 0 = swap only\r\n'
    'rem   SALU_SWAP_LOCK      \'a swap is running\' marker, released at the end\r\n'
    'rem\r\n'
    'rem The log lives in %TEMP% beside this script - never in the staging folder\r\n'
    'rem it cleans up: it has to outlive the success cleanup AND a failure that\r\n'
    'rem deliberately keeps staging.\r\n'
    '\r\n'
    'rem == 0. Borrow a console - a minimized, out-of-the-way one ==\r\n'
    'rem SALU starts us DETACHED: no console at all. Every console tool a\r\n'
    'rem console-less process launches then gets a brand-new window of its own,\r\n'
    'rem which is a screen full of flashing black boxes - the exact bug this step\r\n'
    'rem exists for. Re-running this file under `start /min` gives the whole swap\r\n'
    'rem ONE minimized console that every tool below inherits, so nothing flashes\r\n'
    'rem and every tool still has a console (and a stdin) to work with.\r\n'
    'if not "%SALU_SWAP_HIDDEN%"=="1" (\r\n'
    '  set SALU_SWAP_HIDDEN=1\r\n'
    '  start "" /min cmd.exe /c "%~f0"\r\n'
    '  exit /b 0\r\n'
    ')\r\n'
    '\r\n'
    'rem Delayed expansion is not a style choice here: the per-slot outcomes of\r\n'
    'rem the swap (DONE1..3, OLD1..3) are written inside :SWAP and read after it,\r\n'
    'rem and only !VAR! sees a value that changed since its line was parsed.\r\n'
    'rem `setlocal` keeps every variable this script needs out of the\r\n'
    'rem machine-wide environment.\r\n'
    'setlocal enabledelayedexpansion\r\n'
    'if "%LOG%"=="" set LOG=%TEMP%\\salu_swap.log\r\n'
    'title SALU is updating - please wait\r\n'
    'set TARGET=%SALU_SWAP_TARGET%\r\n'
    'set STAGING=%SALU_SWAP_STAGING%\r\n'
    'set EXE=%SALU_SWAP_EXE%\r\n'
    'set LOCK=%SALU_SWAP_LOCK%\r\n'
    'set RELAUNCH=%SALU_SWAP_RELAUNCH%\r\n'
    'if "%RELAUNCH%"=="" set RELAUNCH=1\r\n'
    'set ATTEMPT=0\r\n'
    'set MAX=10\r\n'
    'set RC=0\r\n'
    'set KEEP_STAGING=0\r\n'
    'set DONE1=0\r\n'
    'set DONE2=0\r\n'
    'set DONE3=0\r\n'
    '>>"%LOG%" echo ==== %DATE% %TIME% swap start target=%TARGET%\r\n'
    '\r\n'
    'rem == 1. Wait for the locks by USING them, never by watching SALU ==\r\n'
    'rem The current file is RENAMED out of the way and the staged one copied in.\r\n'
    'rem A rename is exactly what Windows still allows while SALU is on its way\r\n'
    'rem out, because a loaded DLL is opened with share-delete and its owner keeps\r\n'
    'rem its own mapping. So there is no process id to poll and no\r\n'
    'rem `tasklist | findstr` to match it: a reused pid - or those digits turning\r\n'
    'rem up in any other column - can make that loop wait forever, and the\r\n'
    'rem `timeout` it slept with needs a keyboard, so with none the loop spun as\r\n'
    'rem fast as the CPU allows, opening a fresh window on every pass. A busy file\r\n'
    'rem now simply makes this attempt fail, and the attempt repeats a second\r\n'
    'rem later; ten attempts, ten seconds, then the install goes back as it was.\r\n'
    ':TRY\r\n'
    'set /a ATTEMPT+=1\r\n'
    'set BAD=0\r\n'
    'call :SWAP 1 WebView2Loader.dll\r\n'
    'if errorlevel 1 set BAD=1\r\n'
    'call :SWAP 2 libmpv-2.dll\r\n'
    'if errorlevel 1 set BAD=1\r\n'
    'call :SWAP 3 yt-dlp.exe\r\n'
    'if errorlevel 1 set BAD=1\r\n'
    'if "%BAD%"=="0" goto :OK\r\n'
    'if %ATTEMPT% LSS %MAX% (\r\n'
    '  rem `ping` is the pause that needs no keyboard. `timeout` is not.\r\n'
    '  ping -n 2 -w 1000 127.0.0.1 >nul\r\n'
    '  goto :TRY\r\n'
    ')\r\n'
    '\r\n'
    'rem == 2. Out of attempts: put the installation back exactly as found ==\r\n'
    'rem `msg` is gone too - it is missing from Windows Home, and a popup that\r\n'
    'rem fails to appear in the middle of a failed update is worse than a line in\r\n'
    'rem the log.\r\n'
    'set RC=1\r\n'
    'set KEEP_STAGING=1\r\n'
    '>>"%LOG%" echo ==== %DATE% %TIME% swap FAILED after %ATTEMPT% attempts - previous files restored, staging kept\r\n'
    'if "!DONE1!"=="1" call :RESTORE WebView2Loader.dll\r\n'
    'if "!DONE2!"=="1" call :RESTORE libmpv-2.dll\r\n'
    'if "!DONE3!"=="1" call :RESTORE yt-dlp.exe\r\n'
    'goto :FINISH\r\n'
    '\r\n'
    ':OK\r\n'
    'rem == 3. The staged manifest becomes the installed record ==\r\n'
    'rem Promoted only when EVERY file made it, so a failed swap can never leave\r\n'
    'rem versions.json claiming a version the disk does not have.\r\n'
    'if exist "%STAGING%\\manifest.json" copy /y "%STAGING%\\manifest.json" "%TARGET%\\versions.json" >nul\r\n'
    '>>"%LOG%" echo ==== %DATE% %TIME% swap OK on attempt %ATTEMPT%\r\n'
    '\r\n'
    ':FINISH\r\n'
    'call :CLEAN\r\n'
    'if not "%RELAUNCH%"=="0" (\r\n'
    '  rem The dying SALU holds its single-instance mutex a moment longer. Starting\r\n'
    '  rem too early makes the new process a \'second window\': it forwards its\r\n'
    '  rem arguments to a process that is already gone and quits, which reads as\r\n'
    '  rem \'SALU never came back\'. The pause is the whole fix.\r\n'
    '  ping -n 4 -w 1000 127.0.0.1 >nul\r\n'
    '  start "" "%EXE%"\r\n'
    ')\r\n'
    'exit /b %RC%\r\n'
    '\r\n'
    ':SWAP\r\n'
    'rem %~1 = slot number, %~2 = file name. Three rules shape this:\r\n'
    'rem  - a slot already swapped is LEFT ALONE, so a retry never mistakes the\r\n'
    'rem    file it just wrote for the file it was replacing;\r\n'
    'rem  - a component nothing staged for is nothing to do;\r\n'
    'rem  - no `if errorlevel` inside a ( ) block, and none after a call.\r\n'
    'rem errorlevel is ONE slot every command writes, and 0 is what a successful\r\n'
    'rem command stores last - so the second call would read the FIRST one and\r\n'
    'rem believe nothing failed. That is how the previous version of this script\r\n'
    'rem reached its copy step having backed nothing up: the rollback half of the\r\n'
    'rem design was silently dead. Each outcome therefore keeps its own slot-named\r\n'
    'rem variable, read back with delayed expansion.\r\n'
    'if "!DONE%~1!"=="1" exit /b 0\r\n'
    'if not exist "%STAGING%\\%~2" exit /b 0\r\n'
    'del "%TARGET%\\%~2.old" >nul 2>nul\r\n'
    'set "OLD%~1=0"\r\n'
    'if exist "%TARGET%\\%~2" set "OLD%~1=1"\r\n'
    'if "!OLD%~1!"=="1" (\r\n'
    '  ren "%TARGET%\\%~2" "%~2.old" 2>>"%LOG%"\r\n'
    '  set "GONE%~1=!errorlevel!"\r\n'
    '  if not "!GONE%~1!"=="0" (\r\n'
    '    >>"%LOG%" echo %TIME% %~2 is still held by SALU - attempt %ATTEMPT%\r\n'
    '    exit /b 1\r\n'
    '  )\r\n'
    ')\r\n'
    'copy /y "%STAGING%\\%~2" "%TARGET%\\%~2" >nul 2>>"%LOG%"\r\n'
    'set "IN%~1=!errorlevel!"\r\n'
    'if not "!IN%~1!"=="0" (\r\n'
    '  >>"%LOG%" echo %TIME% could not write %~2 - attempt %ATTEMPT% - read-only folder or full disk\r\n'
    '  if "!OLD%~1!"=="1" (\r\n'
    '    ren "%TARGET%\\%~2.old" "%~2" 2>nul\r\n'
    '  ) else (\r\n'
    '    rem Nothing was there before, so a half-written file must not stay behind.\r\n'
    '    del "%TARGET%\\%~2" >nul 2>nul\r\n'
    '  )\r\n'
    '  exit /b 1\r\n'
    ')\r\n'
    'set "DONE%~1=1"\r\n'
    'exit /b 0\r\n'
    '\r\n'
    ':RESTORE\r\n'
    'rem %~1 = file name. The .old beside it is exactly what SALU ran before, so\r\n'
    'rem undoing a swap is one delete and one rename - nothing was ever edited.\r\n'
    'del "%TARGET%\\%~1" >nul 2>nul\r\n'
    'ren "%TARGET%\\%~1.old" "%~1" 2>nul\r\n'
    '>>"%LOG%" echo %TIME% restored %~1\r\n'
    'exit /b 0\r\n'
    '\r\n'
    ':CLEAN\r\n'
    'rem Staging is consumed on success and KEPT on failure - a refused swap never\r\n'
    'rem discards verified payloads. This script lives OUTSIDE the staging folder\r\n'
    'rem on purpose: a batch file that deletes the folder it runs from can stop\r\n'
    'rem reading itself halfway through, which is how a relaunch line silently\r\n'
    'rem never ran.\r\n'
    'if not "%KEEP_STAGING%"=="1" rd /s /q "%STAGING%" >nul 2>nul\r\n'
    'for %%f in (WebView2Loader.dll libmpv-2.dll yt-dlp.exe) do del "%TARGET%\\%%f.old" >nul 2>nul\r\n'
    'if not "%LOCK%"=="" del "%LOCK%" >nul 2>nul\r\n'
    'exit /b 0\r\n';

/// Where the script is written: the `%TEMP%` folder that HOLDS
/// `%TEMP%\salu_update\`, not the staging folder itself (§CLEAN's note).
String swapScriptPathFor(String stagingDir) =>
    p.join(swapTempRootOf(stagingDir), swapScriptName);

/// The lock file's path — same folder, same reason.
String swapLockPathFor(String stagingDir) =>
    p.join(swapTempRootOf(stagingDir), swapLockName);

/// The log's path, for "what happened during that restart?" (§6.1).
String swapLogPathFor(String stagingDir) =>
    p.join(swapTempRootOf(stagingDir), swapLogName);

String swapTempRootOf(String stagingDir) {
  final String parent = p.dirname(p.normalize(stagingDir));
  return parent.isEmpty ? '.' : parent;
}

/// The environment block the script reads its job from.
Map<String, String> swapEnvironment({
  required String targetDir,
  required String stagingDir,
  required String saluExe,
  bool relaunch = true,
  String? lockPath,
}) {
  return <String, String>{
    swapEnvTarget: targetDir,
    swapEnvStaging: stagingDir,
    swapEnvExe: saluExe,
    swapEnvRelaunch: relaunch ? '1' : '0',
    if (lockPath != null) swapEnvLock: lockPath,
  };
}

/// The whole command line: `cmd.exe /c salu_swap.bat`. Nothing else — the
/// arguments are environment variables, so there is no quoting to get wrong
/// and no `start`-style re-parsing to lose a path with a space in it.
List<String> swapCommandLine(String scriptPath) =>
    <String>['/c', scriptPath];

/// The swap could not be started, and why — in user words, because the
/// reason is the useful part (updater.md §8's "Preparation or Installer
/// Error" rule: never blame the network, never show a raw OS error).
class UpdateSwapRefusedException implements Exception {
  const UpdateSwapRefusedException(this.message);

  final String message;

  @override
  String toString() => 'UpdateSwapRefusedException: $message';
}

/// How a swap is spawned and how SALU leaves — the two OS touches of the
/// restart flow, behind seams so tests never kill their own runner.
class UpdateInstallerWindows {
  UpdateInstallerWindows({
    this.scriptWriter = _writeScript,
    this.spawner = _spawnScript,
    this.exitApp = _exitApp,
    this.writability = _installRootWritable,
    this.lockReader = _lockStampedAt,
    this.clock = DateTime.now,
    this.isWindowsHost = Platform.isWindows,
  });

  /// The swap is a `cmd.exe` affair. A seam, so the guards below can be
  /// tested wherever the suite runs.
  final bool isWindowsHost;

  /// Writes the script next to the staging folder (never inside it).
  final Future<void> Function(String scriptPath) scriptWriter;

  /// Spawns `cmd.exe /c salu_swap.bat` detached with the job in its
  /// environment (updater.md §5: "Spawn script detached"). False when
  /// Windows refused.
  final Future<bool> Function(String scriptPath, Map<String, String> environment)
      spawner;

  /// Ends the process — `exit(0)`, updater.md §8's "SALU exits: exit(0)".
  final void Function() exitApp;

  /// Can SALU actually write its own folder? Guards the one install layout
  /// where the swap would fail for a reason the user cannot see: an
  /// installation under `C:\Program Files` (updater.md §10).
  final bool Function(String targetDir) writability;

  /// When the in-flight lock was stamped, or null when there is none. The
  /// lock's own content is this process's pid — so a swap that got stuck can
  /// be traced to whoever started it. (Nothing here ever WAITS on a pid:
  /// that was the bug behind the window storm, updater.md §6.1.)
  final DateTime? Function(String lockPath) lockReader;

  /// The clock — a seam, so no test ever sleeps to age a lock.
  final DateTime Function() clock;

  /// Why a swap must not start right now, or `null` when it may. Checked
  /// before anything is written, so SALU keeps its files and its staging
  /// folder instead of dying in front of a script that cannot work.
  String? refusal({
    required String targetDir,
    required String stagingDir,
  }) {
    if (!isWindowsHost) {
      return 'SALU\'s automatic update install is a Windows feature. '
          'Replace the files in the installation folder by hand.';
    }
    final DateTime? stampedAt = lockReader(swapLockPathFor(stagingDir));
    if (stampedAt != null &&
        clock().difference(stampedAt) < swapLockLifetime) {
      return 'The previous update is still being applied. SALU will finish '
          'it in a moment - try again after it is done.';
    }
    if (!writability(targetDir)) {
      return 'SALU cannot write inside its own folder, so the update cannot '
          'be installed there. Keep SALU in a folder you own (for example '
          'your own Programs folder instead of "Program Files"), or run '
          'SALU as administrator once to apply this update.';
    }
    return null;
  }

  /// Writes the script and spawns it detached. `relaunch: true` = the
  /// script reopens SALU when done (updater.md §8's "Restart Now");
  /// `false` = it only swaps ("Restart Later", riding the close, and every
  /// dev build — §10).
  Future<bool> startSwap({
    required String stagingDir,
    required String targetDir,
    required String saluExe,
    bool relaunch = true,
  }) async {
    final String? reason =
        refusal(targetDir: targetDir, stagingDir: stagingDir);
    if (reason != null) throw UpdateSwapRefusedException(reason);

    final String scriptPath = swapScriptPathFor(stagingDir);
    final String lockPath = swapLockPathFor(stagingDir);
    await scriptWriter(scriptPath);
    _stampLock(lockPath);

    final bool started = await spawner(
      scriptPath,
      swapEnvironment(
        targetDir: targetDir,
        stagingDir: stagingDir,
        saluExe: saluExe,
        relaunch: relaunch,
        lockPath: lockPath,
      ),
    );
    // Never spawned means no script step will ever release the lock; drop
    // it here so the next attempt is not blocked for [swapLockLifetime].
    if (!started) _clearLock(lockPath);
    return started;
  }

  /// updater.md §8 · `[ Restart Now ]`: spawn the swap, then `exit(0)`.
  /// The swap can begin as soon as this process releases its files, which
  /// is why it needs no pid to wait for. Returns false (and keeps SALU
  /// alive) when Windows refused the spawn: killing SALU over an update
  /// that will never apply helps nobody.
  Future<bool> applyAndExit({
    required String stagingDir,
    required String targetDir,
    required String saluExe,
    bool relaunch = true,
  }) async {
    final bool started = await startSwap(
      stagingDir: stagingDir,
      targetDir: targetDir,
      saluExe: saluExe,
      relaunch: relaunch,
    );
    if (started) exitApp();
    return started;
  }

  /// The leftovers a swap cannot clean up behind itself: the script, the
  /// lock, and a `.old` that survived because SALU was killed between the
  /// rename and the delete. Called on every startup (updater.md §10), so
  /// an interrupted swap never leaves litter or a blocked lock — and never
  /// deletes a `.old` the still-running SALU itself is mapped from.
  void sweepSwapLeftovers({
    required String targetDir,
    required String stagingDir,
  }) {
    final DateTime nowAt = clock();
    for (final String name in <String>[swapScriptName, swapLockName]) {
      final File file = File(p.join(swapTempRootOf(stagingDir), name));
      try {
        if (!file.existsSync()) continue;
        // Young leftovers belong to a swap that may be running right now.
        if (nowAt.difference(file.lastModifiedSync()) < swapLockLifetime) {
          continue;
        }
        file.deleteSync();
      } catch (_) {
        // Locked or gone — the next startup sweeps again.
      }
    }
    for (final String fileName in swapComponentFiles) {
      final File old = File(p.join(targetDir, '$fileName.old'));
      try {
        // Only once the real file is in place — and never the file some
        // other process may still be running from.
        if (old.existsSync() && File(p.join(targetDir, fileName)).existsSync()) {
          old.deleteSync();
        }
      } catch (_) {
        // Same: harmless litter, retried at the next startup.
      }
    }
  }

  void _stampLock(String lockPath) {
    try {
      File(lockPath).writeAsStringSync(
        '$pid ${clock().toIso8601String()}\r\n',
        flush: true,
      );
    } catch (_) {
      // A lock we cannot write is a lock that cannot block anyone.
    }
  }

  void _clearLock(String lockPath) {
    try {
      File(lockPath).deleteSync();
    } catch (_) {}
  }
}

Future<void> _writeScript(String scriptPath) async {
  final Directory dir = File(scriptPath).parent;
  if (!dir.existsSync()) await dir.create(recursive: true);
  await File(scriptPath).writeAsString(saluUpdaterScript, flush: true);
}

Future<bool> _spawnScript(
  String scriptPath,
  Map<String, String> environment,
) async {
  try {
    await Process.start(
      'cmd.exe',
      swapCommandLine(scriptPath),
      environment: environment,
      // Detached: no console of ours, no handles to inherit, and nothing
      // that ties the script's life to this process's. The script's very
      // first step gives itself a hidden one (§6.1), which is what keeps
      // every tool it runs from opening its own window.
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// True when SALU can create a file in [targetDir] — the honest test for
/// whether a swap can land there at all (`Program Files` says no without
/// elevation, and a swap that only discovers that mid-flight strands the
/// user between two versions).
bool _installRootWritable(String targetDir) {
  final File probe = File(p.join(targetDir, '.salu_swap_write_probe'));
  try {
    probe.writeAsStringSync('probe', flush: true);
    probe.deleteSync();
    return true;
  } catch (_) {
    try {
      if (probe.existsSync()) probe.deleteSync();
    } catch (_) {}
    return false;
  }
}

DateTime? _lockStampedAt(String lockPath) {
  try {
    final File lock = File(lockPath);
    if (!lock.existsSync()) return null;
    return lock.lastModifiedSync();
  } catch (_) {
    return null;
  }
}

void _exitApp() => exit(0);
