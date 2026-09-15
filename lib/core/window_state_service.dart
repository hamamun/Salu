import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// The ONE memory for the OS window state (bug 2 fix).
///
/// Before this service, the title-bar maximize button and the fullscreen
/// button each kept their own private copy of the window state and never
/// compared notes. Restoring the window via the title bar while
/// fullscreen bypassed the fullscreen system entirely: the window
/// shrank, no event fired, and the fullscreen button kept believing it
/// was fullscreen — so the next click sent "exit fullscreen" to an
/// already-windowed window, and the plugin's raced restore routine
/// froze pointer input and Flutter painting until a clean resize.
///
/// The rules here make that sequence unreachable:
///
/// 1. **One memory.** Both buttons read [isFullscreen] / [isMaximized];
///    nothing else tracks window state.
/// 2. **Live truth wins.** [syncState] re-reads both values from the OS
///    after every command and on every window event — memory can never
///    go stale, even when the plugin stays silent.
/// 3. **No silent restore.** [toggleMaximize] while fullscreen exits
///    through the clean `setFullScreen(false)` path first and stops
///    there (back to the pre-fullscreen state); it never restores
///    around the fullscreen system.
/// 4. **No exit on windowed.** [toggleFullscreen] reads the live state
///    before acting, so "exit fullscreen" can never fire on an
///    already-windowed window — the step-4 trigger is deleted.
///
/// External changes (Win+Down, taskbar, Alt+Space) still flow through
/// the plugin's events below, which re-sync live; a refocus
/// ([onWindowFocus]) heals anything the events miss.
class WindowStateService with WindowListener {
  WindowStateService._();

  static final WindowStateService instance = WindowStateService._();

  /// Whether the OS window is fullscreen right now.
  final ValueNotifier<bool> isFullscreen = ValueNotifier<bool>(false);

  /// Whether the OS window is maximized right now.
  final ValueNotifier<bool> isMaximized = ValueNotifier<bool>(false);

  bool _listening = false;

  /// Guards the two toggles: a second click mid-transition is dropped
  /// instead of interleaving two window commands.
  bool _busy = false;

  /// Starts listening and takes the initial live reading. Called once
  /// from `main`, after `windowManager.ensureInitialized()`.
  Future<void> ensureInitialized() async {
    if (_listening) return;
    _listening = true;
    windowManager.addListener(this);
    await syncState();
  }

  /// Re-reads both states live from the OS. Idempotent — overlapping
  /// calls converge on the same truth. Never throws: a failed read
  /// (e.g. mid-shutdown) keeps the last known state.
  Future<void> syncState() async {
    try {
      final bool fullscreen = await windowManager.isFullScreen();
      final bool maximized = await windowManager.isMaximized();
      if (isFullscreen.value != fullscreen) isFullscreen.value = fullscreen;
      if (isMaximized.value != maximized) isMaximized.value = maximized;
    } catch (_) {
      // Unreachable in practice; a failed read must never take the UI
      // down with it — the last known state simply stands.
    }
  }

  /// Fullscreen toggle. Reads the live state first, so the command
  /// always matches reality — "exit" can never fire while windowed.
  Future<void> toggleFullscreen() async {
    if (_busy) return;
    _busy = true;
    try {
      await syncState();
      await windowManager.setFullScreen(!isFullscreen.value);
      await syncState();
    } finally {
      _busy = false;
    }
  }

  /// Maximize / restore toggle. While fullscreen it takes the clean
  /// path — `setFullScreen(false)` back to the pre-fullscreen state —
  /// and never restores around the fullscreen system.
  Future<void> toggleMaximize() async {
    if (_busy) return;
    _busy = true;
    try {
      await syncState();
      if (isFullscreen.value) {
        await windowManager.setFullScreen(false);
        await syncState();
        return;
      }
      if (isMaximized.value) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await syncState();
    } finally {
      _busy = false;
    }
  }

  // ── Plugin events: backup hints, always verified live ────
  //
  // The plugin can stay silent (leaving fullscreen any way other than
  // `setFullScreen(false)` fires nothing), so every event below ends in
  // a live re-read instead of trusting the event alone.

  @override
  void onWindowMaximize() {
    unawaited(syncState());
  }

  @override
  void onWindowUnmaximize() {
    unawaited(syncState());
  }

  @override
  void onWindowEnterFullScreen() {
    unawaited(syncState());
  }

  @override
  void onWindowLeaveFullScreen() {
    unawaited(syncState());
  }

  @override
  void onWindowFocus() {
    // Heals external changes (Win+Down, taskbar, Alt+Space) that the
    // events above may have missed: coming back to the window always
    // re-checks the real state.
    unawaited(syncState());
  }
}
