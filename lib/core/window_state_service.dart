import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/mini/mini_metrics.dart';

/// Which SALU is on screen: the full player, or the mini bar
/// (mini.md §9 — "one owner … a `WindowMode { full, mini }` flag").
///
/// The flag is persisted on every switch, so a session closed in mini opens
/// in mini, at the same point, on the next launch (§5).
enum WindowMode { full, mini }

/// The full window's remembered shape (mini.md §4 — "save the full window's
/// geometry (position, size, maximized state) before shrinking to the fixed
/// mini rect", restored *exactly* on exit).
///
/// Both geometries are persisted independently (§9) and in logical pixels —
/// the same units every `window_manager` call here takes and gives back.
@immutable
class FullWindowGeometry {
  const FullWindowGeometry({
    required this.position,
    required this.size,
    this.maximized = false,
    this.fullscreen = false,
  });

  final ui.Offset position;
  final ui.Size size;

  /// The window was maximized when mini took over — it comes back maximized.
  final bool maximized;

  /// …or fullscreen (which is also stepped out of before the bar appears).
  final bool fullscreen;

  String encode() => jsonEncode(<String, Object?>{
        'x': position.dx,
        'y': position.dy,
        'w': size.width,
        'h': size.height,
        'maximized': maximized,
        'fullscreen': fullscreen,
      });

