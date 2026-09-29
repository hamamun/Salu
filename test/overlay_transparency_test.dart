import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/theme/themed_app.dart';
import 'package:salu/ui/osd/osd_controller.dart';
import 'package:salu/ui/widgets/glass_capsule.dart';
import 'package:salu/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TintProbe extends StatelessWidget {
  const _TintProbe();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Text(
          'foreground',
          style: TextStyle(color: context.palette.textPrimary),
        ),
        GlassCapsule(radius: 10, child: const Text('glass')),
        ColoredBox(
          key: const ValueKey<String>('surface'),
          color: context.overlayTint(context.palette.surface),
          child: const Text('surface'),
        ),
      ],
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

  test(
    'restores before first frame, clamps invalid values, defaults to 0',
    () async {
      expect(settings.overlayTransparency.value, 0);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': 80,
      });
      await settings.load();
      expect(
        settings.overlayTransparency.value,
        SettingsService.maxOverlayTransparency,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': -20,
      });
      await settings.load();
      expect(settings.overlayTransparency.value, 0);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_overlay_transparency': 'bad',
      });
      await settings.load();
      expect(settings.overlayTransparency.value, 0);
    },
  );

  test('drag applies live; release saves and restores', () async {
    await settings.setOverlayTransparency(20, persist: false);
    expect(settings.overlayTransparency.value, 20);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      isNull,
    );
    await settings.setOverlayTransparency(25);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      25,
    );
    settings.overlayTransparency.value = 0;
    await settings.load();
    expect(settings.overlayTransparency.value, 25);
    await settings.setOverlayTransparency(900);
    expect(
      settings.overlayTransparency.value,
      SettingsService.maxOverlayTransparency,
    );
    await settings.setOverlayTransparency(0);
    expect(settings.overlayTransparency.value, 0);
  });

  test('immediate reset then Undo persists the latest value', () async {
    final Future<void> reset = settings.setOverlayTransparency(0);
    final Future<void> undo = settings.setOverlayTransparency(30);
    await Future.wait(<Future<void>>[reset, undo]);
    expect(settings.overlayTransparency.value, 30);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        'appearance_overlay_transparency',
      ),
      30,
    );
  });

  testWidgets('only surface tint changes in both themes, not foreground', (
    tester,
  ) async {
    await tester.pumpWidget(const SaluThemedApp(home: _TintProbe()));
    final before = tester.widget<Container>(
      find
          .ancestor(of: find.text('glass'), matching: find.byType(Container))
          .first,
    );
    expect(before.decoration, isA<BoxDecoration>());
    expect(
      (before.decoration! as BoxDecoration).color,
      AppPalette.saluDefault.glass,
    );
    await settings.setOverlayTransparency(40);
    await tester.pumpAndSettle();
    final after = tester.widget<Container>(
      find
          .ancestor(of: find.text('glass'), matching: find.byType(Container))
          .first,
    );
    expect(
      (after.decoration! as BoxDecoration).color!.a,
      closeTo(AppPalette.saluDefault.glass.a * 0.6, 0.005),
    );
    expect(
      tester.widget<Text>(find.text('foreground')).style!.color,
      AppPalette.saluDefault.textPrimary,
    );
    expect(
      Theme.of(tester.element(find.text('foreground'))).scaffoldBackgroundColor,
      AppPalette.saluDefault.background,
    );
    await settings.setThemeMode(SaluThemeMode.light);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('foreground')).style!.color,
      AppPalette.light.textPrimary,
    );
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey<String>('surface')))
          .color
          .a,
      closeTo(0.6, 0.005),
    );
  });

  testWidgets('Appearance control, group reset/Undo and master reset', (
    tester,
  ) async {
    addTearDown(OsdController.instance.dismiss);
    await tester.pumpWidget(
      const SaluThemedApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              height: 700,
              child: SettingsDialog(initialTab: SettingsTab.appearance),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.byTooltip('0% original · higher is more see-through'),
      findsOneWidget,
    );
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(65, 0));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, greaterThan(0));
    expect(find.text('${settings.overlayTransparency.value}%'), findsOneWidget);
    final previous = settings.overlayTransparency.value;
    await tester.tap(find.byTooltip('Reset Overlay transparency to defaults'));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, 0);
    (OsdController.instance.current.value! as OsdUndoCard).onUndo();
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, previous);
    await tester.tap(find.byTooltip('Reset all settings'));
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, 0);
    (OsdController.instance.current.value! as OsdUndoCard).onUndo();
    await tester.pumpAndSettle();
    expect(settings.overlayTransparency.value, previous);
  });
}
