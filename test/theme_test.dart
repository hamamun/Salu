import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/theme/themed_app.dart';
import 'package:salu/ui/osd/osd_controller.dart';
import 'package:salu/ui/widgets/eq_curve_painter.dart';
import 'package:salu/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ColoredBox(
          key: const ValueKey<String>('palette'),
          color: context.palette.surface,
          child: Text(Theme.of(context).brightness.name),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();
  final SettingsService settings = SettingsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.load();
  });

  test('missing or unknown preferences preserve Default', () async {
    expect(settings.themeMode.value, SaluThemeMode.defaultTheme);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'appearance_theme_mode': 'unknown',
    });
    await settings.load();
    expect(settings.themeMode.value, SaluThemeMode.defaultTheme);
  });

  test('every selection applies immediately and survives reload', () async {
    for (final SaluThemeMode mode in SaluThemeMode.values) {
      final Future<void> saved = settings.setThemeMode(mode);
      expect(settings.themeMode.value, mode);
      await saved;
      expect(
        (await SharedPreferences.getInstance())
            .getString('appearance_theme_mode'),
        mode.name,
      );
      settings.themeMode.value = SaluThemeMode.defaultTheme;
      await settings.load();
      expect(settings.themeMode.value, mode);
    }
  });

  test('SALU appearance does not change browser page colours', () async {
    final WebPageScheme pageScheme = settings.webPageScheme.value;
    await settings.setThemeMode(SaluThemeMode.light);
    expect(settings.webPageScheme.value, pageScheme);
  });

  testWidgets('saved Light is present on the first rendered frame',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'appearance_theme_mode': 'light',
    });
    await settings.load();
    await tester.pumpWidget(const SaluThemedApp(home: _Probe()));
    expect(find.text('light'), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey<String>('palette')))
          .color,
      AppPalette.light.surface,
    );
  });

  testWidgets('System follows live brightness; explicit modes ignore it',
      (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(const SaluThemedApp(home: _Probe()));
    expect(find.text('dark'), findsOneWidget); // Default, not System.

    await settings.setThemeMode(SaluThemeMode.system);
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);

    await settings.setThemeMode(SaluThemeMode.light);
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('Appearance choices, group reset and master Undo',
      (tester) async {
    addTearDown(OsdController.instance.dismiss);
    await tester.pumpWidget(const SaluThemedApp(
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: 700,
        height: 700,
        child: SettingsDialog(initialTab: SettingsTab.appearance),
      ))),
    ));
    await tester.pumpAndSettle();
    for (final String label in <String>['Default', 'Light', 'System']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(settings.themeMode.value, SaluThemeMode.light);
    await tester.tap(find.byTooltip('Reset Theme to defaults'));
    await tester.pumpAndSettle();
    expect(settings.themeMode.value, SaluThemeMode.defaultTheme);
    final OsdUndoCard groupUndo =
        OsdController.instance.current.value! as OsdUndoCard;
    groupUndo.onUndo();
    await tester.pumpAndSettle();
    expect(settings.themeMode.value, SaluThemeMode.light);
    await tester.tap(find.byTooltip('Reset all settings'));
    await tester.pumpAndSettle();
    expect(settings.themeMode.value, SaluThemeMode.defaultTheme);
    final OsdUndoCard masterUndo =
        OsdController.instance.current.value! as OsdUndoCard;
    masterUndo.onUndo();
    await tester.pumpAndSettle();
    expect(settings.themeMode.value, SaluThemeMode.light);
    OsdController.instance.dismiss();
  });

  test('custom painter repaints on palette change', () {
    const EqCurvePainter dark = EqCurvePainter(gains: <double>[]);
    const EqCurvePainter light = EqCurvePainter(
      gains: <double>[],
      palette: AppPalette.light,
    );
    expect(light.shouldRepaint(dark), isTrue);
  });

  test('light surfaces and text contrast; media backdrop stays dark', () {
    expect(AppPalette.saluDefault.background, AppColors.background);
    expect(AppPalette.saluDefault.glass, AppColors.glass);
    expect(AppPalette.light.background.computeLuminance(), greaterThan(0.8));
    final double contrast =
        (AppPalette.light.surface.computeLuminance() + 0.05) /
            (AppPalette.light.textSecondary.computeLuminance() + 0.05);
    expect(contrast, greaterThan(4.5));
    expect(AppPalette.light.videoBackdrop, AppColors.videoBackdrop);
  });
}
