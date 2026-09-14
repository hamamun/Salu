import 'dart:ui' as ui;

import 'package:salu/core/tune/tune_engine.dart';
import 'package:salu/core/tune/tune_model.dart';

/// The recorder the Tune service tests drive (eq_imp.md §6: "the engine only
/// ever receives the same single property write as before" — so what a test
/// has to prove is *which* writes arrive, in what order, and how many).
///
/// Nothing here talks to mpv, a window or a player: it stores the values and
/// answers the reads with whatever a test needs to pretend the file is.
class TuneFakeEngine implements TuneEngine {
  /// Every curve handed to `setEqCurve`, oldest first.
  final List<EqCurve> eqCurves = <EqCurve>[];

  /// Every `setPicture` payload.
  final List<PictureValues> pictureWrites = <PictureValues>[];

  /// Every `video-aspect-override` value (`0` = the file's own shape).
  final List<double> aspectWrites = <double>[];

  /// Every `speed` write, with the pitch-correction flag that came with it.
  final List<FakeSpeedWrite> speedWrites = <FakeSpeedWrite>[];

  /// Every snap-mode toggle and every requested window shape.
  final List<bool> snapModes = <bool>[];
  final List<double> fitted = <double>[];

  /// How often the cached filter belief was dropped (a file landing, §2).
  int forgotten = 0;

  /// What the reads answer.
  double? fileAspect;
  int? channels;
  String? genre;

  /// How many tone frames were asked for, and what the §7a capture answers.
  int captures = 0;
  ui.Image? frame;

  @override
  Future<void> setEqCurve(EqCurve curve) async {
    eqCurves.add(curve);
  }

  @override
  Future<void> setPicture(PictureValues values) async {
    pictureWrites.add(values);
  }

  @override
  Future<void> setAspectOverride(double ratio) async {
    aspectWrites.add(ratio);
  }

  @override
  Future<void> setSpeed(double speed, {required bool keepPitch}) async {
    speedWrites.add(FakeSpeedWrite(speed: speed, keepPitch: keepPitch));
  }

  @override
  Future<double?> readFileAspect() async => fileAspect;

  @override
  Future<int?> readAudioChannels() async => channels;

  @override
  Future<String?> readGenre() async => genre;

  @override
  Future<ui.Image?> captureFrame() async {
    captures++;
    return frame;
  }

  @override
  Future<void> setSnapMode(bool on) async {
    snapModes.add(on);
  }

  @override
  Future<void> fitWindow(double ratio) async {
    fitted.add(ratio);
  }

  @override
  Future<bool> isFullscreen() async => false;

  @override
  void forgetInstalledFilter() {
    forgotten++;
  }

  /// Starts from nothing, so a test that only checks one behaviour is not
  /// reading another test's leftovers.
  void reset() {
    eqCurves.clear();
    pictureWrites.clear();
    aspectWrites.clear();
    speedWrites.clear();
    snapModes.clear();
    fitted.clear();
    forgotten = 0;
    fileAspect = null;
    channels = null;
    genre = null;
    captures = 0;
    frame = null;
  }
}

/// A recorded `speed` + `audio-pitch-correction` pair.
class FakeSpeedWrite {
  const FakeSpeedWrite({required this.speed, required this.keepPitch});

  final double speed;
  final bool keepPitch;
}