  /// Anything unreadable — missing, hand-edited, truncated — is `null`, the
  /// same "no memory yet" state a fresh install has.
  static FullWindowGeometry? decode(String? raw) {
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final double? x = (decoded['x'] as num?)?.toDouble();
      final double? y = (decoded['y'] as num?)?.toDouble();
      final double? w = (decoded['w'] as num?)?.toDouble();
      final double? h = (decoded['h'] as num?)?.toDouble();
      if (x == null || y == null || w == null || h == null) return null;
      if (w <= 0 || h <= 0) return null;
      return FullWindowGeometry(
        position: ui.Offset(x, y),
        size: ui.Size(w, h),
        maximized: decoded['maximized'] == true,
        fullscreen: decoded['fullscreen'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The ONE memory for the OS window state (bug 2 fix), and now the owner of
/// SALU's window *mode*: full or mini (mini.md §9).
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
/// The mini bar extends the same discipline to a second axis: [mode] is
/// flipped in one place, the OS window is locked/unlocked around it in one
/// place, and both geometries are remembered in one place. Nothing else in
/// the app talks to `window_manager` about size, position, resizability,
/// always-on-top or the maximize affordances.
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

  /// Which shape SALU is in — the one owner mini.md §9 asks for.
  final ValueNotifier<WindowMode> mode =
      ValueNotifier<WindowMode>(WindowMode.full);

  /// Whether the bar is live. The UI reads the notifier; this is the
  /// one-liner the service's own logic uses.
  bool get isMini => mode.value == WindowMode.mini;

  /// The full window's minimum — `main.dart`'s `WindowOptions` and
  /// `MpvTuneEngine.appMinimum` (the 800 × 600 boot floor, phase_1 §15).
  /// Restored when the bar lets the window go.
  static const ui.Size fullMinimumSize = ui.Size(800, 600);

  /// What "no maximum" has to look like: Windows has no unbounded maximum,
  /// so a size no real desktop reaches stands in for one.
  static const ui.Size unboundedSize = ui.Size(16384, 16384);

  /// The bar's fixed rect (§2) — the one size the mini window ever has.
  static ui.Size get miniWindowSize => MiniMetrics.windowSize;

  // ── Persistence keys (mini.md §9 — both geometries, independently) ─────
  static const String _prefMode = 'window_mode';
  static const String _prefFull = 'window_full_geometry';
  static const String _prefMini = 'window_mini_point';

  bool _listening = false;

  /// Guards the two toggles: a second click mid-transition is dropped
  /// instead of interleaving two window commands.
  bool _busy = false;

  /// Guards a full↔mini switch: entering mini runs six window commands, and
  /// the move/resize events they fire must not be mistaken for the user's
  /// own dragging (they would save a half-applied rect).
  bool _switching = false;

  /// The remembered full-window shape, and where the bar was left.
  FullWindowGeometry? _fullGeometry;
  ui.Offset? _miniPoint;

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

  /// Fullscreen SET (web.md · "Fullscreen is handed to the web page").
  /// The browser's page-fullscreen hand-off commands a STATE, not a flip:
  /// reality already matching [on] makes this a no-op, so a late "exit"
  /// can never fire against a window that was never handed over.
  Future<void> setFullscreen(bool on) async {
    if (_busy) return;
    _busy = true;
    try {
      await syncState();
      if (isFullscreen.value != on) {
        await windowManager.setFullScreen(on);
        await syncState();
      }
    } catch (_) {
      // A window command that can't land leaves reality as the truth —
      // the next [syncState] keeps every notifier honest.
    } finally {
      _busy = false;
    }
  }

  /// Maximize / restore toggle. While fullscreen it takes the clean
  /// path — `setFullScreen(false)` back to the pre-fullscreen state — and
  /// never restores around the fullscreen system.
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

  // ── Mini mode (mini.md §2 · §4 · §5 · §9) ─────────────────────────────

  /// Reads the persisted mode and BOTH geometries. Called from `main` before
  /// the window options are built, so a session closed in mini reopens as a
  /// bar — never as a full window that flashes and then shrinks.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      mode.value = WindowMode.values.asNameMap()[prefs.getString(_prefMode)] ??
          WindowMode.full;
      _fullGeometry = FullWindowGeometry.decode(prefs.getString(_prefFull));
      _miniPoint = _decodePoint(prefs.getString(_prefMini));
    } catch (_) {
      // Corrupt/missing prefs — no memory, the boot state.
      mode.value = WindowMode.full;
      _fullGeometry = null;
      _miniPoint = null;
    }
  }

  /// Applies what [load] restored to the real window. Called once, right
  /// after the window is on screen.
  ///
  /// In full mode there is nothing to tell the OS: the boot options already
  /// are the contract (centered, 1280 × 720 — phase_1 §15). In mini the
  /// bar's lock goes back on and its remembered point comes back (§5).
  Future<void> applyLoadedMode() async {
    if (!isMini) return;
    _switching = true;
    try {
      await _lockToMiniWindow(await _miniTargetPoint());
    } catch (_) {
      // A refused window command leaves the bar where the launch put it;
      // the mode itself is already correct and Esc still restores.
    } finally {
      _switching = false;
    }
  }

  /// Enters the mini bar (§9's order): the full window's geometry is saved
  /// FIRST — before anything shrinks — then always-on-top goes on, the size
  /// locks to the bar's fixed rect (`minSize = maxSize`), and the window
  /// takes that rect at the last mini point in one `setBounds`.
  ///
  /// The UI swaps last, on purpose: the bar is a full-bleed surface, so
  /// flipping [mode] while the window is still 1280 × 720 would paint one
  /// whole-screen glass rectangle on the way in. This way the shell draws
  /// for the first time at its real 32 px.
  Future<void> enterMini() async {
    if (isMini || _switching) return;
    _switching = true;
    try {
      await _captureFullGeometry();
      await _lockToMiniWindow(await _miniTargetPoint());
      mode.value = WindowMode.mini;
      await _persistMode();
      await syncState();
    } catch (_) {
      // Never leave the flag and the window disagreeing: the mode only
      // ever flips once the geometry is already saved.
    } finally {
      _switching = false;
    }
  }

  /// Leaves the mini bar, restoring the saved full geometry EXACTLY (§4):
  /// position, size, and maximized/fullscreen state.
  Future<void> exitMini() async {
    if (!isMini || _switching) return;
    _switching = true;
    try {
      // Where the bar was left is worth keeping even though the mode is
      // about to change — the next mini session returns here (§5).
      await _rememberMiniPoint();
      // The size clamp has to come off BEFORE the big rect is set, or the
      // maximum the bar locked in would clip the window it is returning to.
      await _releaseMiniLock();
      final FullWindowGeometry? full = _fullGeometry;
      if (full == null) {
        // Nothing was ever captured (the bar was booted straight into
        // mini): the boot shape, centred — main.dart's own defaults.
        await windowManager.setBounds(
          const ui.Rect.fromLTWH(0, 0, 1280, 720),
        );
        await windowManager.center();
      } else {
        await windowManager.setBounds(full.position & full.size);
      }
      mode.value = WindowMode.full;
      await _persistMode();
      // State last: maximizing is itself a geometry change, so the UI must
      // already be full mode when the OS animates it back.
      if (full != null) {
        if (full.maximized) await windowManager.maximize();
        if (full.fullscreen) await windowManager.setFullScreen(true);
      }
      await syncState();
    } catch (_) {
      // Same rule as above: `mode` flips only after the window is whole.
    } finally {
      _switching = false;
    }
  }

  /// `M` and the title-strip glyph both land here (mini.md §4).
  Future<void> toggleMini() => isMini ? exitMini() : enterMini();

  /// The close guard's last call: whatever the mode, its geometry is flushed
  /// once more so the next launch opens exactly where this one ended (§5).
  Future<void> saveOnClose() async {
    if (isMini) {
      await _rememberMiniPoint();
    } else {
      await _rememberFullGeometry();
    }
    await _persistMode();
  }

  // ── Window contract, applied in the doc's order (§9) ──────────────────

  /// The whole mini contract: always-on-top → `setMinimumSize` +
  /// `setMaximumSize` → the bar's size. Resize and maximize affordances
  /// follow, because "no drag edges, no maximize, ever" (§2) is a window
  /// property, not a hint.
  ///
  /// Size and point travel together in one `setBounds`, so the OS sees a
  /// single geometry change instead of a resize and then a move.
  Future<void> _lockToMiniWindow(ui.Offset point) async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setMinimumSize(MiniMetrics.windowSize);
    await windowManager.setMaximumSize(MiniMetrics.windowSize);
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setBounds(point & MiniMetrics.windowSize);
  }

