import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../player_service.dart';
import 'eq_filter.dart';
import 'tune_model.dart';

/// Everything the Tune panel can ask the outside world to do
/// (eq_imp.md §6: "the continua are pure math… the engine only ever receives
/// the same single property write as before").
///
/// The service talks to THIS interface only, so the state machine, the
/// blends, the snapping and the persistence stay unit-testable with a fake —
/// and an engine that refuses a filter can never take the panel down.
abstract class TuneEngine {
  /// The 10-band curve. `Flat` (all zeros) removes the filter entirely.
  Future<void> setEqCurve(EqCurve curve);

  /// The 5 picture values, straight onto mpv's video equalizer options.
  Future<void> setPicture(PictureValues values);

  /// `video-aspect-override`: 0 = the file's own shape (Auto); any other
  /// number is the ratio the knob rests on, in-between values included.
  Future<void> setAspectOverride(double ratio);

  /// `speed`, plus pitch correction for the "Keep pitch" switch.
  Future<void> setSpeed(double speed, {required bool keepPitch});

  /// The playing file's real display aspect ratio (width × pixel aspect ÷
  /// height) — what "the window is the screen" reads. `null` while unknown.
  ///
  /// This must be the FILE's shape, never the override the panel itself
  /// wrote: `Auto` means the film's own shape, and a snap back to `Auto`
  /// has to fit the window to the film again.
  Future<double?> readFileAspect();

  /// mpv's audio channel count (2 = stereo, 6 = 5.1, 8 = 7.1).
  Future<int?> readAudioChannels();

  /// The file's own genre tag, `null` when it carries none.
  Future<String?> readGenre();

  /// One decoded frame of the playing picture, small enough to bin — the
  /// live tone histogram's only input (eq_imp.md §7a). `null` when there is
  /// nothing to read (no video, no screenshot support, a paused-to-nothing
  /// player). The caller owns the returned image and disposes it.
  Future<ui.Image?> captureFrame();

  /// Snap mode: relaxes the 800×600 window minimum while ON (a 9:16 story
  /// cannot fit an 800 px floor) and restores it when OFF.
  Future<void> setSnapMode(bool on);

  /// Resizes the SALU window to [ratio] — centred, fitted to the screen,
  /// never while fullscreen (the cinema changes shape with every film).
  Future<void> fitWindow(double ratio);

  /// Whether the window is fullscreen right now (snap stands down there).
  Future<bool> isFullscreen();

  /// A file landing rebuilds mpv's filter chain, so any cached belief about
  /// what is installed must be dropped (the next write re-applies).
  void forgetInstalledFilter() {}
}

/// The engine SALU runs with before boot finishes, and in tests: it accepts
/// every value and changes nothing.
class NullTuneEngine implements TuneEngine {
  const NullTuneEngine();

  @override
  Future<void> setEqCurve(EqCurve curve) async {}

  @override
  Future<void> setPicture(PictureValues values) async {}

  @override
  Future<void> setAspectOverride(double ratio) async {}

  @override
  Future<void> setSpeed(double speed, {required bool keepPitch}) async {}

  @override
  Future<double?> readFileAspect() async => null;

  @override
  Future<int?> readAudioChannels() async => null;

  @override
  Future<String?> readGenre() async => null;

  @override
  Future<ui.Image?> captureFrame() async => null;

  @override
  Future<void> setSnapMode(bool on) async {}

  @override
  Future<void> fitWindow(double ratio) async {}

  @override
  Future<bool> isFullscreen() async => false;

  @override
  void forgetInstalledFilter() {}
}

/// The real one. Every write is a single mpv property, handed through
/// media_kit's [NativePlayer] — the same recipe `PlayerService` already uses
/// for `sub-delay` and `track-list`, so nothing new rides on the engine.
class MpvTuneEngine implements TuneEngine {
  MpvTuneEngine();

