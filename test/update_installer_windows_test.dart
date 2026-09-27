import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:salu/core/updater/update_installer_windows.dart';
import 'package:salu/core/updater/update_manifest.dart';

import 'updater_test_support.dart';

/// The Windows swap half (updater.md §2, §6, §6.1, §9, §10): the x64
/// architecture guard, the detached script, and the guards SALU runs before
/// it hands the swap over.
///
/// These assert the SHAPE the script has to obey, not its wording. The
/// previous version of this file pinned phrases — `tasklist /fi "PID eq …"`,
/// `timeout /t 1 /nobreak` — and so helped ship the very loop that filled the
/// desktop with flashing cmd windows. An assertion that a bug is present is
/// worse than no assertion at all.

/// The script's lines, trailing CRLF folded away.
List<String> get _scriptLines => saluUpdaterScript
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((String line) => line.isNotEmpty)
    .toList();

/// Only what cmd actually runs — the `rem` lines dropped. Several rules below
/// are "this must NOT appear", and the comments that explain the old, broken
/// design name the very tools the rules forbid; an assertion that reads the
/// prose can be satisfied or broken by a sentence, which is no rule at all.
String get _scriptCode => _scriptLines
    .where((String line) => !line.trim().startsWith('rem'))
    .join('\n');

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

  group('the component list', () {
    test('is exactly what UpdateComponent owns, in slot order', () {
      // The script names the three files literally (cmd has no imports), so
      // the two lists are pinned here — drift would mean a component that is
      // downloaded, verified, and then never installed.
      expect(
        swapComponentFiles,
        UpdateComponent.values
            .map((UpdateComponent c) => c.fileName)
            .toList(),
      );
    });
  });

  group('saluUpdaterScript · the two rules that used to be broken', () {
    test('waits on no process id, anywhere', () {
      // The window storm came from polling SALU's pid: a recycled pid — or
      // those same digits turning up in another column of tasklist's output —
      // makes that loop wait forever. The swap now reacts to "this file is
      // busy", which is the only fact it ever needed.
      expect(_scriptCode, isNot(contains('tasklist')));
      expect(_scriptCode, isNot(contains('findstr')));
      expect(_scriptCode, isNot(contains('SALU_PID')));
      expect(_scriptCode, isNot(contains('/fi "PID eq')));
      // …and the pid is not even handed over any more.
      expect(swapCommandLine(swapScriptName), <String>['/c', swapScriptName]);
    });

    test('pauses with something that needs no keyboard', () {
      // `timeout` refuses to wait when its stdin is not a console — which is
      // exactly what a detached process has — so every pass of the old loop
      // ran immediately and opened a fresh window while doing it.
      expect(_scriptCode, isNot(contains('timeout')));
      expect(saluUpdaterScript, contains('ping -n'));
      // Bounded: a pause that outlives its patience is a stuck window.
      expect(saluUpdaterScript, contains('set MAX=$swapAttempts'));
    });

    test('gives the whole run one hidden console, before any tool runs', () {
      // A console-less parent hands EVERY console tool it starts a window of
      // its own. Step 0 re-runs the script under `start /min`, so the tools
      // share one minimized console instead of flashing a new one per pass.
      expect(saluUpdaterScript, contains(swapEnvHidden));
      expect(saluUpdaterScript, contains('start "" /min cmd.exe /c "%~f0"'));
      final int hide = saluUpdaterScript.indexOf('start "" /min');
      expect(hide, greaterThan(0));
      expect(hide, lessThan(saluUpdaterScript.indexOf('ping -n')),
          reason: 'the hidden console must exist before the first tool runs');
      expect(hide, lessThan(saluUpdaterScript.indexOf('copy /y')));
    });

    test('takes its whole job from the environment, never from argv', () {
      for (final String key in <String>[
        swapEnvTarget,
        swapEnvStaging,
        swapEnvExe,
        swapEnvRelaunch,
        swapEnvLock,
      ]) {
        expect(saluUpdaterScript, contains(key), reason: '$key must be read');
      }
      // One quoted path on a cmd command line is one path cmd can re-split
      // in the wrong place; `%~1`-style reads of the OUTER arguments are gone.
      expect(swapCommandLine(swapScriptName).length, 2);
      expect(_scriptCode, isNot(contains('set TARGET=%~')));
    });
  });

  group('saluUpdaterScript · the swap itself', () {
    test('is CRLF-terminated — cmd goto is not safe over LF-only files', () {
      expect(saluUpdaterScript, contains('\r\n'));
      expect(saluUpdaterScript.replaceAll('\r\n', ''), isNot(contains('\n')),
          reason: 'no bare LF anywhere');
    });

    test('is pure ASCII — cmd reads a .bat in the console OEM codepage', () {
      for (final int unit in saluUpdaterScript.codeUnits) {
        expect(unit, lessThan(0x80),
            reason: 'non-ASCII byte $unit: it would echo as mojibake');
      }
    });

    test('every block opens and closes (cmd parses by parenthesis)', () {
      // One stray `)` in an echo line ends a block early and the rest of the
      // script then runs outside it — silently, halfway through a swap.
      // Checked structurally, with quoted text and echo payloads set aside.
      int depth = 0;
      for (final String line in _scriptLines) {
        final String t = line.trim();
        if (t.isEmpty ||
            t.startsWith('rem') ||
            t.startsWith(':') ||
            t.startsWith('@echo')) {
          continue;
        }
        String code = t.replaceAll(RegExp(r'"[^"]*"'), '""');
        final int echo = code.indexOf('echo ');
        if (echo >= 0) code = code.substring(0, echo);
        final int opens = '('.allMatches(code).length;
        final int closes = ')'.allMatches(code).length;
        depth += opens - closes;
        expect(depth, greaterThanOrEqualTo(0),
            reason: 'block closed early: $t');
      }
      expect(depth, 0, reason: 'a block was left open to the end of the file');
    });

    test('copies the three component files only, never the whole folder', () {
      for (int i = 0; i < swapComponentFiles.length; i++) {
        expect(
          saluUpdaterScript,
          contains('call :SWAP ${i + 1} ${swapComponentFiles[i]}'),
        );
      }
      // `copy staging\*.*` was the §6 sketch. It dropped the script itself and
      // manifest.json into the installation root, and its rollback restored a
      // wider set than the one it had backed up.
      expect(_scriptCode, isNot(contains('copy /y "%STAGING%\\*.*"')));
      expect(_scriptCode, isNot(contains('\\*.*')));
    });

    test('rolls back by rename, and reads errorlevel only where it is honest',
        () {
      // errorlevel is ONE slot every command writes, and 0 is what any
      // successful command stores last. Inside a ( ) block — and after a call
      // — it is the PREVIOUS command's value: that is how the old script
      // reached its copy step with the backup never made, and how it decided
      // every file had copied when none had.
      final int start = _scriptCode.indexOf('\n:SWAP\n');
      expect(start, greaterThan(0), reason: 'the swap subroutine exists');
      final String swap = _scriptCode.substring(start);
      expect(swap, isNot(contains('if errorlevel')),
          reason: 'a block reads a stale errorlevel');
      expect(swap, isNot(contains('setlocal')));
      expect(saluUpdaterScript, contains('setlocal enabledelayedexpansion'));
      expect(
        swap,
        contains('ren "%TARGET%\\%~2" "%~2.old"'),
        reason: 'the old file is moved aside, not overwritten — that rename is '
            'what Windows still allows while SALU is closing',
      );
      expect(swap, contains('set "DONE%~1=1"'),
          reason: 'a swapped slot is remembered, so a retry never mistakes the '
              'new file for the old one');
      expect(saluUpdaterScript, contains('if "!DONE1!"=="1" call :RESTORE'),
          reason: 'the failure path restores per slot, with delayed expansion');
    });

    test('promotes versions.json only when every file made it', () {
      expect(saluUpdaterScript, contains('\\versions.json"'));
      final int failed = saluUpdaterScript.indexOf('swap FAILED');
      final int jump = saluUpdaterScript.indexOf('goto :FINISH', failed);
      final int promote = saluUpdaterScript.indexOf('versions.json');
      expect(jump, greaterThan(failed), reason: 'the failed path must leave :OK');
      expect(promote, greaterThan(jump),
          reason: 'versions.json is written in :OK, after the failed path has '
              'jumped past it — a failed swap can never make the store lie');
    });

    test('keeps staging when the swap failed, cleans it when it did not', () {
      expect(saluUpdaterScript, contains('set KEEP_STAGING=1'));
      expect(saluUpdaterScript,
          contains('if not "%KEEP_STAGING%"=="1" rd /s /q "%STAGING%"'));
    });

    test('never deletes the folder it is running from', () {
      // cmd reads a .bat as it goes: deleting the script mid-run is how the
      // relaunch line silently stopped existing at all.
      // Built with p.join from a relative root: what an absolute path equals
      // depends on whose separator the platform canonicalises to, and that is
      // not the fact under test.
      final String staging = p.join('T', 'salu_update');
      expect(swapScriptPathFor(staging), p.join('T', swapScriptName));
      expect(swapLockPathFor(staging), p.join('T', swapLockName));
      expect(swapLogPathFor(staging), p.join('T', swapLogName));
      expect(p.isWithin(staging, swapScriptPathFor(staging)), isFalse,
          reason: 'a script inside the folder it cleans can be cleaned away '
              'while it is still being read');
      expect(_scriptCode, isNot(contains(swapScriptName)),
          reason: 'the script must not name itself as a file to clean');
    });

    test('reopening SALU is gated, and gated late', () {
      expect(saluUpdaterScript, contains('if not "%RELAUNCH%"=="0"'));
      expect(saluUpdaterScript, contains('start "" "%EXE%"'));
      final int relaunch = saluUpdaterScript.indexOf('start "" "%EXE%"');
      expect(saluUpdaterScript.lastIndexOf('ping -n'), lessThan(relaunch),
          reason: 'the dying SALU still holds the single-instance mutex; '
              'starting into it makes the new instance forward and quit');
      // `msg` used to announce a failure — it does not exist on Windows Home,
      // so the announcement was the part that broke.
      expect(_scriptCode, isNot(contains('msg *')));
    });

    test('logs both outcomes where the swap cannot delete it', () {
      expect(saluUpdaterScript, contains('salu_swap.log'));
      expect(saluUpdaterScript, contains('swap OK'));
      expect(saluUpdaterScript, contains('swap FAILED'));
      expect(saluUpdaterScript, contains('still held by SALU'));
      expect(saluUpdaterScript, contains('could not write'));
    });
  });

  group('swapEnvironment', () {
    test('carries the job, the exe to reopen, and the lock to release', () {
      final Map<String, String> env = swapEnvironment(
        targetDir: r'C:\Users\me\Programs\Salu',
        stagingDir: r'C:\Users\me\AppData\Local\Temp\salu_update',
        saluExe: r'C:\Users\me\Programs\Salu\salu.exe',
        lockPath: r'C:\Users\me\AppData\Local\Temp\salu_swap.lock',
      );
      expect(env[swapEnvTarget], r'C:\Users\me\Programs\Salu');
      expect(env[swapEnvStaging], r'C:\Users\me\AppData\Local\Temp\salu_update');
      expect(env[swapEnvExe], r'C:\Users\me\Programs\Salu\salu.exe');
      expect(env[swapEnvRelaunch], '1');
      expect(env[swapEnvLock], r'C:\Users\me\AppData\Local\Temp\salu_swap.lock');
    });

    test('relaunch off is the Restart Later / close-time / dev-build shape', () {
      final Map<String, String> env = swapEnvironment(
        targetDir: 't',
        stagingDir: 's',
        saluExe: 'e',
        relaunch: false,
      );
      expect(env[swapEnvRelaunch], '0');
      expect(env.containsKey(swapEnvLock), isFalse,
          reason: 'no lock path means the script has nothing to release');
    });
  });

  group('the guards SALU runs before handing off', () {
    late List<String> calls;
    late bool exited;

    UpdateInstallerWindows fakeInstaller({
      bool writable = true,
      DateTime? lockStampedAt,
      DateTime Function()? clock,
      bool spawnOk = true,
      bool windowsHost = true,
    }) {
      calls = <String>[];
      exited = false;
      return UpdateInstallerWindows(
        scriptWriter: (String scriptPath) async {
          calls.add('write:$scriptPath');
        },
        spawner: (String scriptPath, Map<String, String> env) async {
          calls.add('spawn:${env[swapEnvTarget]}:${env[swapEnvRelaunch]}');
          return spawnOk;
        },
        exitApp: () => exited = true,
        writability: (String targetDir) => writable,
        lockReader: (String lockPath) => lockStampedAt,
        clock: clock ?? DateTime.now,
        isWindowsHost: windowsHost,
      );
    }

    test('a protected install root is refused BEFORE anything is written',
        () async {
      final UpdateInstallerWindows installer = fakeInstaller(writable: false);
      await expectLater(
        installer.startSwap(
          stagingDir: r'C:\T\salu_update',
          targetDir: r'C:\Program Files\Salu',
          saluExe: r'C:\Program Files\Salu\salu.exe',
        ),
        throwsA(isA<UpdateSwapRefusedException>()),
      );
      expect(calls, isEmpty,
          reason: 'a swap that cannot land must not be written, and SALU must '
              'not exit in front of it');
      expect(exited, isFalse);
    });

    test('the refusal says what to do, and never blames the internet', () {
      final UpdateInstallerWindows installer = fakeInstaller(writable: false);
      final String reason =
          installer.refusal(targetDir: 'x', stagingDir: 'y')!;
      expect(reason, contains('Program Files'));
      expect(reason, isNot(contains('internet')));
      expect(reason, isNot(contains('UpdateSwapRefusedException')));
    });

    test('a fresh lock means one swap at a time; a stale one does not', () {
      final DateTime t = DateTime(2026, 9, 27, 12);
      expect(
        fakeInstaller(
          lockStampedAt: t,
          clock: () => t.add(const Duration(minutes: 1)),
        ).refusal(targetDir: 'x', stagingDir: 'y'),
        contains('still being applied'),
      );
      expect(
        fakeInstaller(
          lockStampedAt: t,
          clock: () => t.add(swapLockLifetime + const Duration(minutes: 1)),
        ).refusal(targetDir: 'x', stagingDir: 'y'),
        isNull,
        reason: 'a swap killed before its cleanup must never block SALU '
            'forever',
      );
    });

    test('a refused spawn leaves no lock behind', () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('salu_swap_refused');
      final String staging = p.join(temp.path, 'salu_update');
      final UpdateInstallerWindows installer =
          fakeInstaller(spawnOk: false);
      final bool started = await installer.startSwap(
        stagingDir: staging,
        targetDir: temp.path,
        saluExe: p.join(temp.path, 'salu.exe'),
      );
      expect(started, isFalse);
      expect(exited, isFalse,
          reason: 'killing SALU over an update that will never apply helps '
              'nobody');
      expect(File(swapLockPathFor(staging)).existsSync(), isFalse,
          reason: 'a lock nobody will release must not survive the attempt');
      await temp.delete(recursive: true);
    });

    test('the handoff writes beside staging, spawns it, and then exits',
        () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('salu_swap_handoff');
      final String staging = p.join(temp.path, 'salu_update');
      final UpdateInstallerWindows installer = fakeInstaller();
      final bool started = await installer.applyAndExit(
        stagingDir: staging,
        targetDir: temp.path,
        saluExe: p.join(temp.path, 'salu.exe'),
      );
      expect(started, isTrue);
      expect(exited, isTrue);
      expect(calls.first, 'write:${swapScriptPathFor(staging)}');
      expect(calls.last, 'spawn:${temp.path}:1');
      await temp.delete(recursive: true);
    });

    test('the default seams really write the script — beside staging', () async {
      // Everything else in this file reads the const; this checks the writer
      // that production actually uses, including WHERE it puts the file. A
      // script inside the folder it cleans is a script that can be cleaned
      // away halfway through running.
      final Directory temp =
          await Directory.systemTemp.createTemp('salu_swap_default');
      final String staging = p.join(temp.path, 'salu_update');
      Directory(staging).createSync();
      final UpdateInstallerWindows installer = UpdateInstallerWindows(
        spawner: (String scriptPath, Map<String, String> env) async => false,
        writability: (String targetDir) => true,
        lockReader: (String lockPath) => null,
      );
      final bool started = await installer.startSwap(
        stagingDir: staging,
        targetDir: temp.path,
        saluExe: p.join(temp.path, 'salu.exe'),
      );
      expect(started, isFalse, reason: 'the fake spawner says Windows refused');
      final File script = File(swapScriptPathFor(staging));
      expect(script.existsSync(), isTrue,
          reason: 'the default writer writes what it says it wrote');
      expect(script.readAsStringSync(), saluUpdaterScript);
      expect(p.isWithin(staging, script.path), isFalse);
      expect(File(swapLockPathFor(staging)).existsSync(), isFalse,
          reason: 'a spawn Windows refused must not leave a lock behind');
      await temp.delete(recursive: true);
    });

    test('a non-Windows host says so instead of pretending', () {
      expect(
        fakeInstaller(windowsHost: false)
            .refusal(targetDir: 'x', stagingDir: 'y'),
        contains('Windows'),
      );
    });
  });

  group('sweepSwapLeftovers', () {
    test('removes stale leftovers, keeps what a live swap still owns',
        () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('salu_sweep_leftovers');
      final String staging = p.join(temp.path, 'salu_update');
      Directory(staging).createSync();
      final DateTime lastWeek = DateTime(2026, 9, 20);
      final File script = File(swapScriptPathFor(staging))
        ..createSync()
        ..setLastModifiedSync(lastWeek);
      final File lock = File(swapLockPathFor(staging))
        ..createSync()
        ..setLastModifiedSync(lastWeek);
      // A swap that renamed and then died: the new file is in place, so the
      // .old is litter. The other has no new file yet — its .old is the ONLY
      // copy, and the live SALU may be mapped from it.
      final File dead = File(p.join(temp.path, 'WebView2Loader.dll.old'))
        ..writeAsStringSync('old');
      File(p.join(temp.path, 'libmpv-2.dll.old')).writeAsStringSync('old');
      File(p.join(temp.path, 'WebView2Loader.dll')).writeAsStringSync('new');

      UpdateInstallerWindows(
        clock: () => DateTime(2026, 9, 27, 12),
      ).sweepSwapLeftovers(targetDir: temp.path, stagingDir: staging);

      expect(script.existsSync(), isFalse);
      expect(lock.existsSync(), isFalse);
      expect(dead.existsSync(), isFalse);
      expect(File(p.join(temp.path, 'WebView2Loader.dll')).existsSync(), isTrue,
          reason: 'the sweep never touches a live file');
      expect(File(p.join(temp.path, 'libmpv-2.dll.old')).existsSync(), isTrue,
          reason: 'no new file in place — that .old is still the only copy');
      expect(Directory(staging).existsSync(), isTrue,
          reason: 'staging is the updater\'s business, not the sweep\'s');
      await temp.delete(recursive: true);
    });

    test('a young leftover belongs to a swap that may still be running',
        () async {
      final Directory temp =
          await Directory.systemTemp.createTemp('salu_sweep_live');
      final String staging = p.join(temp.path, 'salu_update');
      final File lock = File(swapLockPathFor(staging))..createSync();
      UpdateInstallerWindows().sweepSwapLeftovers(
        targetDir: temp.path,
        stagingDir: staging,
      );
      expect(lock.existsSync(), isTrue);
      await temp.delete(recursive: true);
    });
  });
}
