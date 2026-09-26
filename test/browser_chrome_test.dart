import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_suggestions.dart';
import 'package:salu/core/web/web_tab.dart';
import 'package:salu/ui/widgets/browser_address_bar.dart';
import 'package:salu/ui/widgets/browser_tab_strip.dart';
import 'package:salu/ui/widgets/salu_marks.dart';

void main() {
  testWidgets('all ten tabs and new-tab control fit after resizing',
      (WidgetTester tester) async {
    final List<WebTab> tabs = List<WebTab>.generate(
      10,
      (int i) => WebTab(initialTitle: 'Page $i'),
    );
    addTearDown(() async {
      for (final WebTab tab in tabs) {
        await tab.destroy();
      }
    });
    int? selected;
    int? closed;

    Future<void> showStrip(double width) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: BrowserTabStrip(
                tabs: tabs,
                activeIndex: 0,
                onSelect: (int i) => selected = i,
                onClose: (int i) => closed = i,
                onNewTab: () {},
                maxTabs: 10,
                hub: const SizedBox(width: 26),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await showStrip(780);
    final double wideGap = tester.getTopLeft(find.text('Page 1')).dx -
        tester.getTopLeft(find.text('Page 0')).dx;
    await showStrip(500);
    final double narrowGap = tester.getTopLeft(find.text('Page 1')).dx -
        tester.getTopLeft(find.text('Page 0')).dx;
    expect(narrowGap, lessThan(wideGap));
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.getTopRight(find.byType(PlusMark)).dx, lessThan(500));
    await tester.tap(find.text('Page 9'));
    expect(selected, 9);
    await tester.tap(find.byType(CloseMark).last);
    expect(closed, 9);
  });

  testWidgets('search suggestions use a magnifier and pick on one click',
      (WidgetTester tester) async {
    const WebSuggestion suggestion = WebSuggestion(
      kind: WebSuggestionKind.search,
      text: 'Yahoo',
      url: 'https://www.google.com/search?q=Yahoo',
    );
    WebSuggestion? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebSuggestionMenu(
          items: const <WebSuggestion>[suggestion],
          cursorIndex: 0,
          onPick: (WebSuggestion item) => picked = item,
          onHover: (_) {},
        ),
      ),
    ));
    expect(find.text('?'), findsNothing);
    expect(find.byType(MagnifierMark), findsOneWidget);
    await tester.tap(find.text('Yahoo'));
    expect(picked, same(suggestion));
  });

  testWidgets('mouse selection survives the address field losing focus',
      (WidgetTester tester) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    int picks = 0;
    const WebSuggestion suggestion = WebSuggestion(
      kind: WebSuggestionKind.search,
      text: 'Yahoo',
      url: 'https://www.google.com/search?q=Yahoo',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextField(focusNode: focus),
            ListenableBuilder(
              listenable: focus,
              builder: (BuildContext context, Widget? child) {
                if (!focus.hasFocus) return const SizedBox.shrink();
                return WebSuggestionMenu(
                  items: const <WebSuggestion>[suggestion],
                  cursorIndex: -1,
                  onPick: (_) => picks++,
                  onHover: (_) {},
                );
              },
            ),
          ],
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.down(tester.getCenter(find.text('Yahoo')));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await mouse.up();
    await tester.pump();
    expect(picks, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
