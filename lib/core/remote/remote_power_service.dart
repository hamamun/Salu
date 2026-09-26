import 'dart:ffi';
import 'dart:io';

/// Small Windows power service for remote sleep and shutdown (pc_part.md Part D ·
/// remote.md §17.15).
///
/// Respects Windows policy/privilege errors and unsaved-work prompts:
/// - Suspend for `pc_sleep` (`SetSuspendState` with no force).
/// - Normal shutdown for `pc_shutdown` (`ExitWindowsEx` / `shutdown.exe` without force).
/// Never force-closes apps.
class RemotePowerService {
  RemotePowerService({
    RemotePowerPlatform? platform,
  }) : _platform = platform ?? RemotePowerPlatform.platform();

  static final RemotePowerService instance = RemotePowerService();

  final RemotePowerPlatform _platform;

  /// Whether power operations are supported on this platform.
  bool get available => _platform.available;

  /// Suspend the system (sleep). Returns null on success, or a human-readable
  /// error explanation on failure.
  Future<String?> sleep() => _platform.sleep();

  /// Gracefully shut down the system. Returns null on success, or a human-readable
  /// error explanation on failure.
  Future<String?> shutdown() => _platform.shutdown();
}

abstract class RemotePowerPlatform {
  const RemotePowerPlatform();

  factory RemotePowerPlatform.platform() {
    if (!Platform.isWindows) return const UnavailablePowerPlatform();
    try {
      return Win32PowerPlatform();
    } catch (_) {
      return const UnavailablePowerPlatform();
    }
  }

  bool get available;
  Future<String?> sleep();
  Future<String?> shutdown();
}

class UnavailablePowerPlatform extends RemotePowerPlatform {
  const UnavailablePowerPlatform();

  @override
  bool get available => false;

  @override
  Future<String?> sleep() async => 'Power management is only supported on Windows.';

  @override
  Future<String?> shutdown() async => 'Power management is only supported on Windows.';
}

/// Windows implementation using Win32 API and system utilities.
///
/// Does NOT force-close applications (no EWX_FORCE, no shutdown /f) so
/// unsaved-work prompts and system policies are respected.
class Win32PowerPlatform extends RemotePowerPlatform {
  Win32PowerPlatform() {
    try {
      final DynamicLibrary powrprof = DynamicLibrary.open('powrprof.dll');
      _setSuspendState = powrprof.lookupFunction<
          Int32 Function(Int32, Int32, Int32),
          int Function(int, int, int)>('SetSuspendState');
    } catch (_) {
      _setSuspendState = null;
    }
  }

  int Function(int, int, int)? _setSuspendState;

  @override
  bool get available => true;

  @override
  Future<String?> sleep() async {
    // 1. Try SetSuspendState(0, 0, 0) via powrprof.dll (Hibernate=FALSE, ForceCritical=FALSE, DisableWakeEvent=FALSE)
    if (_setSuspendState != null) {
      try {
        final int result = _setSuspendState!(0, 0, 0);
        if (result != 0) return null;
      } catch (_) {}
    }

    // 2. Fallback via rundll32 powrprof.dll,SetSuspendState 0,1,0
    try {
      final ProcessResult res = await Process.run(
        'rundll32.exe',
        <String>['powrprof.dll,SetSuspendState', '0,1,0'],
      );
      if (res.exitCode == 0) return null;
      return 'Sleep command failed (code ${res.exitCode}).';
    } catch (e) {
      return 'Could not trigger sleep: $e';
    }
  }

  @override
  Future<String?> shutdown() async {
    // Graceful shutdown without force: shutdown.exe /s /t 0
    // (without /f, apps with unsaved work can block or prompt the user)
    try {
      final ProcessResult res = await Process.run(
        'shutdown.exe',
        <String>['/s', '/t', '0'],
      );
      if (res.exitCode == 0) return null;
      final String stderr = res.stderr.toString().trim();
      return stderr.isNotEmpty
          ? stderr
          : 'Shutdown command failed (code ${res.exitCode}).';
    } catch (e) {
      return 'Could not trigger shutdown: $e';
    }
  }
}
