import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/core/web/web_popup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pop-up policy (web.md · pop-ups lock, 2026-09-17 cut): a
/// Block-by-default global, per-site rules that override it either way,
/// and visit-only memories that never touch disk.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final WebPopupService svc = WebPopupService.instance;
  final SettingsService settings = SettingsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    for (final WebPopupException e in List.of(svc.exceptions.value)) {
      svc.removeFor(e.host);
    }
    svc.endSession();
    settings.webPopupDefault.value = WebPopupDefault.block;
  });

  test('keyFor normalizes URLs and bare hosts', () {
    expect(WebPopupService.keyFor('https://WWW.Example.com/watch?v=1'),
        'example.com');
    expect(WebPopupService.keyFor('http://sub.test:8080/x'), 'sub.test');
    expect(WebPopupService.keyFor('Example.COM'), 'example.com');
    expect(WebPopupService.keyFor('www.test'), 'test');
    expect(WebPopupService.keyFor('not a host'), isEmpty);
    expect(WebPopupService.keyFor('a/b'), isEmpty);
    expect(WebPopupService.keyFor(''), isEmpty);
    expect(WebPopupService.keyFor(null), isEmpty);
  });

  group('resolve', () {
    test('no rules → the global default', () {
      expect(svc.resolve('https://a.test/'), isFalse);
      settings.webPopupDefault.value = WebPopupDefault.allow;
      expect(svc.resolve('https://a.test/'), isTrue);
    });

    test('a site rule beats the default, both ways', () {
      svc.setFor('https://a.test/page', true);
      expect(svc.resolve('https://a.test/other'), isTrue);
      settings.webPopupDefault.value = WebPopupDefault.allow;
      svc.setFor('https://b.test/', false);
      expect(svc.resolve('https://b.test/x'), isFalse);
      expect(svc.resolve('https://c.test/'), isTrue);
    });

    test('the rule survives www and case differences', () {
      svc.setFor('https://www.a.test/', true);
      expect(svc.resolve('https://A.TEST/x'), isTrue);
      expect(svc.findFor('https://a.test/')?.allow, isTrue);
    });

    test('visit memory beats the site rule, then evaporates', () {
      svc.setFor('https://a.test/', false);
      svc.allowVisit('https://a.test/');
      expect(svc.resolve('https://a.test/'), isTrue);
      svc.endSession();
      expect(svc.resolve('https://a.test/'), isFalse);
    });

    test('a permanent rule clears the visit memory', () {
      svc.blockVisit('https://a.test/');
      svc.setFor('https://a.test/', true);
      expect(svc.resolve('https://a.test/'), isTrue);
    });

    test('unknown pages follow the default', () {
      expect(svc.resolve(null), isFalse);
      expect(svc.resolve('garbage'), isFalse);
    });
  });

  test('removeFor hands the site back to the default', () {
    svc.setFor('https://a.test/', true);
    expect(svc.resolve('https://a.test/'), isTrue);
    svc.removeFor('https://a.test/');
    expect(svc.resolve('https://a.test/'), isFalse);
    expect(svc.exceptions.value, isEmpty);
  });

  test('rules persist instantly', () async {
    svc.setFor('https://p.test/', true);
    await svc.flush();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('web_popup_exceptions'), contains('p.test'));
  });

  test('corrupt prefs load as no rules', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'web_popup_exceptions': '[[['});
    await svc.load();
    expect(svc.exceptions.value, isEmpty);
  });
}
