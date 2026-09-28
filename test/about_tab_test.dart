import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/browser_service.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → About (phase_9_details.md · step 2) — the window's second
/// reference page, right of Shortcuts. The engine facts are live reads;
/// in this harness the notifier-only player has no engine, so `mpv` reads
/// `unknown` and `Decoder` reads `—` — exactly the fallbacks the page
/// promises when the engine has nothing to say.
Future<void> pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 700,
            child: SettingsDialog(initialTab: SettingsTab.about),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The gist lines are `Text.rich`, so they are matched on the rendered
/// plain text rather than on `Text.data`.
Finder gistContaining(String needle) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is RichText && widget.text.toPlainText().contains(needle),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  PlayerService.installNotifierOnlyForTesting();

  testWidgets('About sits right of Shortcuts and owns the body',
      (WidgetTester tester) async {
    await pumpAbout(tester);

    // The tab exists, and the dialog opened on it.
    expect(find.text('About'), findsOneWidget);
    expect(
      tester.widget<SettingsDialog>(find.byType(SettingsDialog)).initialTab,
      SettingsTab.about,
    );

    // Right of Shortcuts, not left of it.
    final double shortcutsX = tester.getTopLeft(find.text('Shortcuts')).dx;
    final double aboutX = tester.getTopLeft(find.text('About')).dx;
    expect(aboutX, greaterThan(shortcutsX));

    // Tapping Shortcuts leaves About; tapping About comes back.
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('THE PLAYER'), findsNothing);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('THE PLAYER'), findsOneWidget);
  });

  testWidgets('the identity block names the app and its version',
      (WidgetTester tester) async {
    await pumpAbout(tester);
    expect(find.text('SALU'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('A borderless media player for Windows.'), findsOneWidget);
    // The app tile, at the compact size the 620 px window asks for.
    final Image tile = tester.widget<Image>(find.byType(Image));
    expect(tile.image, const AssetImage('assets/images/salu_logo.png'));
    expect(tile.width, 44);
    expect(tile.height, 44);
  });

  testWidgets('every section is on the page', (WidgetTester tester) async {
    await pumpAbout(tester);
    for (final String caption in <String>[
      'THE PLAYER',
      'WHAT ONLY SALU DOES',
      'CHANNELS',
      'THE BROWSER',
      'ENGINE',
      'CREDITS',
    ]) {
      expect(find.text(caption), findsOneWidget, reason: caption);
    }
  });

  testWidgets('the gist lines are the agreed copy',
      (WidgetTester tester) async {
    await pumpAbout(tester);

    // The specialty, one line each.
    expect(gistContaining('Stop is not Start Over'), findsOneWidget);
    expect(gistContaining('32 px always-on-top strip'), findsOneWidget);
    expect(gistContaining('thirteen presets for audio'), findsOneWidget);
    expect(gistContaining('paired once by QR'), findsOneWidget);
    expect(gistContaining('shrunken and answering'), findsOneWidget);

    // m3u — the gist, not the details.
    expect(gistContaining("SALU's own incremental parser"), findsOneWidget);
    expect(gistContaining('Fifty thousand channels, no cap'), findsOneWidget);
    expect(gistContaining('never store a URL'), findsOneWidget);

    // The browser's safety line — Windows' own Edge engine.
    expect(gistContaining("Windows' own Edge engine"), findsOneWidget);
    expect(gistContaining('No custom engine'), findsOneWidget);

    // The discarded failure-skip copy is nowhere on the page.
    expect(gistContaining('three in a row'), findsNothing);
    expect(gistContaining('stampeding'), findsNothing);
  });

  testWidgets('the engine rows carry live values with quiet fallbacks',
      (WidgetTester tester) async {
    await pumpAbout(tester);

    // No engine in this harness → the promised fallbacks.
    expect(find.text('mpv'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Windows 10/11'), findsOneWidget);
    expect(find.text('shared_preferences'), findsOneWidget);

    // The decoder row is live: it follows the same notifier Info reads.
    PlayerService.instance.activeHwdec.value = 'd3d11va';
    await tester.pumpAndSettle();
    expect(find.text('d3d11va'), findsOneWidget);

    // Leave the shared notifier as it was found.
    PlayerService.instance.activeHwdec.value = null;
  });

  testWidgets('the credits name the source and nothing else',
      (WidgetTester tester) async {
    await pumpAbout(tester);
    expect(find.text('github.com/hamamun/Salu'), findsOneWidget);
    expect(find.text('mpv · media_kit · Flutter · WebView2'), findsOneWidget);
    // OpenSubtitles is not credited anywhere on the page.
    expect(find.textContaining('OpenSubtitles'), findsNothing);
  });

  testWidgets('the signature is there, faint, and pinned at the bottom',
      (WidgetTester tester) async {
    await pumpAbout(tester);

    final Text signature = tester.widget<Text>(find.text('created by HAM'));
    final Color? color = signature.style?.color;
    expect(color, isNotNull);
    // Barely visible: a fraction of full white, never nothing.
    expect(color!.a, lessThan(0.5));
    expect(color.a, greaterThan(0.0));

    // Centered on the page, like the identity block above it.
    final Rect signatureBox = tester.getRect(find.text('created by HAM'));
    final Rect nameBox = tester.getRect(find.text('SALU'));
    expect(signatureBox.center.dx, moreOrLessEquals(nameBox.center.dx));

    // Pinned under the scroll: the body can be dragged, the signature
    // cannot move. (`.last` is the tab body — the strip's scroller is
    // first in the tree.)
    final double before = signatureBox.top;
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('created by HAM')).top, before);
  });

  testWidgets("the Source row opens the repository in SALU's browser",
      (WidgetTester tester) async {
    await pumpAbout(tester);
    expect(BrowserService.instance.mode.value, SaluMode.player);

    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(BrowserService.instance.mode.value, SaluMode.web);

    // Leave the shared service as it was found.
    BrowserService.instance.mode.value = SaluMode.player;
  });
}
