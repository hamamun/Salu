import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_state.dart';

/// The panel's one settings entry (eq_imp.md §6: "one settings entry,
/// persisted with `shared_preferences`"). What matters here is not that the
/// JSON comes back — it is that a hand-edited, half-written or plain broken
/// blob can never take the player down: the store's answer to nonsense is the
/// factory default, and the default is "nothing installed, nothing changed".
void main() {
  group('round trip', () {
    test('the factory default survives encode → decode untouched', () {
      final TuneState back = TuneState.decode(TuneState.initial.encode());
      expect(back.encode(), TuneState.initial.encode());
      expect(back.eqGains.every((double g) => g == 0), isTrue);
      expect(back.keepPitch, isTrue);
      expect(back.snapWindow, isFalse);
      expect(back.curveOnVideo, isFalse);
      expect(back.speed, 1);
      expect(back.eqCurve.isFlat, isTrue);
      expect(back.picture, PictureValues.original);
    });

    test('every value the panel can hold comes back the same', () {
      final TuneState state = TuneState.initial.copyWith(
        kind: TuneFileKind.audio,
        eqGains: <double>[5, 4, 3, 1, -2, -1, 2, 3, 4, 5],
        eqKnob: 0.25,
        eqStop: 'rock',
        picture: const PictureValues(
          saturation: 26,
          gamma: -6,
          contrast: 14,
          brightness: 5,
          hue: 0,
        ),
        pictureKnob: 0.4,
        pictureStop: 'vivid',
        aspectKnob: 0.5714285714285714,
        aspectStop: 'a235',
        speed: 1.25,
        speedKnob: 0.36363636363636365,
        speedStop: 'x1_25',
        keepPitch: false,
        snapWindow: true,
        curveOnVideo: true,
        my: <double>[-1, 0, 1, 2, 3, 4, 5, 6, 7, 8],
      );
      final TuneState back = TuneState.decode(state.encode());
      expect(back.encode(), state.encode());
      expect(back.kind, TuneFileKind.audio);
      expect(back.eqStop, 'rock');
      expect(back.pictureStop, 'vivid');
      expect(back.aspectStop, 'a235');
      expect(back.speed, 1.25);
      expect(back.keepPitch, isFalse);
      expect(back.snapWindow, isTrue);
      expect(back.curveOnVideo, isTrue);
      expect(back.myCurve, const EqCurve(<double>[-1, 0, 1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test('an empty slot writes no key at all', () {
      final Map<String, Object?> json =
          jsonDecode(TuneState.initial.encode()) as Map<String, Object?>;
      expect(json.containsKey('my'), isFalse);
      expect(json['v'], 1);
    });
  });

  group('nonsense is forgiven', () {
    test('a truncated or hostile blob falls back to the default', () {
      for (final Object? raw in <Object?>[
        null,
        '',
        'not json',
        '{',
        '[1,2,3]',
        '{"eq": 7}',
        '{"eq": ["a","b"],"spd": "fast"}',
        jsonEncode(<String, Object?>{'v': 99, 'snap': 'yes'}),
      ]) {
        final TuneState back = TuneState.decode(raw);
        // The silence SALU boots with: nothing in the audio chain, nothing
        // pushed to the picture, normal speed, pitch kept.
        expect(back.eqCurve.isFlat, isTrue, reason: '$raw');
        expect(back.picture, PictureValues.original, reason: '$raw');
        expect(back.speed, 1, reason: '$raw');
        expect(back.keepPitch, isTrue, reason: '$raw');
        expect(back.snapWindow, isFalse, reason: '$raw');
        expect(back.curveOnVideo, isFalse, reason: '$raw');
        expect(back.my, isNull, reason: '$raw');
      }
    });

    test('out-of-range gains are fenced on the way in, not trusted', () {
      final TuneState back = TuneState.decode(jsonEncode(<String, Object?>{
        'eq': <Object>[999, -999, 0.004, 0.5, 0.5],
      }));
      expect(back.eqGains[0], kEqGainMax);
      expect(back.eqGains[1], kEqGainMin);
      // A short list keeps its tail silent — a half-written blob must not
      // invent a curve out of nothing.
      expect(back.eqGains.length, kEqBandCount);
      expect(back.eqGains[5], 0);
      expect(back.eqGains[3], 0.5);
    });

    test('a stop key of `null` is kept as "no named stop", not Flat', () {
      final TuneState state =
          TuneState.initial.copyWith(eqStop: 'rock', eqGains: <double>[
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      ], clearEqStop: true);
      expect(state.eqStop, isNull);
      final TuneState back = TuneState.decode(state.encode());
      expect(back.eqStop, isNull);
      expect(back.eqGains, state.eqGains);
    });
  });
}
