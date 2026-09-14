import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/ui/widgets/tune_continuum.dart';
import 'package:salu/ui/widgets/tune_sliders.dart';

/// **Mouse over preview** (Settings → Equalizer, owner 2026-09-14, default
/// **Off**) — the one gate in front of §8's hover half.
///
/// The preview itself and its revert are the service's contract and are pinned
/// in `test/tune_service_test.dart`; what these tests pin is the SWITCH: off, a
/// pointer resting on a control must reach no callback at all — so a pointer
/// merely passing over can write nothing — and on, the very same rest
/// previews exactly as §8 says. A press is never gated: turning the hover off
/// is not turning the panel off.
void main() {
  /// Every change a control reports: the position (plus the band index) and
  /// whether it is a keep (`true`) or a live move (`false`).
  late List<List<Object>> moves;

  setUp(() {
    moves = <List<Object>>[];
    // The switch is app state, not widget state: put it back where SALU ships
    // it (Off) before every test.
    SettingsService.instance.mouseOverPreview.value = false;
  });

  // ── The line ───────────────────────────────────────────────────────────

  /// A two-stop line is enough: rest anywhere on it and there is a value to
  /// preview.
  final Continuum line = Continuum(
    stops: const <ContinuumStop>[
      ContinuumStop('a', 'A', vector: <double>[0]),
      ContinuumStop('b', 'B', vector: <double>[10]),
    ],
  );

  Widget lineHarness() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: TuneContinuum(
              title: 'Audio Equalizer',
              line: line,
              position: 0,
              label: 'A',
              onChanged: (double t, bool commit) =>
                  moves.add(<Object>[t, commit]),
            ),
          ),
        ),
      ),
    );
  }

  /// A point on the LINE itself — the widget's head sits above it and the
  /// fine layer below, so the centre of the box is not the centre of the line.
  Offset linePoint(WidgetTester tester) =>
      tester.getTopLeft(find.byType(TuneContinuum)) + const Offset(200, 48);

  Future<void> restOn(WidgetTester tester, Offset point) async {
    final TestGesture gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(point);
    // One frame for the enter itself, then well past §8's ~0.3 s lead — so a
    // preview that WOULD start has started, whichever phase the enter lands in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('off (the default): a resting pointer moves nothing',
      (WidgetTester tester) async {
    await tester.pumpWidget(lineHarness());
    await restOn(tester, linePoint(tester));

    expect(moves, isEmpty,
        reason: 'a hover must not reach the line at all');
  });

  testWidgets('on: the same rest previews the value under the pointer',
      (WidgetTester tester) async {
    SettingsService.instance.mouseOverPreview.value = true;
    await tester.pumpWidget(lineHarness());
    await restOn(tester, linePoint(tester));

    expect(moves, isNotEmpty);
    // A hover is not a decision: §8's preview never commits.
    expect(moves.last[1], isFalse);
  });

  testWidgets('the press is never gated: a click keeps with preview off',
      (WidgetTester tester) async {
    await tester.pumpWidget(lineHarness());
    final TestGesture gesture = await tester.startGesture(
      linePoint(tester),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(moves, isNotEmpty);
    // The release keeps what it landed on — the click's own rule, switch or
    // no switch.
    expect(moves.last[1], isTrue);
  });

  // ── The bands ──────────────────────────────────────────────────────────

  Widget bandsHarness() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: TuneBands(
              gains: List<double>.filled(kEqBandCount, 0),
              enabled: true,
              onBand: (int index, double db, bool commit) =>
                  moves.add(<Object>[index, db, commit]),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('off: a band keeps its frequency label under the pointer',
      (WidgetTester tester) async {
    await tester.pumpWidget(bandsHarness());
    expect(find.text(kEqBandLabels[0]), findsOneWidget);
    await restOn(tester, tester.getCenter(find.text(kEqBandLabels[0])));

    expect(moves, isEmpty);
    // The label is a preview too: it says what the band HOLDS, which with the
    // switch off is still the frequency it always names.
    expect(find.text(kEqBandLabels[0]), findsOneWidget);
  });

  testWidgets('on: the band speaks the value under the pointer',
      (WidgetTester tester) async {
    SettingsService.instance.mouseOverPreview.value = true;
    await tester.pumpWidget(bandsHarness());
    await restOn(tester, tester.getCenter(find.text(kEqBandLabels[0])));

    expect(moves, isNotEmpty);
    expect(moves.last[2], isFalse);
    expect(find.text(kEqBandLabels[0]), findsNothing);
  });
}
