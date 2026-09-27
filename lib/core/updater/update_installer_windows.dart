/// SALU's Windows swap step (updater.md §2, §5–§6, §9): the tiny detached
/// updater script, the way it is spawned, and the x64 architecture guard
/// every staged binary must pass before it is allowed into the
/// installation root.
///
/// Windows will not let SALU overwrite the DLLs it is running from — so the
/// new files are staged in `%TEMP%\salu_update\`, this script waits for
/// SALU to exit, swaps with a backup + rollback, and relaunches (or stays
/// down when the swap rides a normal close).
library;

import 'dart:io';

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

/// The detached swap script (updater.md §6), with CRLF endings — cmd's
/// `goto` over LF-only batch files is not a safe bet.
///
/// Deliberate tightening of the §6 sketch, same steps: step 3 copies the
/// three **component files** instead of `staging\*.*`, so the script and
/// `manifest.json` never leak into the installation root — and so the
/// rollback of step 3's failure path restores exactly the set the backup
/// of step 2 saved. `manifest.json` still lands as `versions.json` (step
/// 4), verbatim.
///
/// Arguments: `SALU_PID TARGET_DIR STAGING_DIR [RELAUNCH]`.
/// `RELAUNCH` defaults to `1` (the §6 restart-now flow, step 6). Passing
/// `0` turns the same script into updater.md §8's "Restart Later" applier:
/// the swap rides the next normal close and SALU stays down.
const String saluUpdaterScript =
    '@echo off\r\n'
    'setlocal enabledelayedexpansion\r\n'
    '\r\n'
    'set SALU_PID=%~1\r\n'
    'set TARGET_DIR=%~2\r\n'
    'set STAGING_DIR=%~3\r\n'
    'set SALU_EXE=%TARGET_DIR%\\salu.exe\r\n'
    'set RELAUNCH=%~4\r\n'
    'if "%RELAUNCH%"=="" set RELAUNCH=1\r\n'
    '\r\n'
    ':: 1. Wait for SALU to exit and release file locks\r\n'
    ':WAIT_LOOP\r\n'
    'tasklist /fi "PID eq %SALU_PID%" | findstr /i "%SALU_PID%" >nul\r\n'
    'if not errorlevel 1 (\r\n'
    '    timeout /t 1 /nobreak >nul\r\n'
    '    goto WAIT_LOOP\r\n'
    ')\r\n'
    '\r\n'
    ':: Extra 1s safety margin for DLL handles to release completely\r\n'
    'timeout /t 1 /nobreak >nul\r\n'
    '\r\n'
    ':: 2. Create backup\r\n'
    'if not exist "%TARGET_DIR%\\backup" mkdir "%TARGET_DIR%\\backup"\r\n'
    'if exist "%STAGING_DIR%\\WebView2Loader.dll" copy /y "%TARGET_DIR%\\WebView2Loader.dll" "%TARGET_DIR%\\backup\\" >nul\r\n'
    'if exist "%STAGING_DIR%\\libmpv-2.dll" copy /y "%TARGET_DIR%\\libmpv-2.dll" "%TARGET_DIR%\\backup\\" >nul\r\n'
    'if exist "%STAGING_DIR%\\yt-dlp.exe" copy /y "%TARGET_DIR%\\yt-dlp.exe" "%TARGET_DIR%\\backup\\" >nul\r\n'
    '\r\n'
    ':: 3. Copy new files\r\n'
    'set COPY_FAILED=0\r\n'
    'if exist "%STAGING_DIR%\\WebView2Loader.dll" (\r\n'
    '    copy /y "%STAGING_DIR%\\WebView2Loader.dll" "%TARGET_DIR%\\" >nul\r\n'
    '    if errorlevel 1 set COPY_FAILED=1\r\n'
    ')\r\n'
    'if exist "%STAGING_DIR%\\libmpv-2.dll" (\r\n'
    '    copy /y "%STAGING_DIR%\\libmpv-2.dll" "%TARGET_DIR%\\" >nul\r\n'
    '    if errorlevel 1 set COPY_FAILED=1\r\n'
    ')\r\n'
    'if exist "%STAGING_DIR%\\yt-dlp.exe" (\r\n'
    '    copy /y "%STAGING_DIR%\\yt-dlp.exe" "%TARGET_DIR%\\" >nul\r\n'
    '    if errorlevel 1 set COPY_FAILED=1\r\n'
    ')\r\n'
    'if !COPY_FAILED! equ 1 (\r\n'
    '    :: Rollback on failure\r\n'
    '    copy /y "%TARGET_DIR%\\backup\\*.*" "%TARGET_DIR%\\" >nul\r\n'
    '    msg * "SALU Update failed. Previous files restored."\r\n'
    '    if not "%RELAUNCH%"=="0" start "" "%SALU_EXE%"\r\n'
    '    exit /b 1\r\n'
    ')\r\n'
    '\r\n'
    ':: 4. Update versions file\r\n'
    'if exist "%STAGING_DIR%\\manifest.json" copy /y "%STAGING_DIR%\\manifest.json" "%TARGET_DIR%\\versions.json" >nul\r\n'
    '\r\n'
    ':: 5. Clean up staging folder\r\n'
    'rmdir /s /q "%STAGING_DIR%"\r\n'
    'rmdir /s /q "%TARGET_DIR%\\backup"\r\n'
    '\r\n'
    ':: 6. Relaunch SALU\r\n'
    'if not "%RELAUNCH%"=="0" start "" "%SALU_EXE%"\r\n'
    'exit /b 0\r\n';