  /// The window minimum SALU boots with (`main.dart`'s `WindowOptions`) —
  /// restored the moment snap mode lets go.
  static const ui.Size appMinimum = ui.Size(800, 600);

  /// The floor while snap mode owns the window: small enough that a 9:16
  /// story or a 1:1 clip can take its real shape.
  static const ui.Size snapMinimum = ui.Size(320, 180);

  /// How much of the screen a snapped window may take.
  static const double screenFill = 0.94;

  /// The width the histogram's frame is decoded at (eq_imp.md §7a: "mpv's
  /// built-in screenshot command → downscaled in pure Dart → histogram").
  /// 64 × ~36 is 2 300 pixels: plenty for 32 tone bins, and free.
  static const int histogramWidth = 64;

  /// Where the tone histogram's screenshot lands — one fixed file, rewritten
  /// in place (no pile of PNGs in the temp folder).
  static String get histogramShotPath =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}salu-tone.png';

  bool _snapModeOn = false;

  /// Which [EqFilter] spelling this libmpv accepted (`0` = anequalizer,
  /// `1` = the chained peaking fallback). Latched for the session: a build
  /// without `anequalizer` must not be re-probed on every drag.
  int _afSpelling = 0;

  /// The graph currently installed, so a no-op change writes nothing.
  String _afInstalled = '';

  /// Whether mpv's equalizer options were touched this session — the
  /// neutral state needs no write at all (SALU leaves the engine's defaults
  /// alone until the viewer asks for something).
  bool _pictureDirty = false;

  NativePlayer? get _native {
    final PlatformPlayer? platform = PlayerService.instance.player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> _write(String name, String value) async {
    final NativePlayer? native = _native;
    if (native == null) return;
    try {
      await native.setProperty(name, value);
    } catch (error) {
      debugPrint('[SALU/tune] $name=$value failed: $error');
    }
  }

  Future<String> _read(String name) async {
    final NativePlayer? native = _native;
    if (native == null) return '';
    try {
      return await native.getProperty(name);
    } catch (error) {
      debugPrint('[SALU/tune] read $name failed: $error');
      return '';
    }
  }

  // ── Audio EQ ───────────────────────────────────────────────────────────

  @override
  Future<void> setEqCurve(EqCurve curve) async {
    final List<String> candidates = EqFilter.candidates(curve);
    // Flat → no filter at all in the chain (eq_imp.md §2's closing rule).
    if (candidates.length == 1 && candidates.first.isEmpty) {
      if (_afInstalled.isEmpty) return;
      _afInstalled = '';
      await _write('af', '');
      return;
    }
    final NativePlayer? native = _native;
    if (native == null) return;
    final int start = _afSpelling.clamp(0, candidates.length - 1).toInt();
    for (int i = start; i < candidates.length; i++) {
      final String value = candidates[i];
      if (value == _afInstalled) return;
      try {
        await native.setProperty('af', value);
        _afInstalled = value;
        _afSpelling = i;
        return;
      } catch (error) {
        debugPrint('[SALU/tune] af spelling $i rejected: $error');
        _afInstalled = '';
      }
    }
  }

  @override
  void forgetInstalledFilter() {
    _afInstalled = '';
  }

  // ── Picture ────────────────────────────────────────────────────────────

  @override
  Future<void> setPicture(PictureValues values) async {
    if (values.isNeutral && !_pictureDirty) return;
    _pictureDirty = !values.isNeutral;
    // Always all five: a neutral look after an adjusted one has to CLEAR the
    // previous values, since mpv keeps the last write across files.
    await Future.wait<void>(<Future<void>>[
      _write('brightness', values.brightness.toStringAsFixed(2)),
      _write('contrast', values.contrast.toStringAsFixed(2)),
      _write('saturation', values.saturation.toStringAsFixed(2)),
      _write('gamma', values.gamma.toStringAsFixed(2)),
      _write('hue', values.hue.toStringAsFixed(2)),
    ]);
  }

  // ── Aspect ─────────────────────────────────────────────────────────────

  @override
  Future<void> setAspectOverride(double ratio) async {
    final double v = ratio.isFinite && ratio > 0.05 ? ratio : 0;
    // `no` is mpv's word for "the file's own shape" (`-1` is the deprecated
    // alias; a bare 0 is not a valid aspect at all).
    await _write(
      'video-aspect-override',
      v == 0 ? 'no' : v.toStringAsFixed(6),
    );
  }

  // ── Speed ──────────────────────────────────────────────────────────────

  @override
  Future<void> setSpeed(double speed, {required bool keepPitch}) async {
    // The floor is the line's own head: nothing on the speed continuum means
    // a rate below 0.25×, and mpv's 0.01× would be a different product.
    final double v =
        speed.isFinite ? clampRange(speed, kSpeedLineMin, 100) : 1.0;
    await _write('speed', v.toStringAsFixed(4));
    // "Keep pitch" ON = mpv's built-in correction (a natural voice at any
    // speed); OFF = the correction is dropped, so the classic tape-style
    // shift rides along with the speed change (eq_imp.md §6).
    await _write('audio-pitch-correction', keepPitch ? 'yes' : 'no');
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  @override
  Future<double?> readFileAspect() async {
    // The FILE's own shape, with no override applied — `video-dec-params` is
    // mpv's own override-free view of the chain ("Exactly like video-params,
    // but no overrides applied"), which matters because this read happens
    // while a `video-aspect-override` from a previous choice may still be in
    // force: `dw/dh` there would hand back the override, and `Auto` would
    // then fit the window to a shape the file never had.
    //
    // `video-params` is the fallback (older builds, and it DOES include the
    // override) — best effort, then the derived forms.
    for (final String prefix in <String>[
      'video-dec-params',
      'video-params',
    ]) {
      // dw/dh are already "scaled for correct aspect ratio", so the ratio is
      // their quotient — no pixel-aspect sub-property needed.
      final double? dw = _asDouble(await _read('$prefix/dw'));
      final double? dh = _asDouble(await _read('$prefix/dh'));
      if (dw != null && dh != null && dw > 0 && dh > 0) {
        final double ratio = dw / dh;
        if (ratio.isFinite && ratio > 0.05) return ratio;
      }
      final double? aspect = _asDouble(await _read('$prefix/aspect'));
      if (aspect != null && aspect.isFinite && aspect > 0.05) return aspect;
      // Last resort: the raw frame and its pixel aspect (`par` is mpv's
      // documented name; `pix-aspect` is kept for builds that spell it so).
      final double? w = _asDouble(await _read('$prefix/w'));
      final double? h = _asDouble(await _read('$prefix/h'));
      if (w != null && h != null && w > 0 && h > 0) {
        final double? par = _asDouble(await _read('$prefix/par')) ??
            _asDouble(await _read('$prefix/pix-aspect'));
        final double safe = (par != null && par.isFinite && par > 0) ? par : 1;
        final double ratio = w * safe / h;
        if (ratio.isFinite && ratio > 0.05) return ratio;
      }
    }
    return null;
  }

  @override
  Future<int?> readAudioChannels() async {
    final double? v = _asDouble(await _read('audio-params/channel-count'));
    if (v == null || v < 1 || !v.isFinite) return null;
    return v.round();
  }

  @override
  Future<String?> readGenre() async {
    String raw = (await _read('metadata/by-key/genre')).trim();
    if (raw.isEmpty || raw.startsWith('(')) {
      // The flat print form of the whole map, when the sub-property is not
      // there: `{genre=Rock, artist=…}` — best effort, then give up.
      raw = (_tagValue(await _read('filtered-metadata'), 'genre') ?? '').trim();
    }
    if (raw.isEmpty || raw.startsWith('(')) return null;
    return raw;
  }

  /// One tag out of mpv's printed map form (`genre=Rock`).
  static String? _tagValue(String raw, String tag) {
    if (raw.trim().isEmpty) return null;
    final Match? m = RegExp('$tag=([^,}]+)').firstMatch(raw);
    final String? v = m?.group(1)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  static double? _asDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // ── The tone histogram's frame (eq_imp.md §7a) ─────────────────────────

  @override
  Future<ui.Image?> captureFrame() async {
    final NativePlayer? native = _native;
    if (native == null) return null;
    final String path = histogramShotPath;
    try {
      // mpv's own screenshot: synchronous inside mpv, so the file is there
      // when the command answers. No new dependency — the decode below is
      // Flutter's own image codec.
      await native.command(<String>['screenshot-to-file', path, 'video']);
      final File file = File(path);
      Uint8List bytes = await _readShot(file);
      if (bytes.isEmpty) {
        // One retry: a few builds answer the command before the encoder has
        // finished with the file.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        bytes = await _readShot(file);
      }
      if (bytes.isEmpty) return null;
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: histogramWidth,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (error) {
      debugPrint('[SALU/tune] tone frame failed: $error');
      return null;
    }
  }

  Future<Uint8List> _readShot(File file) async {
    try {
      if (!await file.exists()) return Uint8List(0);
      return await file.readAsBytes();
    } catch (_) {
      return Uint8List(0);
    }
  }

  // ── The window is the screen ───────────────────────────────────────────

  @override
  Future<bool> isFullscreen() async {
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setSnapMode(bool on) async {
    if (_snapModeOn == on) return;
    _snapModeOn = on;
    try {
      await windowManager.setMinimumSize(on ? snapMinimum : appMinimum);
    } catch (error) {
      debugPrint('[SALU/tune] snap mode ignored: $error');
    }
  }

  @override
  Future<void> fitWindow(double ratio) async {
    if (!ratio.isFinite || ratio <= 0.05) return;
    if (await isFullscreen()) return; // live cinema — the screen IS the shape
    late final double screenW, screenH;
    try {
      final ui.Size screen = _screenSize();
      screenW = screen.width;
      screenH = screen.height;
    } catch (_) {
      return;
    }
    if (screenW <= 0 || screenH <= 0) return;
    double w = screenW * screenFill;
    double h = w / ratio;
    if (h > screenH * screenFill) {
      h = screenH * screenFill;
      w = h * ratio;
    }
    // Whole pixels, and the shape kept exact: 1 px of rounding on a 2.39
    // window is where "no black bars" dies.
    w = math.max(160, w.roundToDouble());
    h = math.max(90, h.roundToDouble());
    if ((w / h - ratio).abs() > 0.02) h = (w / ratio).roundToDouble();
    try {
      await windowManager.setSize(ui.Size(w, h));
      await windowManager.center();
    } catch (error) {
      debugPrint('[SALU/tune] window snap failed: $error');
    }
  }

  /// The screen the window lives on — Flutter's own display geometry, not a
  /// plugin call: `window_manager`'s screen query does not exist in every
  /// version, and a shape computed from the window's own size would drift on
  /// every snap.
  ///
  /// The view's own display comes first (the monitor SALU is actually on),
  /// then the first display of the platform. `Display.size` is the physical
  /// size, so the device pixel ratio brings it back to logical pixels — the
  /// units `windowManager.setSize` takes.
  static ui.Size _screenSize() {
    final Iterable<ui.Display> displays =
        ui.PlatformDispatcher.instance.displays;
    final ui.Display? display = ui.PlatformDispatcher.instance.implicitView
            ?.display ??
        (displays.isEmpty ? null : displays.first);
    if (display == null) return ui.Size.zero;
    final double dpr =
        display.devicePixelRatio > 0 ? display.devicePixelRatio : 1.0;
    return ui.Size(
      display.size.width / dpr,
      display.size.height / dpr,
    );
  }
}
