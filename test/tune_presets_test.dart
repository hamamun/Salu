import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';

/// The preset tables are the feature's promise (eq_imp.md §2 · §3): thirteen
/// named sounds on a music file, four on a video, six looks, seven speeds —
/// and each name must mean exactly the numbers the spec's tables list, or the
/// line lies. Everything the panel prints, the engine writes and the learning
/// map stores comes out of these lists, so they are checked here at the
/// source.
void main() {
  group('the tables of §2, pinned number by number', () {
    // These are the locked starting curves — the whole promise of a named
    // stop — so they are written out here a second time. If a number is ever
    // retuned by ear, this is where that decision gets recorded.
    const Map<String, List<double>> audioTable = <String, List<double>>{
      'flat': <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      'pop': <double>[1, 2, 3, 5, 3, 1, -1, -2, -1, 0],
      'rock': <double>[5, 4, 3, 1, -2, -1, 2, 3, 4, 5],
      'jazz': <double>[4, 3, 1, 0, -2, -2, 0, 1, 2, 3],
      'classical': <double>[5, 4, 3, 2, -2, -3, -3, -1, 2, 4],
      'bass': <double>[10, 8, 6, 3, 0, -1, -2, -2, -1, 0],
      'treble': <double>[-1, -1, 0, 0, 1, 2, 4, 6, 8, 10],
      'vshape': <double>[8, 6, 3, 1, -2, -2, 1, 4, 7, 9],
      'vocal': <double>[-2, -3, -4, -2, 0, 3, 5, 4, 2, 0],
      'lounge': <double>[4, 3, 2, 2, 0, -1, -2, -3, -2, -1],
      'live': <double>[3, 2, 1, 0, 2, 3, 4, 5, 6, 7],
      'dance': <double>[9, 8, 5, 2, -1, -1, 1, 3, 5, 7],
      'phone': <double>[-6, -5, -4, -3, -1, 1, 2, 3, 2, 0],
    };
    const Map<String, List<double>> videoTable = <String, List<double>>{
      'flat': <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      'movie': <double>[4, 3, 1, 0, 1, 2, 3, 4, 3, 2],
      'musicvideo': <double>[7, 5, 3, 1, 0, 1, 2, 4, 5, 3],
      'documentary': <double>[-3, -3, -2, 0, 1, 3, 4, 3, 1, 0],
    };

    test('the 13 stops of a music file', () {
      expect(
        TunePresets.audio.map((EqPreset p) => p.key).toList(),
        audioTable.keys.toList(),
      );
      expect(
        TunePresets.audio.map((EqPreset p) => p.label).toList(),
        <String>[
          'Flat', 'Pop', 'Rock', 'Jazz', 'Class', 'Bass', 'Treb', //
          'V-Shape', 'Vocal', 'Lounge', 'Live', 'Dance', 'Phone',
        ],
      );
      for (final EqPreset p in TunePresets.audio) {
        expect(p.gains, audioTable[p.key], reason: p.key);
      }
    });

    test('the 4 stops of a video file', () {
      expect(
        TunePresets.video.map((EqPreset p) => p.key).toList(),
        videoTable.keys.toList(),
      );
      expect(TunePresets.video.map((EqPreset p) => p.label).toList(),
          <String>['Flat', 'Movie', 'Music V', 'Doc']);
      for (final EqPreset p in TunePresets.video) {
        expect(p.gains, videoTable[p.key], reason: p.key);
      }
    });

    test('My is a mark below the line, never a stop on it', () {
      for (final TuneFileKind kind in TuneFileKind.values) {
        expect(
          TunePresets.audioContinuum(kind).stops
              .any((ContinuumStop s) => s.key == 'my'),
          isFalse,
        );
      }
    });
  });

  group('the audio equalizer set (§2)', () {
    test('13 stops on a music file, 4 on a video', () {
      expect(TunePresets.audio.length, 13);
      expect(TunePresets.video.length, 4);
      expect(TunePresets.forKind(TuneFileKind.audio).length, 13);
      expect(TunePresets.forKind(TuneFileKind.video).length, 4);
      expect(TunePresets.audioContinuum(TuneFileKind.audio).length, 13);
      expect(TunePresets.audioContinuum(TuneFileKind.video).length, 4);
    });

    test('every preset fills the 10 bands inside ±12 dB', () {
      for (final EqPreset p in <EqPreset>[
        ...TunePresets.audio,
        ...TunePresets.video,
      ]) {
        expect(p.gains.length, kEqBandCount, reason: p.key);
        for (final double g in p.gains) {
          // ±12 dB is the slider's whole world; a preset outside it would
          // be silently re-fenced by the engine and no longer match itself.
          expect(g, inInclusiveRange(kEqGainMin, kEqGainMax));
        }
      }
    });

    test('keys are unique, and Flat is the line head of both sets', () {
      for (final List<EqPreset> set in <List<EqPreset>>[
        TunePresets.audio,
        TunePresets.video,
      ]) {
        expect(set.map((EqPreset p) => p.key).toSet().length, set.length);
        expect(set.first.key, 'flat');
        expect(set.first.curve.isFlat, isTrue);
        // Only Flat is silent: a "loudness" preset that does nothing is a
        // bug, and an accidental all-zero row would be invisible otherwise.
        for (final EqPreset p in set.skip(1)) {
          expect(p.curve.isFlat, isFalse, reason: p.key);
        }
      }
    });

    test('an audio name means nothing on a video line', () {
      expect(TunePresets.presetByKey('pop', TuneFileKind.audio), isNotNull);
      expect(TunePresets.presetByKey('pop', TuneFileKind.video), isNull);
      expect(TunePresets.presetByKey(null, TuneFileKind.audio), isNull);
      expect(TunePresets.presetByKey('flat', TuneFileKind.video)?.label,
          'Flat');
    });

    test('a preset curve matches back to its own name', () {
      for (final EqPreset p in TunePresets.audio) {
        expect(TunePresets.matchCurve(p.curve, TuneFileKind.audio)?.key, p.key,
            reason: p.key);
      }
      // A curve that is not in the set answers `null` — the line says
      // `Custom`, it never guesses.
      expect(
        TunePresets.matchCurve(const EqCurve(<double>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0.5]),
            TuneFileKind.audio),
        isNull,
      );
    });

    test('peakGain reads the loudest ask of the line', () {
      expect(TunePresets.peakGain(const EqCurve.flat()), 0);
      expect(TunePresets.peakGain(TunePresets.presetByKey('bass', TuneFileKind.audio)!.curve), 10);
      expect(
        TunePresets.peakGain(const EqCurve(<double>[
          -11, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ])),
        -11,
      );
    });
  });

  group('the picture looks (§4)', () {
    test('the six looks are the table, in the spec’s order', () {
      const List<List<double>> table = <List<double>>[
        <double>[0, 0, 0, 0, 0], // Original
        <double>[26, -6, 14, 5, 0], // Vivid
        <double>[-6, 30, -14, 12, 0], // Night
        <double>[-24, 8, -26, 9, 0], // Faded
        <double>[8, 0, 4, 2, -6], // Warm
        <double>[6, 0, 5, 1, 7], // Cool
      ];
      expect(TunePresets.looks.length, table.length);
      for (int i = 0; i < table.length; i++) {
        expect(TunePresets.looks[i].values, table[i],
            reason: TunePresets.looks[i].key);
      }
    });

    test('Original is all-zero and matches itself', () {
      expect(TunePresets.looks.first.key, 'original');
      expect(TunePresets.looks.first.values.every((double v) => v == 0), isTrue);
      expect(TunePresets.matchPicture(PictureValues.original)?.key, 'original');
      for (final PictureLook l in TunePresets.looks) {
        expect(TunePresets.matchPicture(l.picture)?.key, l.key, reason: l.key);
      }
      expect(TunePresets.lookByKey(null), isNull);
      expect(TunePresets.lookByKey('nope'), isNull);
    });

    test('a look blends into the next one halfway', () {
      final PictureValues vivid = TunePresets.lookByKey('vivid')!.picture;
      final PictureValues night = TunePresets.lookByKey('night')!.picture;
      final PictureValues mid = PictureValues.blend(vivid, night, 0.5);
      expect(mid.saturation, (26 + -6) / 2);
      expect(mid.gamma, (-6 + 30) / 2);
      expect(mid.contrast, (14 + -14) / 2);
      expect(mid.brightness, (5 + 12) / 2);
      expect(mid.hue, 0);
    });

    test('the picture line carries every look as a stop', () {
      final Continuum line = TunePresets.pictureContinuum();
      expect(line.length, TunePresets.looks.length);
      expect(line.stopAt(0).key, 'original');
      expect(line.vectorAt(0)?.length, kPictureKeys.length);
      expect(line.vectorAt(1)?.length, kPictureKeys.length);
    });
  });

  group('shapes and speeds (§3)', () {
    test('the eight aspect stops are the spec’s list', () {
      expect(
        TunePresets.aspectStops.map((ContinuumStop s) => s.label).toList(),
        <String>['Auto', '4:3', '16:9', '1.85', '2.35', '21:9', '1:1', '9:16'],
      );
      expect(TunePresets.aspectStops.first.value, isNull);
      expect(TunePresets.aspectStops.last.value, 0.5625);
    });

    test('the seven speed stops, and the value each one means', () {
      expect(TunePresets.speedStops.length, 7);
      expect(TunePresets.speedStopForValue(1.5)?.key, 'x1_5');
      expect(TunePresets.speedStopForValue(1.0)?.label, '1×');
      expect(TunePresets.speedStopForValue(1.37), isNull);
    });
  });

  group('the curve and the values themselves', () {
    test('a band edit fences itself inside ±12 and quantises to halves', () {
      const EqCurve flat = EqCurve.flat();
      expect(flat.withBand(0, 40).at(0), kEqGainMax);
      expect(flat.withBand(0, -40).at(0), kEqGainMin);
      expect(flat.withBand(3, 2.3).at(3), 2.5);
      expect(flat.withBand(99, 5).at(0), 0); // out of range: nothing moves
      expect(flat.withBand(-1, 5).at(0), 0);
    });

    test('a gain under the zero tolerance counts as silence', () {
      expect(const EqCurve.flat().isFlat, isTrue);
      expect(const EqCurve(<double>[0.005, 0, 0, 0, 0, 0, 0, 0, 0, -0.005])
          .isFlat, isTrue);
      expect(const EqCurve(<double>[0.02, 0, 0, 0, 0, 0, 0, 0, 0, 0]).isFlat,
          isFalse);
    });

    test('JSON survives a round trip and forgives a broken one', () {
      final EqCurve curve =
          TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve;
      expect(EqCurve.fromJson(curve.toJson()), curve);
      expect(EqCurve.fromJson(null).isFlat, isTrue);
      expect(EqCurve.fromJson(<Object>['x', 3]).at(1), 3);
      expect(EqCurve.fromJson(<Object>[3]).gains.length, kEqBandCount);
      expect(PictureValues.fromJson(null), PictureValues.original);
      expect(PictureValues.fromJson(<Object>['a']).saturation, 0);
      expect(PictureValues.fromJson(<Object>[200]).saturation, kPictureMax);
    });

    test('the picture values clamp and answer by key', () {
      const PictureValues v = PictureValues(
        saturation: 500,
        gamma: -500,
        contrast: 3,
        brightness: 4,
        hue: 5,
      );
      final PictureValues c = v.clamped();
      expect(c.saturation, kPictureMax);
      expect(c.gamma, kPictureMin);
      expect(c.valueAt(2), 3);
      expect(c.withKey('hue', 40).hue, 40);
      expect(c.withValue(0, 40).saturation, 40);
      expect(c.vector.length, kPictureKeys.length);
    });
  });
}
