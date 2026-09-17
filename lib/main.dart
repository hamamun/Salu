import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'core/browser_service.dart';
import 'core/channel_favourites_service.dart';
import 'core/channel_load_service.dart';
import 'core/folder_autoload_service.dart';
import 'core/media_utils.dart';
import 'core/player_service.dart';
import 'core/resume_service.dart';
import 'core/settings_service.dart';
import 'core/sub_delay_service.dart';
import 'core/tune_service.dart';
import 'core/window_state_service.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Phase 1 · Step 6: strict single instance + file argument routing. ─
  // If SALU is already running and the user double-clicks a media file,
  // Windows launches a second process; its arguments are intercepted here,
  // forwarded to the live window, and the duplicate process exits.
  //
  // The check runs BEFORE the mpv engine boots: a duplicate process only
  // forwards its path, so it must never pay for a libmpv startup.
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'salu_media_player_instance',
      onSecondWindow: (List<String> secondArgs) async {
        // The pipe can deliver a path while this process is still
        // booting — make sure the window handle is known before
        // showing/focusing.
        await windowManager.ensureInitialized();
        await windowManager.show();
        await windowManager.focus();
        final String? path = extractMediaPathFromArgs(secondArgs);
        if (path != null) {
          // A `.m3u` / `.m3u8` argument is a channel directory SALU
          // reads itself (playlist_imp.md M55); anything else opens as
          // before.
          final bool channels =
              await ChannelLoadService.instance.openSource(path);
          if (!channels) {
            // Single-file open-with — folder auto-load may kick in
            // (autoload_imp.md §2; the mode setting and exclusions gate
            // everything inside).
            unawaited(FolderAutoloadService.instance.maybeExpand(path));
          }
        }
      },
    );
  }

  // ── Phase 2 · Step 2: boot the mpv C++ engine before any UI draws. ────
  // (First instance only — a duplicate already exited above.)
  MediaKit.ensureInitialized();

  // ── Phase 1 · Step 2: borderless, centered, dark window. ─────────────
  await windowManager.ensureInitialized();
  // Phase 9 adds a second shape: a session closed in mini (mini.md §5)
  // reopens AS the bar — at its fixed rect, always on top, later at the
  // point it was left — and never as a full window that flashes and then
  // shrinks. The memory is read before the options are built for exactly
  // that reason; the point itself is applied once the window exists
  // (`applyLoadedMode`, below).
  await WindowStateService.instance.load();
  final bool startInMini = WindowStateService.instance.isMini;
  final WindowOptions windowOptions = WindowOptions(
    title: 'SALU',
    size: startInMini
        ? WindowStateService.miniWindowSize
        : const Size(1280, 720),
    minimumSize: startInMini
        ? WindowStateService.miniWindowSize
        : const Size(800, 600),
    maximumSize: startInMini ? WindowStateService.miniWindowSize : null,
    center: !startInMini,
    alwaysOnTop: startInMini,
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
  // then an immediate process exit. Covers every close path.
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseGuard());

  // ── Load persisted settings + resume memory before the first frame. ──
  // The one shared window-state memory starts here too (bug 2 fix): one
  // listener + live re-reads back both caption buttons, so fullscreen /
  // maximize can never disagree with the real window again.
  await WindowStateService.instance.ensureInitialized();
  // The bar's lock goes back on — always-on-top, min = max, and the point
  // it was left at, clamped into the visible screen (mini.md §2).
  await WindowStateService.instance.applyLoadedMode();
  await SettingsService.instance.load();
  await ResumeService.instance.load();
  await SubDelayService.instance.load();
  await ChannelFavouritesService.instance.load();
  // The Tune panel's values (its four lines + the Auto EQ learning map) are
  // read before the first frame, so a launch straight into a file lands on
  // the remembered curve instead of flashing a Flat one (eq_imp.md §6).
  await TuneService.instance.load();
  // The browser's two stores — favourites + browsing history — read the
  // same way, before the first frame (web.md: the star and the dropdown
  // must be complete the moment Web mode can first be picked).
  await BrowserService.instance.load();

  runApp(SaluApp(initialFilePath: extractMediaPathFromArgs(args)));

  // The WebView2 environment is heavy and Web mode may never be picked —
  // so it boots AFTER the first frame, never blocking it, exactly once
  // (BrowserService.warmUp caches). By the time the toggle can be clicked
  // the first page is ready to start instantly.
  BrowserService.instance.scheduleStartupWarmUp();
}

/// Intercepts the window close: flush the resume store so the last
/// watched second is remembered, then kill the process immediately.
///
/// We bypass Flutter's graceful widget teardown entirely. After the
/// position is flushed to disk there is no need to dispose the video
/// surface or the mpv engine — the OS reclaims everything when the
/// process dies.
///
/// Every bookkeeping step is guarded: the close is intercepted
/// (`setPreventClose`), so if [exit] is ever skipped the window would
/// be left open with no way to close it. `exit(0)` must be reached no
/// matter what.
class _CloseGuard with WindowListener {
  @override
  void onWindowClose() async {
    try {
      final PlayerService player = PlayerService.instance;
      final String? path = player.currentPath.value;
      if (path != null && player.duration.value > Duration.zero) {
        ResumeService.instance.update(
          path,
          player.position.value,
          player.duration.value,
        );
      }
    } catch (_) {
      // Resume bookkeeping must never block the close.
    }
    try {
      await ResumeService.instance.flush().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      // A sync offset dragged seconds before the × must never be lost.
      await SubDelayService.instance.flush().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      // A bookmark tapped seconds before the × must never be lost.
      await ChannelFavouritesService.instance.flush().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      // The browser's own stores flush, and the auto-clear "on player
      // closing" timing runs here: the due-date check + the browser's
      // own data go now, the locked profile folder is handed to the next
      // startup (web.md · Auto-clear). SALU's own memory is a different
      // store — touched by the steps above, never by this one.
      await BrowserService.instance.prepareClose().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      // An equalizer dragged seconds before the × must never be lost — the
      // panel state and the learning map both ride the same flush.
      await TuneService.instance.flush().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      // Where the window lives — the bar's point or the full rect, and the
      // mode itself — so the next launch reopens exactly here (§5).
      await WindowStateService.instance.saveOnClose().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
    exit(0);
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
