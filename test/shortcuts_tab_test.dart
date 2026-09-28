import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/shortcuts/shortcut_registry.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/widgets/alt_peek.dart';
import 'package:salu/ui/widgets/shortcuts_tab.dart';

Future<ShortcutsTabState> pumpTab(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: SizedBox(width: 640, height: 450, child: ShortcutsTab()),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.state<ShortcutsTabState>(find.byType(ShortcutsTab));
}

Future<void> chord(WidgetTester tester, LogicalKeyboardKey key,
    {LogicalKeyboardKey? modifier}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('the Living Map answers its keys (§4.1 slice B)',
      (WidgetTester tester) async {
    final ShortcutsTabState map = await pumpTab(tester);
    expect(map.mode, ShortcutScope.player);

    expect(map.playing, isTrue);
    await chord(tester, LogicalKeyboardKey.space);
    expect(map.playing, isFalse);
    expect(map.selected?.id, 'player.playPause');

    await chord(tester, LogicalKeyboardKey.keyL,
        modifier: LogicalKeyboardKey.controlLeft);
    expect(map.playlistOpen, isTrue);

    await chord(tester, LogicalKeyboardKey.keyG,
        modifier: LogicalKeyboardKey.controlLeft);
    expect(map.selected?.id, 'player.groupBy');

    await chord(tester, LogicalKeyboardKey.keyF);
    expect(map.fullscreen, isTrue);

    // Esc walks the app's own order: panel → fullscreen.
    await chord(tester, LogicalKeyboardKey.escape);
    expect(map.playlistOpen, isFalse);
    expect(map.fullscreen, isTrue);
    await chord(tester, LogicalKeyboardKey.escape);
    expect(map.fullscreen, isFalse);

    // Ctrl+M drops to the mini bar; Esc brings the player back.
    await chord(tester, LogicalKeyboardKey.keyM,
        modifier: LogicalKeyboardKey.controlLeft);
    expect(map.mode, ShortcutScope.mini);
    await chord(tester, LogicalKeyboardKey.escape);
    expect(map.mode, ShortcutScope.player);

    // Alt+W flips Player ⇄ Web.
    await chord(tester, LogicalKeyboardKey.keyW,
        modifier: LogicalKeyboardKey.altLeft);
    expect(map.mode, ShortcutScope.web);
    await chord(tester, LogicalKeyboardKey.keyT,
        modifier: LogicalKeyboardKey.controlLeft);
    expect(map.webTabs, 4);

    // Let the mock deck's card timer run out.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the mode pill switches the miniature',
      (WidgetTester tester) async {
    final ShortcutsTabState map = await pumpTab(tester);
    await tester.tap(find.text('Dialogs').first);
    await tester.pump();
    expect(map.mode, ShortcutScope.dialog);
    await tester.tap(find.text('Mini').first);
    await tester.pump();
    expect(map.mode, ShortcutScope.mini);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the key tooltip shows only while armed AND hovered',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: AltPeekAnchor(
              anchor: ShortcutAnchor.playPause,
              child: SizedBox(width: 36, height: 36),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Space'), findsNothing);

    // Hover, but the peek is not armed — nothing shows.
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AltPeekAnchor)));
    await tester.pump();
    expect(find.text('Space'), findsNothing);

    // Arm the peek — the key appears as a tooltip over the hovered mark.
    AltPeek.instance.debugSetVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('Space'), findsOneWidget);

    // Disarm — the tooltip leaves.
    AltPeek.instance.debugSetVisible(false);
    await tester.pumpAndSettle();
    expect(find.text('Space'), findsNothing);

    // Armed again, but the mouse is gone — still nothing.
    await mouse.moveTo(const Offset(-500, -500));
    await tester.pump();
    AltPeek.instance.debugSetVisible(true);
    await tester.pumpAndSettle();
    expect(find.text('Space'), findsNothing);
    AltPeek.instance.debugSetVisible(false);
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });
}
