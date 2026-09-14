import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';
import 'package:salu/core/tune/tune_state.dart';

/// The continuum math the whole Tune panel stands on (eq_imp.md §6's first
/// unit-test line): where the stops sit, what a release snaps to, what the
/// floating label says between stops, and how two stops' payloads blend.
///
/// These are the guarantees the panel cannot re-derive at runtime — a knob
/// that lands somewhere the label does not name, or a release that fails to
/// snap, turns the whole feature into a slot machine.
void main() {
  final Continuum line = Continuum(
    stops: const <ContinuumStop>[
      ContinuumStop('a', 'A', vector: <double>[0, 0]),
      ContinuumStop('b', 'B', vector: <double>[10, 10]),
      ContinuumStop('c', 'C', vector: <double>[0, 10]),
    ],
  );

  group('even spacing', () {
    test('n stops sit at i/(n-1)', () {
      expect(line.positionOf(0), 0);
      expect(line.positionOf(1), 0.5);
      expect(line.positionOf(2), 1);
    });

    test('positionForKey is the stop, and 0 for a key the line does not have',
        () {
      expect(line.positionForKey('c'), 1);
      // An audio preset asked of a video line — the knob parks at the head
      // rather than throwing or landing on an unrelated stop.
      expect(line.positionForKey('nope'), 0);
      expect(line.indexOfKey('nope'), -1);
    });
  });

  group('spans and blends', () {
    test('a position between stops names both and the fraction', () {
      final ContinuumSpan span = line.spanOf(0.25);
      expect(span.a, 0);
      expect(span.b, 1);
      expect(span.frac, 0.5);
      expect(span.isStop, isFalse);
    });

    test('a position on a stop is its own span', () {
      final ContinuumSpan span = line.spanOf(0.5);
      expect(span.a, 1);
      expect(span.b, 1);
      expect(span.isStop, isTrue);
    });

    test('the ends clamp instead of running off the line', () {
      expect(line.spanOf(-0.4).a, 0);
      expect(line.spanOf(-0.4).b, 0);
      expect(line.spanOf(1.4).a, 2);
      expect(line.spanOf(1.4).b, 2);
    });

    test('the payload blends linearly between stops', () {
      expect(line.vectorAt(0), <double>[0, 0]);
      expect(line.vectorAt(0.25), <double>[5, 5]);
      expect(line.vectorAt(0.75), <double>[5, 10]);
      expect(line.vectorAt(1), <double>[0, 10]);
    });

    test('a value line blends its number the same way', () {
      final Continuum shapes = Continuum(
        stops: const <ContinuumStop>[
          ContinuumStop('lo', 'lo', value: 0),
          ContinuumStop('hi', 'hi', value: 100),
        ],
      );
      expect(shapes.valueAt(0.25), 25);
      expect(shapes.valueOnLine(0.25), 25);
      expect(shapes.positionForValue(50), 0.5);
    });
  });

  group('snapping', () {
    test('a release within tolerance lands on the named stop', () {
      expect(line.snap(0.48), 0.5);
      expect(line.stopAtPosition(line.snap(0.48))?.key, 'b');
    });

    test('a release between stops keeps the exact position', () {
      expect(line.snap(0.3), 0.3);
      expect(line.stopAtPosition(line.snap(0.3)), isNull);
    });

    test('nearestStop answers whatever the distance', () {
      expect(line.nearestStop(0.4), 1);
      expect(line.nearestStop(0.1), 0);
    });
  });

  group('the speed line is linear in value (eq_imp.md §3)', () {
    final Continuum speed = TunePresets.speedContinuum();

    test('normal speed sits where the value says, not at the middle', () {
      // 0.25…3.0 with 1× as a stop → 1× is a quarter of the way along.
      expect(speed.positionForKey('x1'),
          closeTo(TuneState.initial.speedKnob, 1e-9));
      expect(speed.positionForKey('x1'), closeTo(0.2727, 1e-3));
      expect(speed.positionForKey('x3'), 1);
    });

    test('the ends of the line are the ends of the range', () {
      expect(speed.valueOnLine(0), closeTo(0.25, 1e-9));
      expect(speed.valueOnLine(1), closeTo(3.0, 1e-9));
    });

    test('a value between stops stays exact — only a near-miss snaps', () {
      final double t = speed.positionForValue(1.37);
      expect(speed.stopAtPosition(t), isNull);
      expect(speed.valueAt(t), closeTo(1.37, 1e-6));
      // 1.37 is further from 1.25 than the line's tolerance, so a release
      // there keeps the number (the label reads `1.37×`, not a stop name).
      expect(speed.snap(t), t);
      // 1.24 is a near-miss: it belongs to 1.25×.
      final double near = speed.positionForValue(1.24);
      expect(speed.stopAtPosition(speed.snap(near))?.key, 'x1_25');
    });
  });

  group('the aspect line', () {
    final Continuum aspect = TunePresets.aspectContinuum();

    test('eight shapes, evenly spaced, Auto at the head', () {
      expect(aspect.length, 8);
      expect(aspect.stopAt(0).key, 'auto');
      expect(aspect.positionOf(1), closeTo(1 / 7, 1e-12));
    });

    test('Auto carries no number of its own', () {
      expect(aspect.stopAt(0).value, isNull);
      expect(TunePresets.isAspectAuto('auto'), isTrue);
      expect(TunePresets.isAspectAuto('a16_9'), isFalse);
      // A knob between stops is still Auto's neighbour, not a new ratio.
      expect(aspect.stopAt(7).value, 0.5625);
    });
  });

  group('labels (eq_imp.md §3)', () {
    test('a custom aspect reads as the number, not a stop name', () {
      expect(formatAspectValue(1.523), '1.52:1');
      expect(formatAspectValue(1.777778), '1.78:1');
      expect(formatAspectValue(0), 'Auto');
    });

    test('a speed keeps its decimals but never pads with zeros', () {
      expect(formatSpeedValue(1.37), '1.37×');
      expect(formatSpeedValue(1.5), '1.5×');
      expect(formatSpeedValue(1), '1×');
      expect(formatSpeedValue(0), '1×');
    });

    test('a blend pair says both names', () {
      expect(formatBlendPair('Pop', 'Rock'), 'Pop ↔ Rock');
    });

    test('a gain carries its sign, half-dB steps and a real minus', () {
      expect(formatGainDb(3), '+3');
      expect(formatGainDb(-4.5), '−4.5');
      expect(formatGainDb(0), '0');
      expect(formatGainDb(11.99), '+12');
    });

    test('clampRange fences anything the pointer can produce', () {
      expect(clampRange(-5, 0, 1), 0);
      expect(clampRange(5, 0, 1), 1);
      expect(clampRange(double.nan, 0, 1), double.nan);
      expect(clampRange(0.5, 0, 1), 0.5);
    });
  });
}