  /// …and its mirror. Everything that clamps or pins is released before the
  /// full rect is set, so the returning window can take its real size.
  Future<void> _releaseMiniLock() async {
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimumSize(fullMinimumSize);
    await windowManager.setMaximumSize(unboundedSize);
    await windowManager.setAlwaysOnTop(false);
  }

  /// Where the bar belongs: the remembered point, clamped inside the
  /// visible screen (§2), falling back to wherever the window already is on
  /// the very first mini session. The clamped value is remembered too, so a
  /// point that had to be pulled back never comes back wrong.
  Future<ui.Offset> _miniTargetPoint() async {
    final ui.Offset current = await windowManager.getPosition();
    final ui.Offset point = clampMiniPoint(
      _miniPoint ?? current,
      boxes: await displayBoxes(),
    );
    _miniPoint = point;
    await _persistMiniPoint();
    return point;
  }

  /// Saves the full window's position, size and maximized state — the call
  /// that must happen before the bar shrinks anything (§4).
  ///
  /// A maximized (or fullscreen) window cannot be measured or resized, so it
  /// is stepped out of first: the rect that comes back is the one the window
  /// had before it was maximized, which is what "restore exactly" has to
  /// mean. The maximized flag itself comes back with it.
  Future<void> _captureFullGeometry() async {
    await syncState();
    final bool wasFullscreen = isFullscreen.value;
    bool wasMaximized = isMaximized.value;
    if (wasFullscreen) {
      await windowManager.setFullScreen(false);
      // A window that went fullscreen FROM maximized comes back
      // maximized — and that is the state the saved flag has to mean, or
      // the restore would hand back a screen-sized window instead. The
      // plugin reports state live; give the OS a beat to settle first.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await syncState();
      wasMaximized = wasMaximized || isMaximized.value;
    }
    if (wasMaximized) await windowManager.unmaximize();
    if (wasFullscreen || wasMaximized) {
      // Same beat again for the rect the window lands on.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    _fullGeometry = FullWindowGeometry(
      position: await windowManager.getPosition(),
      size: await windowManager.getSize(),
      maximized: wasMaximized,
      fullscreen: wasFullscreen,
    );
    await _persistFullGeometry();
  }

  /// Reads the bar's current point, clamps it and remembers it — the hook
  /// behind every mini drag (§2: remembered per mode, restored on relaunch).
  Future<void> _rememberMiniPoint() async {
    try {
      final ui.Offset position = await windowManager.getPosition();
      final ui.Offset clamped = clampMiniPoint(
        position,
        boxes: await displayBoxes(),
      );
      _miniPoint = clamped;
      if (clamped != position) await windowManager.setPosition(clamped);
      await _persistMiniPoint();
    } catch (_) {
      // Best effort — a failed read keeps the last remembered point.
    }
  }

  /// Keeps the full rect fresh while the window is in full mode, so the next
  /// restore returns to where the window actually was.
  Future<void> _rememberFullGeometry() async {
    try {
      await syncState();
      // While maximized/fullscreen the live rect is not the rect the window
      // would return to — the captured one stands.
      if (isMaximized.value || isFullscreen.value) return;
      _fullGeometry = FullWindowGeometry(
        position: await windowManager.getPosition(),
        size: await windowManager.getSize(),
      );
      await _persistFullGeometry();
    } catch (_) {
      // Best effort, same as above.
    }
  }

