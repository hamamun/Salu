import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/updater/update_installer_windows.dart';

import 'updater_test_support.dart';

/// The Windows swap half (updater.md §2, §6, §9): the x64 architecture
/// guard, the detached `salu_updater.bat` (its steps and its CRLF safety),
/// and the command line that launches it.

void main() {
  group('isX64PeImage', () {
    test('accepts a 64-bit x86-64 PE', () {
      expect(isX64PeImage(fakePeImage()), isTrue);
    });

    test('refuses 32-bit x86 and ARM64 (updater.md §9 · Architecture Guard)',
        () {
      expect(isX64PeImage(fakePeImage(machine: 0x014c)), isFalse,
          reason: 'x86 must never enter a 64-bit install');
      expect(isX64PeImage(fakePeImage(machine: 0xAA64)), isFalse);
    });

    test('refuses anything that is not a PE at all', () {
      expect(isX64PeImage(<int>[]), isFalse);
      expect(isX64PeImage(List<int>.filled(100, 0)), isFalse);
      expect(isX64PeImage('<html>404 Not Found</html>'.codeUnits), isFalse,
          reason: 'a captive portal page must never become a DLL');
      expect(isX64PeImage(fakePeImage(withPeHeader: false)), isFalse);
    });

    test('refuses a truncated header', () {
      final List<int> truncated = fakePeImage().sublist(0, 10);
      expect(isX64PeImage(truncated), isFalse);
    });
  });

  group('saluUpdaterScript', () {
    test('carries every step of the §6 pipeline', () {
      const String s = saluUpdaterScript;
      // 1. Wait for SALU to exit and release file locks.
      expect(s, contains(':WAIT_LOOP'));
      expect(s, contains('tasklist /fi "PID eq %SALU_PID%"'));
      expect(s, contains('goto WAIT_LOOP'));
      // Extra safety margin.
      expect(s, contains('timeout /t 1 /nobreak >nul'));
      // 2. Backup.
      expect(s, contains('"%TARGET_DIR%\\backup"'));
      expect(s, contains('copy /y "%TARGET_DIR%\\WebView2Loader.dll"'));
      expect(s, contains('copy /y "%TARGET_DIR%\\libmpv-2.dll"'));
      expect(s, contains('copy /y "%TARGET_DIR%\\yt-dlp.exe"'));
      // 3. Copy new files + rollback.
      expect(s, contains('copy /y "%STAGING_DIR%\\WebView2Loader.dll"'));
      expect(s, contains('copy /y "%STAGING_DIR%\\libmpv-2.dll"'));
      expect(s, contains('copy /y "%STAGING_DIR%\\yt-dlp.exe"'));
      expect(s, contains('COPY_FAILED'));
      expect(s, contains('copy /y "%TARGET_DIR%\\backup\\*.*"'));
      expect(s, contains('msg * "SALU Update failed. Previous files restored."'));
      // 4. manifest.json → versions.json.
      expect(s, contains('"%STAGING_DIR%\\manifest.json"'));
      expect(s, contains('"%TARGET_DIR%\\versions.json"'));
      // 5. Cleanup.
      expect(s, contains('rmdir /s /q "%STAGING_DIR%"'));
      expect(s, contains('rmdir /s /q "%TARGET_DIR%\\backup"'));
      // 6. Relaunch, gated on the RELAUNCH flag.
      expect(s, contains('start "" "%SALU_EXE%"'));
      expect(s, contains('if not "%RELAUNCH%"=="0"'));
    });

    test('waits on the PID and takes its three arguments', () {
      expect(saluUpdaterScript, contains('set SALU_PID=%~1'));
      expect(saluUpdaterScript, contains('set TARGET_DIR=%~2'));
      expect(saluUpdaterScript, contains('set STAGING_DIR=%~3'));
    });

    test('is CRLF-terminated — cmd goto is not safe over LF-only files', () {
      expect(saluUpdaterScript, contains('\r\n'));
      expect(saluUpdaterScript.replaceAll('\r\n', ''), isNot(contains('\n')),
          reason: 'no bare LF anywhere');
    });

    test('never copies the script or manifest into the install root', () {
      // The §6 sketch's `copy staging\*.*` would leak both; the shipped
      // script copies the three component files only.
      expect(saluUpdaterScript, isNot(contains('copy /y "%STAGING_DIR%\\*.*"')));
    });
  });

  group('updaterProcessArguments', () {
    test('shapes the detached cmd call', () {
      final List<String> args = updaterProcessArguments(
        scriptPath: r'C:\Temp\salu_update\salu_updater.bat',
        saluPid: 4242,
        targetDir: r'C:\Program Files\Salu',
        stagingDir: r'C:\Users\me\AppData\Local\Temp\salu_update',
      );
      expect(args, <String>[
        '/c',
        r'C:\Temp\salu_update\salu_updater.bat',
        '4242',
        r'C:\Program Files\Salu',
        r'C:\Users\me\AppData\Local\Temp\salu_update',
        '1',
      ]);
    });

    test('relaunch off is the Restart Later / close-time shape', () {
      final List<String> args = updaterProcessArguments(
        scriptPath: 's.bat',
        saluPid: 1,
        targetDir: 't',
        stagingDir: 'st',
        relaunch: false,
      );
      expect(args.last, '0');
    });
  });

  group('UpdateInstallerWindows', () {
    test('writes the script, spawns it, and relaunches — the Restart Now flow',
        () async {
      final List<String> calls = <String>[];
      bool exited = false;
      final UpdateInstallerWindows installer = UpdateInstallerWindows(
        scriptWriter: (String stagingDir) async {
          calls.add('write:$stagingDir');
          return '$stagingDir\\salu_updater.bat';
        },
        spawner: (String scriptPath, int saluPid, String targetDir,
            String stagingDir, bool relaunch) async {
          calls.add('spawn:$scriptPath:$saluPid:$targetDir:$relaunch');
          return true;
        },
        exitApp: () => exited = true,
      );

      await installer.applyAndExit(
        stagingDir: r'C:\Temp\salu_update',
        targetDir: r'C:\Salu',
        saluPid: 99,
      );

      expect(calls, <String>[
        r'write:C:\Temp\salu_update',
        r'spawn:C:\Temp\salu_update\salu_updater.bat:99:C:\Salu:true',
      ]);
      expect(exited, isTrue);
    });

    test('a refused spawn never kills SALU', () async {
      bool exited = false;
      final UpdateInstallerWindows installer = UpdateInstallerWindows(
        scriptWriter: (String stagingDir) async => 's.bat',
        spawner: (String scriptPath, int saluPid, String targetDir,
                String stagingDir, bool relaunch) async =>
            false,
        exitApp: () => exited = true,
      );

      final bool started = await installer.applyAndExit(
        stagingDir: 'st',
        targetDir: 't',
        saluPid: 1,
      );

      expect(started, isFalse);
      expect(exited, isFalse);
    });

    test('the close-time swap spawns with relaunch off and does not exit',
        () async {
      bool? relaunchArg;
      bool exited = false;
      final UpdateInstallerWindows installer = UpdateInstallerWindows(
        scriptWriter: (String stagingDir) async => 's.bat',
        spawner: (String scriptPath, int saluPid, String targetDir,
            String stagingDir, bool relaunch) async {
          relaunchArg = relaunch;
          return true;
        },
        exitApp: () => exited = true,
      );

      final bool started = await installer.startSwap(
        stagingDir: 'st',
        targetDir: 't',
        saluPid: 1,
        relaunch: false,
      );

      expect(started, isTrue);
      expect(relaunchArg, isFalse);
      expect(exited, isFalse);
    });
  });
}
