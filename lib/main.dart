import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'core/media_utils.dart';
import 'core/player_service.dart';
import 'core/resume_service.dart';
import 'core/settings_service.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Phase 2 · Step 2: boot the mpv C++ engine before any UI draws. ────
  MediaKit.ensureInitialized();

  // ── Phase 1 · Step 6: strict single instance + file argument routing. ─
  // If SALU is already running and the user double-clicks a media file,
  // Windows launches a second process; its arguments are intercepted here,
  // forwarded to the live window, and the duplicate process exits.
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'salu_media_player_instance',
      onSecondWindow: (List<String> secondArgs) async {
        await windowManager.show();
        await windowManager.focus();
        final String? path = extractMediaPathFromArgs(secondArgs);
        if (path != null) {
          await PlayerService.instance.openPath(path);
        }
      },
    );
  }

  // ── Phase 1 · Step 2: borderless, centered, dark window. ─────────────
  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    title: 'SALU',
    size: Size(1280, 720),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    // Hide the default grey Windows title bar — SALU draws its own.
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // ── Close hook: flush the resume memory before the window dies. ──────
  // `setPreventClose(true)` routes the × button and Alt+F4 through
  // [_CloseGuard.onWindowClose] — one final position save, a disk flush,
  // engine release, then the real destroy. Covers every close path.
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseGuard());

  // ── Load persisted settings + resume memory before the first frame. ──
  await SettingsService.instance.load();
  await ResumeService.instance.load();

  runApp(SaluApp(initialFilePath: extractMediaPathFromArgs(args)));
}

/// Intercepts the window close: flush the resume store so the last
/// watched second is remembered, then close for real.
///
/// The native engine teardown (`player.dispose()`) is fired but NOT
/// awaited — mpv + D3D11/ANGLE resource release can take several
/// seconds during active hardware-decoded playback, and blocking the
/// window on it produces the OS "busy" cursor. The resume flush above
/// is the only thing that MUST reach disk before the window dies;
/// everything else the OS reclaims when `destroy()` kills the process.
class _CloseGuard with WindowListener {
  @override
  void onWindowClose() async {
    final PlayerService player = PlayerService.instance;
    final String? path = player.currentPath.value;
    if (path != null && player.duration.value > Duration.zero) {
      ResumeService.instance.update(
        path,
        player.position.value,
        player.duration.value,
      );
    }
    await ResumeService.instance.flush();
    unawaited(player.dispose());
    await windowManager.destroy();
  }
}

/// Picks the first argument that points to an existing, playable file.
String? extractMediaPathFromArgs(List<String> args) {
  for (final String rawArg in args) {
    // Windows may hand paths over wrapped in quotes.
    final String arg = rawArg.replaceAll('"', '').trim();
    if (arg.isEmpty || arg.startsWith('--')) continue;
    if (File(arg).existsSync() &&
        (MediaUtils.isMedia(arg) || MediaUtils.isPlaylist(arg))) {
      return arg;
    }
  }
  return null;
}

/// SALU application root.
class SaluApp extends StatelessWidget {
  const SaluApp({super.key, this.initialFilePath});

  /// Media file the app was launched with (double-click / "Open with").
  final String? initialFilePath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SALU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(initialFilePath: initialFilePath),
    );
  }
}
