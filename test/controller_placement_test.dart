import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
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
}
