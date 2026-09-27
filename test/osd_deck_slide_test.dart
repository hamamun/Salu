import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/ui/osc/controller_panel.dart' show kChromeBlockHeight;
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
///
/// The card's y is read off the GlassCapsule itself (its position in
/// the test surface): the chrome block's bottom edge
/// ([kChromeBlockHeight]) + the deck layer's 8 px rest + the live
/// slide lift (−10 at the enter's start, 0 at rest, −6 at the exit's
/// end).
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

      // 1st hit — the card enters at the top of its slide (rest − 10)…
      osd.show(const OsdTransportCard(mark: OsdMark.play));
      await tester.pump();
      expect(slideY(tester), closeTo(kChromeBlockHeight - 2.0, 0.001));

      // …and settles at its rest (block + 8) by the end of the 160 ms
      // enter.
      await tester.pump(const Duration(milliseconds: 160));
      expect(slideY(tester), closeTo(kChromeBlockHeight + 8.0, 0.001));

      // 2nd hit while the card is live — the replacement must NOT move.
      osd.show(const OsdTransportCard(mark: OsdMark.pause));
      await tester.pump();
      expect(slideY(tester), closeTo(kChromeBlockHeight + 8.0, 0.001));

      // 3rd hit — it keeps showing at the resting position.
      osd.show(const OsdTransportCard(mark: OsdMark.next));
      await tester.pump();
      expect(slideY(tester), closeTo(kChromeBlockHeight + 8.0, 0.001));
      await tester.pump(const Duration(milliseconds: 100));

      // TTL — the card is mid-exit here: the 1000 ms TTL fired 100 ms
      // into the 120 ms reverse, so the card has left its rest
      // (block + 8) and is near the exit lift's end (block + 2), but
      // not gone. (Measuring any later is too late — once the reverse
      // completes, the deck builds nothing at all.)
      await tester.pump(const Duration(milliseconds: 1000));
      final double exitingY = slideY(tester);
      expect(exitingY, lessThan(kChromeBlockHeight + 8.0));
      expect(exitingY, greaterThan(kChromeBlockHeight + 2.0));

      // …and is gone once the 120 ms exit completes.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(GlassCapsule), findsNothing);
    },
  );
}

/// The card's y in the test surface. The AnimatedSwitcher may hold two
/// capsules mid-cross-fade — `.last` is the card just shown (and both
/// ride the same transform anyway).
double slideY(WidgetTester tester) =>
    tester.getTopLeft(find.byType(GlassCapsule).last).dy;
