import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/panel_service.dart';
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
}
