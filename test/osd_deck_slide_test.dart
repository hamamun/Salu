import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderTransform;
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/ui/osd/osd_controller.dart';
import 'package:salu/ui/osd/osd_deck.dart';
import 'package:salu/ui/widgets/glass_capsule.dart';

/// Regression test for the "toast jumps down on the second hit" bug
/// (owner report 2026-09-27).
///
/// The deck's slide offset used to be baked into a bare
/// `Transform.translate` in `build()`, and nothing rebuilt the deck on
/// animation ticks (only `FadeTransition` listens to the controller).
/// So a fresh show froze at the pre-tick value — 10 px too high, the
/// enter slide never ran — and the next hit, built with the slot
/// already at 1.0, jumped the card down those 10 px. Volume and seek
/// cards share the deck, so both jumped.
void main() {
  testWidgets(
    'the deck slides in once and never jumps on repeat hits',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Stack(children: <Widget>[OsdDeck()]),
      ));
      final OsdController osd = OsdController.instance;

      // A fresh deck renders nothing.
      expect(find.byType(GlassCapsule), findsNothing);

      // 1st hit — the card enters at the top of its slide (8 − 10)…
      osd.show(const OsdTransportCard(mark: OsdMark.play));
      await tester.pump();
      expect(slideY(tester), closeTo(-2.0, 0.001));

      // …and settles at its rest (y = 8) by the end of the 160 ms enter.
      await tester.pump(const Duration(milliseconds: 160));
      expect(slideY(tester), closeTo(8.0, 0.001));

      // 2nd hit while the card is live — the replacement must NOT move.
      osd.show(const OsdTransportCard(mark: OsdMark.pause));
      await tester.pump();
      expect(slideY(tester), closeTo(8.0, 0.001));

      // 3rd hit — it keeps showing at the resting position.
      osd.show(const OsdTransportCard(mark: OsdMark.next));
      await tester.pump();
      expect(slideY(tester), closeTo(8.0, 0.001));
      await tester.pump(const Duration(milliseconds: 100));

      // TTL — the card exits, rising somewhere between its rest and
      // the 6 px exit lift…
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 60));
      final double exitingY = slideY(tester);
      expect(exitingY, lessThan(8.0));
      expect(exitingY, greaterThan(2.0));

      // …and is gone once the 120 ms exit completes.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(GlassCapsule), findsNothing);
    },
  );
}

/// The deck's slide offset, read back from the rendered transform
/// (`Transform.translate` bakes it into the matrix translation — which
/// only changes now that the transform ticks with the animation).
double slideY(WidgetTester tester) {
  // The deck's own Transform is the only one in this test tree.
  final RenderTransform render =
      tester.renderObject<RenderTransform>(find.byType(Transform));
  return render.transform.getTranslation().y;
}