/// The file name the script is written as under `%TEMP%\salu_update\`
/// (updater.md §5).
const String updaterScriptName = 'salu_updater.bat';

/// Builds the detached command: `cmd.exe /c salu_updater.bat PID TARGET
/// STAGING RELAUNCH`. Everything the script cannot safely derive is an
/// argument; the script strips quotes itself (`%~1`).
List<String> updaterProcessArguments({
  required String scriptPath,
  required int saluPid,
  required String targetDir,
  required String stagingDir,
  bool relaunch = true,
}) {
  return <String>[
    '/c',
    scriptPath,
    '$saluPid',
    targetDir,
    stagingDir,
    relaunch ? '1' : '0',
  ];
}

/// How a swap is spawned and how SALU leaves — the two OS touches of the
/// restart flow, behind seams so tests never kill their own runner.
class UpdateInstallerWindows {
  UpdateInstallerWindows({
    this.scriptWriter = _writeScript,
    this.spawner = _spawnScript,
    this.exitApp = _exitApp,
  });

  /// Writes `salu_updater.bat` into the staging directory.
  final Future<String> Function(String stagingDir) scriptWriter;

  /// Spawns `cmd.exe /c salu_updater.bat …` detached (updater.md §5:
  /// "Spawn script detached"). Returns false when Windows refused.
  final Future<bool> Function(String scriptPath, int saluPid, String targetDir,
      String stagingDir, bool relaunch) spawner;

  /// Ends the process — `exit(0)`, updater.md §8's "SALU exits: exit(0)".
  final void Function() exitApp;

  /// Writes the script and spawns it detached. `relaunch: true` = the
  /// script restarts SALU when done ("Restart Now"); `false` = it only
  /// swaps ("Restart Later", riding the close).
  Future<bool> startSwap({
    required String stagingDir,
    required String targetDir,
    required int saluPid,
    bool relaunch = true,
  }) async {
    final String scriptPath = await scriptWriter(stagingDir);
    return spawner(scriptPath, saluPid, targetDir, stagingDir, relaunch);
  }

  /// updater.md §8's `[ Restart Now ]`: spawn the swap, then `exit(0)`.
  /// The script holds the PID and waits — the swap can only begin once
  /// this process is gone. Returns false (and stays alive) when Windows
  /// refused the spawn: killing SALU over an update that will never apply
  /// helps nobody.
  Future<bool> applyAndExit({
    required String stagingDir,
    required String targetDir,
    required int saluPid,
  }) async {
    final bool started = await startSwap(
      stagingDir: stagingDir,
      targetDir: targetDir,
      saluPid: saluPid,
      relaunch: true,
    );
    if (started) exitApp();
    return started;
  }
}

Future<String> _writeScript(String stagingDir) async {
  final Directory dir = Directory(stagingDir);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final File script = File('$stagingDir${Platform.pathSeparator}$updaterScriptName');
  await script.writeAsString(saluUpdaterScript, flush: true);
  return script.path;
}

Future<bool> _spawnScript(
  String scriptPath,
  int saluPid,
  String targetDir,
  String stagingDir,
  bool relaunch,
) async {
  try {
    await Process.start(
      'cmd.exe',
      updaterProcessArguments(
        scriptPath: scriptPath,
        saluPid: saluPid,
        targetDir: targetDir,
        stagingDir: stagingDir,
        relaunch: relaunch,
      ),
      // Detached: no console of ours, no handles to inherit, and nothing
      // that ties the script's life to this process's.
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}

void _exitApp() => exit(0);