  // ── Geometry maths (pure — unit-testable on its own) ──────────────────

  /// The visible area of every monitor, in logical pixels — mini.md §2's
  /// "clamped inside the visible screen (multi-monitor + DPI safe)".
  ///
  /// `screen_retriever` is the one query that answers with each monitor's
  /// ORIGIN as well as its size. Flutter's own `Display` has no position, so
  /// a monitor to the left of (or above) the primary one would be
  /// indistinguishable from off-screen space and the bar would be dragged
  /// home every time it was parked there.
  ///
  /// Each display's *visible* rect is its work area (taskbar excluded) when
  /// the platform reports one, its full rect otherwise; [Display.size],
  /// `visiblePosition` and `visibleSize` are all logical pixels — the same
  /// units every `window_manager` call in this file takes and returns.
  ///
  /// A failed query is not fatal: an empty list makes [clampMiniPoint] a
  /// no-op rather than a wrong move.
  static Future<List<ui.Rect>> displayBoxes() async {
    try {
      final List<Display> displays =
          await ScreenRetriever.instance.getAllDisplays();
      final List<ui.Rect> boxes = <ui.Rect>[];
      for (final Display display in displays) {
        final ui.Size size = display.visibleSize ?? display.size;
        if (size.width <= 0 || size.height <= 0) continue;
        boxes.add((display.visiblePosition ?? ui.Offset.zero) & size);
      }
      return boxes;
    } catch (_) {
      return const <ui.Rect>[];
    }
  }

  /// Pulls [point] back so the WHOLE bar sits inside one monitor's visible
  /// area — the monitor the bar is nearest to, so a point remembered on a
  /// second screen stays on that screen instead of snapping home. A display
  /// smaller than the bar (or an empty list) leaves the point alone.
  static ui.Offset clampMiniPoint(
    ui.Offset point, {
    required List<ui.Rect> boxes,
    ui.Size windowSize = MiniMetrics.windowSize,
  }) {
    if (boxes.isEmpty) return point;
    final ui.Offset centre =
        point + ui.Offset(windowSize.width / 2, windowSize.height / 2);
    ui.Rect best = boxes.first;
    double bestDistance = double.infinity;
    for (final ui.Rect box in boxes) {
      final double distance = (box.center - centre).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = box;
      }
    }
    final double maxX = math.max(best.left, best.right - windowSize.width);
    final double maxY = math.max(best.top, best.bottom - windowSize.height);
    return ui.Offset(
      point.dx.clamp(best.left, maxX).toDouble(),
      point.dy.clamp(best.top, maxY).toDouble(),
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────

  Future<void> _persistMode() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefMode, mode.value.name);
    } catch (_) {
      // In-memory change already applied; persistence is best-effort.
    }
  }

  Future<void> _persistFullGeometry() async {
    final FullWindowGeometry? geometry = _fullGeometry;
    if (geometry == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefFull, geometry.encode());
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _persistMiniPoint() async {
    final ui.Offset? point = _miniPoint;
    if (point == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefMini, encodePoint(point));
    } catch (_) {
      // Best effort.
    }
  }

  /// The mini point's storage shape — `{"x":…,"y":…}`, logical pixels.
  static String encodePoint(ui.Offset point) =>
      jsonEncode(<String, Object?>{'x': point.dx, 'y': point.dy});

  static ui.Offset? _decodePoint(String? raw) {
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final double? x = (decoded['x'] as num?)?.toDouble();
      final double? y = (decoded['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return ui.Offset(x, y);
    } catch (_) {
      return null;
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

  /// The window stopped moving. In mini that is where the bar now lives
  /// (remembered, and clamped back into reach); in full mode it is the
  /// window's rect, kept fresh for the next restore.
  @override
  void onWindowMoved() {
    if (_switching) return;
    unawaited(isMini ? _rememberMiniPoint() : _rememberFullGeometry());
  }

  /// The window stopped being resized — in full mode only: a mini session
  /// never resizes (§9), so a resize event there is the transition itself.
  @override
  void onWindowResized() {
    if (_switching || isMini) return;
    unawaited(_rememberFullGeometry());
  }
}
