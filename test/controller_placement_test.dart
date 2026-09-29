import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/theme/app_theme.dart';
import 'package:salu/ui/osc/open_media_control.dart';
import 'package:salu/ui/widgets/glass_capsule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final SettingsService settings = SettingsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.load();
  });

  test('placement defaults migration-safely and persists every choice', () async {
    expect(settings.controllerPlacement.value, ControllerPlacement.defaultPosition);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance_controller_placement'), isNull);

    for (final ControllerPlacement placement in ControllerPlacement.values) {
      await settings.setControllerPlacement(placement);
      expect(settings.controllerPlacement.value, placement);
      expect(prefs.getString('appearance_controller_placement'), placement.name);
    }
  });

  test('unknown stored placement falls back to Default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'appearance_controller_placement': 'some-future-value',
    });
    await settings.load();
    expect(settings.controllerPlacement.value, ControllerPlacement.defaultPosition);
  });

  testWidgets('open media pill opens below for top/default and above for bottom placements', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: OpenMediaControl())),
      ),
    );

    final Rect plusRect = tester.getRect(find.byType(OpenMediaControl));

    for (final ControllerPlacement placement in <ControllerPlacement>[
      ControllerPlacement.defaultPosition,
      ControllerPlacement.top,
    ]) {
      await settings.setControllerPlacement(placement);
      await tester.tap(find.byType(OpenMediaControl));
      await tester.pumpAndSettle();

      final Rect pillRect = tester.getRect(find.byType(GlassCapsule));
      expect(pillRect.top, closeTo(plusRect.bottom + 6, 0.5));

      await tester.tap(find.byType(OpenMediaControl));
      await tester.pump(const Duration(milliseconds: 200));
    }

    for (final ControllerPlacement placement in <ControllerPlacement>[
      ControllerPlacement.bottom,
      ControllerPlacement.bottomEdge,
    ]) {
      await settings.setControllerPlacement(placement);
      await tester.tap(find.byType(OpenMediaControl));
      await tester.pumpAndSettle();

      final Rect pillRect = tester.getRect(find.byType(GlassCapsule));
      expect(pillRect.bottom, closeTo(plusRect.top - 6, 0.5));

      await tester.tap(find.byType(OpenMediaControl));
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
