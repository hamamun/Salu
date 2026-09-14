import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/ui/widgets/tune_sliders.dart';

/// The glide (eq_imp.md §1.3's ~200 ms settle): a jump glides, a drag lands —
/// and a change that arrives *while* a glide is running must carry on from the
/// line the eye can actually see. The bug this pins down is one frame of
/// honesty: remembering the previous *target* instead of the shape on screen
/// makes a drag after a preset jump flick back to the old curve and climb
/// again from there.
void main() {
  testWidgets('a jump glides; a change mid-glide continues from the screen',
      (WidgetTester tester) async {
    final ValueNotifier<List<double>> values =
        ValueNotifier<List<double>>(<double>[0, 0]);
    List<double> shown = <double>[0, 0];

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<double>>(
          valueListenable: values,
          builder: (BuildContext context, List<double> v, Widget? child) {
            return GlideList(
              values: v,
              builder: (BuildContext context, List<double> s) {
                shown = s;
                return const SizedBox(width: 100, height: 20);
              },
            );
          },
        ),
      ),
    );
    expect(shown, <double>[0, 0]);

    // A preset jump: it glides, so halfway through the line is halfway.
    values.value = <double>[6, 6];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown[0], greaterThan(0));
    expect(shown[0], lessThan(6));

    // A second pick arrives before the first has settled. The new glide must
    // start where the line is now — no flicker back to the pre-jump shape.
    final double midway = shown[0];
    values.value = <double>[6.5, 6.5];
    await tester.pump();
    expect(shown[0], closeTo(midway, 0.001));
    await tester.pumpAndSettle();
    expect(shown[0], closeTo(6.5, 0.001));

    // A drag increment is not a jump: it lands at once, and the glide that
    // was running does not drag it anywhere.
    values.value = <double>[6.6, 6.6];
    await tester.pump();
    expect(shown[0], closeTo(6.6, 0.001));

    // A caretaking change under the threshold in one slot only still lands
    // both slots where they belong.
    values.value = <double>[6.7, 6.0];
    await tester.pump();
    expect(shown[0], closeTo(6.7, 0.001));
    expect(shown[1], closeTo(6.0, 0.001));

    values.dispose();
  });
}
