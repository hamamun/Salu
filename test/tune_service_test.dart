import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/panel_service.dart';
import 'package:salu/core/tune/auto_eq.dart';
import 'package:salu/core/tune/tone_histogram.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';
import 'package:salu/core/tune/tune_state.dart';
import 'package:salu/core/tune_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tune_fake_engine.dart';

/// The panel's owner (eq_imp.md §6: "one core service owns all values — the
/// button, the panel and the engine can never disagree"). Everything the viewer
/// does is a call here first, so these are the behaviours the UI trusts and
/// cannot check for itself:
///
///   · a knob on a stop means that stop's numbers, and they reach the engine;
///   · a release snaps, a drag does not;
///   · a hover preview is temporary, reverts, and never teaches;
///   · a kept change is on disk at once, and a slider edit means `Custom`;
///   · greyed-out really means write-nothing (live media, §12);
///   · a new file keeps the curve and re-lays the line (§1.6).
///
/// `startWatching` is deliberately never called — that belongs to the player,
/// and a unit test has none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TuneFakeEngine fake;
  late TuneService tune;

  /// A real `ui.Image` for the §7a tests — the same kind of object the
  /// engine's screenshot hands over, without a player.
  Future<ui.Image> image(List<int> rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(rgba));
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  setUp(() async {
    // The store the service writes to is mocked; the player is never
    // constructed, because a unit test has no media_kit to talk to.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tune = TuneService.instance;
    fake = TuneFakeEngine();
    tune.engine = fake;
    tune.resetForTest();
    tune.memory.clear();
    // A local video — the shape every test assumes unless it says otherwise.
    tune.fileKind.value = TuneFileKind.video;
    tune.available.value = true;
    tune.videoPartsActive.value = true;
  });

  group('a knob, a curve, one write', () {
    test('a click on a named stop means that preset, exactly', () {
      tune.selectStop(TunePart.eq, 'movie');
      expect(tune.eq.value, TunePresets.video[1].curve);
      expect(tune.eqStop.value, 'movie');
      expect(tune.eqCustom.value, isFalse);
      expect(tune.labelFor(TunePart.eq), 'Movie');
      expect(tune.eqKnob.value, tune.eqLine.positionForKey('movie'));
      // One curve write, the same numbers, nothing invented.
      expect(fake.eqCurves.length, 1);
      expect(fake.eqCurves.single, TunePresets.video[1].curve);
    });

    test('a release near a stop snaps to it; mid-drag it does not', () {
      final double near = tune.eqLine.positionOf(1) - 0.02;
      tune.setKnob(TunePart.eq, near, commit: false);
      expect(tune.eqKnob.value, near); // still under the pointer
      expect(tune.eqStop.value, isNull);
      tune.setKnob(TunePart.eq, near, commit: true);
      expect(tune.eqKnob.value, tune.eqLine.positionOf(1));
      expect(tune.eqStop.value, 'movie');
    });

    test('a value between two stops names both and blends both', () {
      final double a = tune.eqLine.positionOf(1); // Movie
      final double b = tune.eqLine.positionOf(2); // Music V
      tune.setKnob(TunePart.eq, (a + b) / 2, commit: false);
      expect(tune.labelFor(TunePart.eq), 'Movie ↔ Music V');
      for (int i = 0; i < kEqBandCount; i++) {
        final double mid =
            (TunePresets.video[1].gains[i] + TunePresets.video[2].gains[i]) / 2;
        expect(tune.eq.value.at(i), closeTo(mid, 1e-9), reason: 'band $i');
      }
    });

    test('the picture line writes mpv’s five options', () {
      tune.selectStop(TunePart.picture, 'vivid');
      expect(tune.labelFor(TunePart.picture), 'Vivid');
      expect(tune.picture.value.saturation, 26);
      expect(tune.picture.value.gamma, -6);
      expect(fake.pictureWrites.length, 1);
      expect(fake.pictureWrites.single.saturation, 26);
    });

    test('the aspect line writes 0 for Auto and a number otherwise', () {
      tune.selectStop(TunePart.aspect, 'auto');
      expect(tune.aspectRatio.value, 0);
      expect(tune.labelFor(TunePart.aspect), 'Auto');
      tune.selectStop(TunePart.aspect, 'a916');
      expect(tune.aspectRatio.value, 0.5625);
      expect(tune.labelFor(TunePart.aspect), '9:16');
      expect(fake.aspectWrites, <double>[0, 0.5625]);
    });

    test('the speed line is linear in value, so 1× is not the middle', () {
      tune.selectStop(TunePart.speed, 'x1_25');
      expect(tune.speed.value, 1.25);
      expect(tune.labelFor(TunePart.speed), '1.25×');
      expect(tune.speedKnob.value, closeTo(0.3636, 1e-3));
      expect(fake.speedWrites.length, 1);
      expect(fake.speedWrites.single.speed, 1.25);
      expect(fake.speedWrites.single.keepPitch, isTrue);
    });

    test('Keep pitch rides along with every speed write', () {
      tune.setKeepPitch(false);
      expect(fake.speedWrites.last.keepPitch, isFalse);
      tune.selectStop(TunePart.speed, 'x2');
      expect(fake.speedWrites.last.speed, 2);
      expect(fake.speedWrites.last.keepPitch, isFalse);
    });
  });

  group('a custom shape is remembered (§1.4 · §3)', () {
    test('a between-stops ratio is a number, not a lost knob', () {
      final Continuum line = tune.aspectLine;
      final double t = (line.positionOf(1) + line.positionOf(2)) / 2;
      tune.setKnob(TunePart.aspect, t, commit: true);
      // 4:3 ↔ 16:9 at the halfway point — a real ratio, written to the engine.
      expect(tune.aspectStop.value, isNull);
      expect(tune.aspectRatio.value, closeTo((1.333333 + 1.777778) / 2, 1e-3));
      expect(tune.labelFor(TunePart.aspect), '1.56:1');
      expect(fake.aspectWrites.last, closeTo(1.5555555, 1e-3));
    });

    test('a capture/restore cycle keeps the exact ratio and the label', () {
      final Continuum line = tune.aspectLine;
      tune.setKnob(TunePart.aspect,
          (line.positionOf(1) + line.positionOf(2)) / 2,
          commit: true);
      final TuneState saved = tune.capture();
      final double ratio = tune.aspectRatio.value;
      final String label = tune.labelFor(TunePart.aspect);

      tune.resetForTest();
      expect(tune.aspectRatio.value, 0);
      tune.applyState(saved, persist: false, push: true);

      expect(tune.aspectStop.value, isNull);
      expect(tune.aspectRatio.value, ratio);
      expect(tune.labelFor(TunePart.aspect), label);
      expect(fake.aspectWrites.last, ratio);
    });

    test('the ratio survives the settings store, not just memory', () async {
      final Continuum line = tune.aspectLine;
      tune.setKnob(TunePart.aspect,
          (line.positionOf(1) + line.positionOf(2)) / 2,
          commit: true);
      final double ratio = tune.aspectRatio.value;
      await tune.persistNow();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final TuneState back = TuneState.decode(prefs.getString('tune_state'));
      expect(back.aspectStop, isNull);
      expect(back.aspectRatio, ratio);
      // …and the next launch lands on the same shape, not on Auto.
      tune.resetForTest();
      tune.applyState(back, persist: false, push: true);
      expect(tune.aspectRatio.value, ratio);
      expect(tune.labelFor(TunePart.aspect), isNot('Auto'));
    });

    test('beside Auto a blend starts from the file\'s own shape', () {
      tune.fileAspect.value = 2.35;
      final Continuum line = tune.aspectLine;
      final double t = (line.positionOf(0) + line.positionOf(1)) / 2;
      tune.setKnob(TunePart.aspect, t, commit: true);
      expect(tune.aspectStop.value, isNull);
      // Halfway from 2.35 to 4:3.
      expect(tune.aspectRatio.value, closeTo((2.35 + 1.333333) / 2, 1e-3));
    });
  });

  group('the fine sliders', () {
    test('a band edit leaves the line and reads `Custom`', () {
      tune.selectStop(TunePart.eq, 'movie');
      tune.setBandGain(0, 9.5);
      expect(tune.eq.value.at(0), 9.5);
      expect(tune.eqCustom.value, isTrue);
      expect(tune.eqStop.value, isNull);
      expect(tune.labelFor(TunePart.eq), 'Custom');
      // …and the knob parks on the nearest stop rather than floating free.
      expect(
        tune.eqKnob.value,
        tune.eqLine.positionOf(tune.eqLine.nearestStop(tune.eqKnob.value)),
      );
    });

    test('the grid is the service’s: halves only, ±12 dB', () {
      tune.setBandGain(1, 9.3);
      expect(tune.eq.value.at(1), 9.5);
      tune.setBandGain(2, 40);
      expect(tune.eq.value.at(2), kEqGainMax);
      tune.setBandGain(3, -99);
      expect(tune.eq.value.at(3), kEqGainMin);
    });

    test('a picture bar does the same to its line', () {
      tune.selectStop(TunePart.picture, 'night');
      tune.setPictureValue(2, -30.4);
      expect(tune.picture.value.contrast, -30);
      expect(tune.pictureCustom.value, isTrue);
      expect(tune.labelFor(TunePart.picture), 'Custom');
    });

    test('every band back to zero is Flat', () {
      tune.setBandGain(3, 6);
      tune.resetBands();
      expect(tune.eq.value.isFlat, isTrue);
      expect(tune.eqStop.value, 'flat');
      expect(tune.labelFor(TunePart.eq), 'Flat');
      expect(tune.eqCustom.value, isFalse);
    });
  });

  group('hover preview (§8)', () {
    test('a rest previews, leaving reverts, nothing is kept', () async {
      tune.selectStop(TunePart.eq, 'movie');
      final EqCurve before = tune.eq.value;
      final int writes = fake.eqCurves.length;

      tune.beginPreview();
      tune.setKnob(TunePart.eq, tune.eqLine.positionOf(3), commit: false);
      expect(tune.previewing.value, isTrue);
      expect(tune.eq.value, TunePresets.video[3].curve);

      tune.endPreview();
      expect(tune.previewing.value, isFalse);
      expect(tune.eq.value, before);
      expect(tune.eqStop.value, 'movie');
      expect(fake.eqCurves.length, greaterThan(writes)); // the picture changed
      expect(fake.eqCurves.last, before); // …and changed back
      // A preview is not a decision: the learning map never saw it.
      expect(tune.memory.isEmpty, isTrue);
    });

    test('a preview the viewer clicks becomes the choice', () {
      tune.beginPreview();
      tune.setKnob(TunePart.eq, tune.eqLine.positionOf(2), commit: false);
      // The press is what turns a preview into an answer (the widget's
      // onPointerDown → beginGesture, and a click's commit).
      tune.beginGesture();
      tune.selectStop(TunePart.eq, 'documentary');
      tune.endGesture();
      expect(tune.previewing.value, isFalse);
      expect(tune.eqStop.value, 'documentary');
      expect(tune.eq.value, TunePresets.video[3].curve);
    });

    test('an audio-only file dims its video parts and keeps its own', () {
      tune.fileKind.value = TuneFileKind.audio;
      tune.videoPartsActive.value = false;
      expect(tune.partActive(TunePart.eq), isTrue);
      expect(tune.partActive(TunePart.picture), isFalse);
      expect(tune.partActive(TunePart.aspect), isFalse);
      // Speed is not a video part: a podcast still slows down.
      expect(tune.partActive(TunePart.speed), isTrue);
      tune.nudgeFocused(1); // focused == eq by default
      tune.focusedPart.value = TunePart.speed;
      // 1× is a stop on the line, so one press steps to the next one — the
      // speed line stays answerable on a music file.
      expect(tune.nudgeFocused(1), 'x1_25');
      tune.focusedPart.value = TunePart.aspect;
      expect(tune.nudgeFocused(1), isNull);
      tune.focusedPart.value = TunePart.eq;
      // The audio line is the 13-preset one the moment the file is music.
      expect(tune.eqLine.length, 13);
    });
  });

  group('My (eq_imp.md §1.5)', () {
    test('an empty slot says so, and saving fills it', () {
      expect(tune.hasMy, isFalse);
      tune.setBandGain(0, 3);
      tune.saveMy();
      expect(tune.hasMy, isTrue);
      expect(tune.mySlot.value!.at(0), 3);
    });

    test('applying My is a custom curve, not a new stop on the line', () {
      tune.setBandGain(5, -2);
      tune.saveMy();
      tune.resetBands();
      expect(tune.eq.value.isFlat, isTrue);
      tune.applyMy();
      expect(tune.eq.value.at(5), -2);
      expect(tune.eqCustom.value, isTrue);
      expect(tune.eqStop.value, isNull);
      expect(tune.labelFor(TunePart.eq), 'Custom');
    });

    test('My survives reset-all, because it is a saved thing', () {
      tune.setBandGain(0, 4);
      tune.saveMy();
      tune.resetAll();
      expect(tune.hasMy, isTrue);
      expect(tune.mySlot.value!.at(0), 4);
      expect(tune.eq.value.isFlat, isTrue);
    });
  });

  group('reset-all', () {
    test('every line and slider goes back to the untouched media', () {
      tune.selectStop(TunePart.eq, 'movie');
      tune.selectStop(TunePart.picture, 'vivid');
      tune.selectStop(TunePart.aspect, 'a1_1');
      tune.selectStop(TunePart.speed, 'x3');
      tune.setCurveOnVideo(true);
      tune.resetAll();
      expect(tune.eq.value.isFlat, isTrue);
      expect(tune.picture.value, PictureValues.original);
      expect(tune.aspectRatio.value, 0);
      expect(tune.speed.value, 1);
      expect(tune.curveOnVideo.value, isFalse);
      expect(tune.snapWindow.value, isFalse);
      expect(tune.keepPitch.value, isTrue);
      // Flat means the filter left the chain: the engine got a flat curve.
      expect(fake.eqCurves.last.isFlat, isTrue);
    });
  });

  group('the window is the screen (§1.10)', () {
    test('snap on asks for the file’s own shape, once per shape', () {
      tune.fileAspect.value = 2.35;
      tune.setSnapWindow(true);
      expect(fake.snapModes, <bool>[true]);
      expect(fake.fitted, <double>[2.35]);
      // The same shape twice is not two resizes.
      tune.snapWindowToFit();
      expect(fake.fitted.length, 1);
      // A new film changes the shape, so the window follows it.
      tune.fileAspect.value = 1.333333;
      tune.snapWindowToFit(force: true);
      expect(fake.fitted.last, closeTo(1.333333, 1e-6));
      tune.setSnapWindow(false);
      expect(fake.snapModes.last, isFalse);
    });

    test('a fixed stop snaps to the stop, not to the file', () {
      tune.fileAspect.value = 1.777778;
      tune.selectStop(TunePart.aspect, 'a916');
      tune.setSnapWindow(true);
      expect(fake.fitted.last, 0.5625);
    });

    test('nothing is fitted while snap is off', () {
      tune.fileAspect.value = 1.777778;
      tune.snapWindowToFit(force: true);
      expect(fake.fitted, isEmpty);
      expect(fake.snapModes, isEmpty);
    });
  });

  group('grey means grey (§12)', () {
    test('live media: the panel moves, mpv hears nothing', () {
      tune.available.value = false;
      tune.selectStop(TunePart.picture, 'vivid');
      tune.selectStop(TunePart.aspect, 'a235');
      tune.selectStop(TunePart.speed, 'x2');
      tune.setBandGain(0, 6);
      expect(tune.picture.value.saturation, 26); // remembered for the next file
      expect(fake.pictureWrites, isEmpty);
      expect(fake.aspectWrites, isEmpty);
      expect(fake.speedWrites, isEmpty);
      expect(fake.eqCurves, isEmpty);
      expect(tune.partActive(TunePart.eq), isFalse);
      expect(tune.nudgeFocused(1), isNull);
    });

    test('a stopped player writes nothing either', () {
      tune.available.value = false;
      tune.resetAll();
      expect(fake.pictureWrites, isEmpty);
      expect(fake.eqCurves, isEmpty);
    });

    test('the keyboard tier only drives the focused line', () {
      tune.focusedPart.value = TunePart.picture;
      tune.nudgeFocused(1);
      expect(tune.pictureStop.value, 'vivid');
      expect(tune.eqStop.value, 'flat');
      tune.moveFocus(1);
      expect(tune.focusedPart.value, TunePart.aspect);
      tune.moveFocus(-1);
      expect(tune.focusedPart.value, TunePart.picture);
    });

    test('focus wraps, so four presses come back where they started', () {
      tune.focusedPart.value = TunePart.eq;
      for (int i = 0; i < 4; i++) {
        tune.moveFocus(1);
      }
      expect(tune.focusedPart.value, TunePart.eq);
    });

    test('stepping a line lands on the next named stop, both ways', () {
      tune.focusedPart.value = TunePart.eq;
      expect(tune.nudgeFocused(1), 'movie');
      expect(tune.nudgeFocused(1), 'musicvideo');
      expect(tune.nudgeFocused(-1), 'movie');
      // The ends are ends: no wrap, no change, no card.
      tune.selectStop(TunePart.eq, 'flat');
      expect(tune.nudgeFocused(-1), isNull);
      tune.selectStop(TunePart.eq, 'documentary');
      expect(tune.nudgeFocused(1), isNull);
    });

    test('from between two stops a step moves to the stop it faces', () {
      final double a = tune.eqLine.positionOf(1);
      final double b = tune.eqLine.positionOf(2);
      tune.setKnob(TunePart.eq, (a + b) / 2, commit: false);
      expect(tune.nudgeFocused(-1), 'movie');
      tune.setKnob(TunePart.eq, (a + b) / 2, commit: false);
      expect(tune.nudgeFocused(1), 'musicvideo');
    });
  });

  group('persistence (§6)', () {
    test('a kept change is on disk, and it is the whole panel', () async {
      tune.selectStop(TunePart.eq, 'movie');
      tune.selectStop(TunePart.speed, 'x1_5');
      tune.setKeepPitch(false);
      tune.setCurveOnVideo(true);
      await tune.persistNow();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final TuneState saved = TuneState.decode(prefs.getString('tune_state'));
      expect(saved.eqStop, 'movie');
      expect(saved.eqGains, TunePresets.video[1].gains);
      expect(saved.speed, 1.5);
      expect(saved.keepPitch, isFalse);
      expect(saved.curveOnVideo, isTrue);
    });

    test('a released drag flushes even while the debounce is running',
        () async {
      tune.beginGesture();
      tune.setBandGain(2, 4, commit: false);
      await tune.endGesture();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(TuneState.decode(prefs.getString('tune_state')).eqGains[2], 4);
    });

    test('what the store holds is what the next load becomes', () async {
      tune.selectStop(TunePart.picture, 'faded');
      tune.setBandGain(7, -6);
      await tune.flush();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString('tune_state')!;
      tune.resetForTest();
      expect(tune.picture.value, PictureValues.original);
      tune.applyState(TuneState.decode(raw), persist: false, push: true);
      expect(tune.labelFor(TunePart.picture), 'Faded');
      expect(tune.eq.value.at(7), -6);
      expect(tune.eqCustom.value, isTrue);
      // The restored state is pushed, so the engine catches up on its own.
      expect(fake.pictureWrites.last.contrast, -26);
      expect(fake.eqCurves.last.at(7), -6);
    });

    test('an empty learning map writes no key at all', () async {
      await tune.persistMemory();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('eq_auto_memory'), isFalse);
      tune.memory.teach('audio|jazz', 'jazz');
      await tune.persistMemory();
      expect(prefs.getString('eq_auto_memory'), contains('audio|jazz'));
    });

    test('clear and Undo restore the exact map', () {
      tune.memory.teach('audio|jazz', 'jazz');
      tune.memory.teach('video|the news', 'documentary');
      final previous = tune.clearMemory();
      expect(tune.memory.isEmpty, isTrue);
      expect(tune.autoPick.value, isNull);
      tune.restoreMemory(previous);
      expect(tune.memory.length, 2);
      expect(tune.memory.presetFor('audio|jazz'), 'jazz');
      expect(tune.memory.presetFor('video|the news'), 'documentary');
    });
  });

  group('one popup world (follow.md rule 3)', () {
    test('opening the Tune panel closes the other two', () {
      final PanelService panels = PanelService.instance;
      panels.playlistOpen.value = true;
      panels.trackPanelOpen.value = true;
      panels.toggleTunePanel();
      expect(panels.tunePanelOpen.value, isTrue);
      expect(panels.playlistOpen.value, isFalse);
      expect(panels.trackPanelOpen.value, isFalse);
      expect(panels.anyOpen, isTrue);
      panels.closeTunePanel();
      expect(panels.anyOpen, isFalse);
      // Toggling it closed again leaves nothing up.
      panels.toggleTunePanel();
      panels.toggleTunePanel();
      expect(panels.tunePanelOpen.value, isFalse);
    });
  });

  group('a new file (§1.6)', () {
    test('the line re-lays, the curve stays, the knob parks nearest', () {
      // Music first, on a preset the video set does not have.
      tune.fileKind.value = TuneFileKind.audio;
      tune.selectStop(TunePart.eq, 'vocal');
      expect(tune.labelFor(TunePart.eq), 'Vocal');
      expect(tune.eqLine.length, 13);
      // Then a video lands: the 4-stop line, the numbers kept, the knob
      // parked where the curve still makes sense — never lost.
      tune.fileKind.value = TuneFileKind.video;
      tune.resyncEqFromCurve();
      expect(tune.eqLine.length, 4);
      expect(
        tune.eq.value,
        TunePresets.presetByKey('vocal', TuneFileKind.audio)!.curve,
      );
      expect(tune.eqStop.value, isNot('vocal'));
      expect(tune.eqCustom.value, isTrue);
      expect(tune.labelFor(TunePart.eq), 'Custom');
    });

    test('a curve that is a preset of the NEW set parks on that name', () {
      tune.fileKind.value = TuneFileKind.audio;
      tune.eq.value = TunePresets.video[1].curve; // Movie, from a video
      tune.fileKind.value = TuneFileKind.video;
      tune.resyncEqFromCurve();
      expect(tune.eqStop.value, 'movie');
      expect(tune.eqCustom.value, isFalse);
      expect(tune.labelFor(TunePart.eq), 'Movie');
      expect(tune.eqKnob.value, tune.eqLine.positionForKey('movie'));
    });
    test('a stopped player drops the cached filter belief, nothing else', () {
      // `forgetInstalledFilter` is the whole of SALU's reset on a new file:
      // mpv rebuilds its chain, so the engine must stop believing the
      // previous curve is installed (§2's closing rule).
      tune.selectStop(TunePart.eq, 'movie');
      expect(fake.eqCurves.length, 1);
      fake.reset();
      tune.selectStop(TunePart.eq, 'movie');
      // The service writes the same curve again — the fake starts empty, so
      // the second write is what the next file gets.
      expect(fake.eqCurves.length, 1);
    });
  });

  group('the tone histogram (§7a)', () {
    test('Rec. 709 luma: black, white, grey, blue and green land in their bins',
        () {
      final Uint8List rgba = Uint8List.fromList(<int>[
        0, 0, 0, 255, // black
        255, 255, 255, 255, // white
        128, 128, 128, 255, // mid grey
        0, 0, 255, 255, // saturated blue
        0, 255, 0, 255, // saturated green
      ]);
      final ToneHistogram h = ToneHistogram.fromRgba(rgba, width: 5, height: 1);
      expect(h.total, 5);
      expect(h.bins.length, ToneHistogram.binCount);
      expect(h.bins.first, 1); // black at the darkest end
      expect(h.bins[16], 1); // 128 grey
      expect(h.bins[2], 1); // blue: luma 18
      expect(h.bins.last, 1); // white at the brightest end
      // Green (luma 182, bin 22) reads brighter than blue (18, bin 2) — that
      // weighting is the whole reason this is not a plain mean of r, g and b.
      expect(h.bins[22], 1);
      expect(h.share(0), closeTo(0.2, 1e-9));
      expect(h.peakShare, closeTo(0.2, 1e-9));
      expect(h.meanTone, greaterThan(0));
      expect(h.meanTone, lessThan(1));
      expect(h.isEmpty, isFalse);
    });

    test('an empty frame is an empty reading, never a divide by zero', () {
      final ToneHistogram empty =
          ToneHistogram(List<int>.filled(ToneHistogram.binCount, 0));
      expect(empty.isEmpty, isTrue);
      expect(empty.total, 0);
      expect(empty.share(0), 0);
      expect(empty.share(-1), 0);
      expect(empty.meanTone, 0);
      expect(empty.peakShare, 0);
      expect(empty.shape.every((double v) => v == 0), isTrue);
      // A zero-sized buffer is refused, not read out of bounds.
      final ToneHistogram none =
          ToneHistogram.fromRgba(Uint8List(0), width: 0, height: 0);
      expect(none.isEmpty, isTrue);
    });

    test('the shape is normalised to its peak, so a dark frame still reads',
        () {
      final List<int> bins = List<int>.filled(ToneHistogram.binCount, 0);
      bins[10] = 1;
      bins[11] = 4; // the peak
      bins[12] = 2;
      final List<double> shape = ToneHistogram(bins).shape;
      expect(shape.length, ToneHistogram.binCount);
      expect(shape[11], closeTo(1, 1e-9));
      expect(shape[11], greaterThan(shape[10]));
      expect(shape[11], greaterThan(shape[12]));
      for (final double v in shape) {
        expect(v, lessThanOrEqualTo(1 + 1e-9));
        expect(v, greaterThanOrEqualTo(0));
      }
    });

    test('nothing to read is null, not an empty histogram', () async {
      final ToneHistogramSampler sampler =
          ToneHistogramSampler(capture: () async => null);
      expect(await sampler.sample(), isNull);
    });

    test('a real frame is binned — and disposed — by the sampler', () async {
      final ui.Image frame = await image(
        <int>[0, 0, 0, 255, 255, 255, 255, 255],
        2,
        1,
      );
      final ToneHistogramSampler sampler =
          ToneHistogramSampler(capture: () async => frame);
      final ToneHistogram? h = await sampler.sample();
      expect(h, isNotNull);
      expect(h!.total, 2);
      expect(h.bins.first, 1); // the black pixel
      expect(h.bins.last, 1); // the white pixel
      // The binning is all that leaves the sampler; the image goes with it.
      expect(frame.debugDisposed, isTrue);
    });

    test('the panel reads while it is open, and a bad frame is only silence',
        () async {
      expect(tune.histogram.value, isNull);
      tune.setHistogramActive(true);
      // Let the read's await chain settle. The fake has no frame, so it is
      // one hop, and the capture itself already happened synchronously.
      await Future<void>.delayed(Duration.zero);
      // One reading at once, not one gap later — and with nothing to sample
      // (the fake has no frame) the reading is simply absent.
      expect(fake.captures, 1);
      expect(tune.histogram.value, isNull);
      tune.setHistogramActive(false);
      // Closing the panel drops the reading, so a reopened panel never shows
      // the last film's shape.
      tune.histogram.value = ToneHistogram(
        List<int>.filled(ToneHistogram.binCount, 0)..[5] = 3,
      );
      tune.setHistogramActive(false);
      expect(tune.histogram.value, isNull);
    });

    test('a real read reaches the notifier the bars listen to', () async {
      fake.frame = await image(
        <int>[0, 0, 0, 255, 255, 255, 255, 255],
        2,
        1,
      );
      await tune.sampleToneNow();
      expect(fake.captures, 1);
      expect(tune.histogram.value, isNotNull);
      expect(tune.histogram.value!.total, 2);
      expect(tune.histogram.value!.bins.last, 1);
    });

    test('nothing is read on live media, and nothing on an audio file (§12)',
        () async {
      tune.available.value = false;
      await tune.sampleToneNow();
      expect(fake.captures, 0);
      expect(tune.histogram.value, isNull);
      // §7a is a picture reading: an audio file has none to take.
      tune.available.value = true;
      tune.videoPartsActive.value = false;
      await tune.sampleToneNow();
      expect(fake.captures, 0);
    });
  });

  group('scenes (§7b)', () {
    test('Cinema moves all four lines together', () {
      tune.selectStop(TunePart.speed, 'x2');
      tune.setSnapWindow(false);
      tune.applyScene(TuneScene.byKey('cinema')!);
      expect(tune.labelFor(TunePart.eq), 'Movie');
      expect(tune.labelFor(TunePart.picture), 'Night');
      expect(tune.aspectAuto, isTrue);
      expect(tune.speed.value, 1);
      expect(tune.speedStop.value, 'x1');
      expect(tune.snapWindow.value, isTrue);
      expect(fake.snapModes.last, isTrue);
      expect(tune.eqStop.value, 'movie');
      expect(tune.pictureStop.value, 'night');
    });

    test('Vivid asks for a flat sound and the file shape, no snap', () {
      tune.selectStop(TunePart.eq, 'movie');
      tune.applyScene(TuneScene.byKey('vivid')!);
      expect(tune.labelFor(TunePart.eq), 'Flat');
      expect(tune.labelFor(TunePart.picture), 'Vivid');
      expect(tune.aspectAuto, isTrue);
      expect(tune.snapWindow.value, isFalse);
      expect(fake.snapModes.last, isFalse);
    });

    test('a sound the line does not have is skipped, not forced', () {
      // Podcast asks for Vocal — an audio-line preset. A video has no such
      // stop, so the sound it has stays rather than sliding to a neighbour.
      tune.selectStop(TunePart.eq, 'movie');
      tune.applyScene(TuneScene.byKey('podcast')!);
      expect(tune.labelFor(TunePart.eq), 'Movie');
      expect(tune.eqStop.value, 'movie');
      // The rest of the scene still lands.
      expect(tune.labelFor(TunePart.picture), 'Original');
      expect(tune.snapWindow.value, isFalse);
    });

    test('the same scene does move the sound on an audio file', () {
      tune.fileKind.value = TuneFileKind.audio;
      tune.applyScene(TuneScene.byKey('podcast')!);
      expect(tune.labelFor(TunePart.eq), 'Vocal');
      expect(tune.eqStop.value, 'vocal');
    });

    test('a scene on live media writes nothing at all (§12)', () {
      tune.available.value = false;
      final TuneState before = tune.capture();
      tune.applyScene(TuneScene.byKey('cinema')!);
      expect(tune.capture().eqGains, before.eqGains);
      expect(tune.capture().aspectStop, before.aspectStop);
      expect(fake.eqCurves, isEmpty);
      expect(fake.aspectWrites, isEmpty);
      expect(fake.snapModes, isEmpty);
    });
  });

  group('learning the whole curve (§7c)', () {
    const AutoEqFacts jazz = AutoEqFacts(
      kind: TuneFileKind.audio,
      fileName: 'mix',
      genre: 'jazz',
    );

    test('a curve you kept comes back exactly, and calls itself Custom',
        () async {
      final List<double> mine = <double>[3, -2, 1, 0, -1, 2, -3, 1, 0, 2];
      tune.memory.teach(AutoEq.memoryKey(jazz), gains: mine);
      await tune.applyAutoEq(jazz);
      expect(tune.eq.value.gains, mine);
      expect(tune.eqStop.value, isNull);
      expect(tune.eqCustom.value, isTrue);
      expect(tune.autoPick.value, 'Custom');
      expect(AutoEq.describe(tune.autoPick.value!), 'Auto EQ · Custom');
      // The engine gets those numbers, not the nearest preset to them.
      expect(fake.eqCurves.last, mine);
    });

    test('the numbers survive a capture/restore round trip', () async {
      final List<double> mine = <double>[3, -2, 1, 0, -1, 2, -3, 1, 0, 2];
      tune.memory.teach(AutoEq.memoryKey(jazz), gains: mine);
      await tune.applyAutoEq(jazz);
      final TuneState saved = tune.capture();
      fake.eqCurves.clear();
      tune.applyState(saved, persist: false, push: true);
      expect(tune.eq.value.gains, mine);
      expect(tune.eqStop.value, isNull);
      expect(tune.eqCustom.value, isTrue);
      expect(fake.eqCurves.last, mine);
    });

    test('a manual tap wins, and puts the automation dot out (§5)', () async {
      tune.memory.teach(AutoEq.memoryKey(jazz), presetKey: 'rock');
      await tune.applyAutoEq(jazz);
      expect(tune.autoPick.value, 'Rock');
      // The tap decides — and the dot, which is Auto's report and not a
      // second name for the current curve, goes dark with it.
      tune.selectStop(TunePart.eq, 'flat');
      expect(tune.eqStop.value, 'flat');
      expect(tune.autoPick.value, isNull);
      // A band drag too.
      await tune.applyAutoEq(jazz);
      expect(tune.autoPick.value, 'Rock');
      tune.setBandGain(0, 3);
      expect(tune.autoPick.value, isNull);
      await tune.applyAutoEq(jazz);
      tune.resetBands();
      expect(tune.autoPick.value, isNull);
      // …but a hover is not a tap: leaving a preview decides nothing, so the
      // report it interrupted is still true.
      await tune.applyAutoEq(jazz);
      expect(tune.autoPick.value, 'Rock');
      tune.beginPreview();
      tune.setKnob(TunePart.eq, tune.eqLine.positionOf(0), commit: false);
      tune.endPreview();
      expect(tune.eqStop.value, 'rock');
      expect(tune.autoPick.value, 'Rock');
    });

    test('a kept preset answers, and the dot says its name', () async {
      tune.memory.teach(AutoEq.memoryKey(jazz), presetKey: 'rock');
      await tune.applyAutoEq(jazz);
      final EqPreset rock =
          TunePresets.presetByKey('rock', TuneFileKind.audio)!;
      expect(tune.eqStop.value, 'rock');
      expect(tune.eq.value.gains, rock.curve);
      expect(tune.autoPick.value, rock.label);
      expect(AutoEq.describe(tune.autoPick.value!), 'Auto EQ · Rock');
    });

    test('a kept curve outranks the preset nearest to it (§7c)', () async {
      final List<double> mine = <double>[3, -2, 1, 0, -1, 2, -3, 1, 0, 2];
      tune.memory.teach(AutoEq.memoryKey(jazz), presetKey: 'rock', gains: mine);
      await tune.applyAutoEq(jazz);
      // A named stop wins when the person landed on one — the curve is the
      // memory for the times they did not.
      expect(tune.eqStop.value, 'rock');
      expect(tune.eq.value.gains,
          TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve);
    });

    test('a key from another line is not a guess about this one', () async {
      // Vocal is an audio sound; a video line has no such stop, so the stale
      // entry is not applied to the film.
      const AutoEqFacts film =
          AutoEqFacts(kind: TuneFileKind.video, fileName: 'film');
      tune.memory.teach(AutoEq.memoryKey(film), presetKey: 'vocal');
      await tune.applyAutoEq(film);
      expect(tune.eqStop.value, isNot('vocal'));
      expect(tune.eq.value.gains,
          isNot(TunePresets.presetByKey('vocal', TuneFileKind.audio)!.curve));
      // §5's rules answer instead, here the plain sound.
      expect(tune.eqStop.value, 'flat');
    });

    test('a curve you set yourself never lights the automation dot', () {
      tune.fileKind.value = TuneFileKind.audio;
      tune.selectStop(TunePart.eq, 'rock');
      tune.saveMy();
      tune.selectStop(TunePart.eq, 'flat');
      expect(tune.autoPick.value, isNull);
      tune.applyMy();
      expect(tune.eqStop.value, isNull);
      expect(tune.eqCustom.value, isTrue);
      expect(tune.autoPick.value, isNull);
      expect(AutoEq.describe('Rock'), 'Auto EQ · Rock');
    });
  });
}
