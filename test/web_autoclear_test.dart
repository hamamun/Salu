import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/settings_service.dart';
import 'package:salu/core/web/web_autoclear_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The auto-clear schedule's two pure halves (web.md · Auto-clear —
/// LOCKED): which moment the timing names, and whether the interval is
/// due. The sweep itself lives in `WebDataControlService` and speaks to
/// prefs and files.

void main() {
  group('firesAt — the timing gate', () {
    test('both fires at either moment', () {
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.both, WebAutoClearTrigger.open), isTrue);
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.both, WebAutoClearTrigger.close), isTrue);
    });
    test('onOpen answers opening only', () {
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.onOpen, WebAutoClearTrigger.open), isTrue);
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.onOpen, WebAutoClearTrigger.close), isFalse);
    });
    test('onClose answers closing only', () {
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.onClose, WebAutoClearTrigger.open), isFalse);
      expect(WebAutoClearPolicy.firesAt(
          WebAutoClearTiming.onClose, WebAutoClearTrigger.close), isTrue);
    });
  });

  group('isDue — the interval', () {
    final DateTime now = DateTime(2026, 9, 17, 12);

    test('Off is never due', () {
      expect(
          WebAutoClearPolicy.isDue(
              interval: WebAutoClearInterval.off,
              now: now,
              lastRun: now.subtract(const Duration(days: 999))),
          isFalse);
    });

    test('a store that was never cleared is due at once', () {
      expect(
          WebAutoClearPolicy.isDue(
              interval: WebAutoClearInterval.days7, now: now),
          isTrue);
    });

    test('within the interval it waits; at the edge it runs', () {
      expect(
          WebAutoClearPolicy.isDue(
              interval: WebAutoClearInterval.days7,
              now: now,
              lastRun: now.subtract(const Duration(days: 6, hours: 23))),
          isFalse);
      expect(
          WebAutoClearPolicy.isDue(
              interval: WebAutoClearInterval.days7,
              now: now,
              lastRun: now.subtract(const Duration(days: 7))),
          isTrue);
      expect(
          WebAutoClearPolicy.isDue(
              interval: WebAutoClearInterval.days30,
              now: now,
              lastRun: now.subtract(const Duration(days: 40))),
          isTrue);
    });

    test('the interval spellings carry their lengths', () {
      expect(WebAutoClearInterval.off.days, 0);
      expect(WebAutoClearInterval.days7.days, 7);
      expect(WebAutoClearInterval.days15.days, 15);
      expect(WebAutoClearInterval.days30.days, 30);
    });
  });

  group('Settings wiring', () {
    test('defaults are the locked ones: suggestions on, auto-clear off',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsService s = SettingsService.instance;
      await s.load();
      expect(s.webSearchSuggestions.value, isTrue);
      expect(s.webAutoClearDays.value, WebAutoClearInterval.off);
      expect(s.webAutoClearTiming.value, WebAutoClearTiming.onOpen);
    });

    test('choices persist across a reload, instantly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsService s = SettingsService.instance;
      await s.setWebSearchSuggestions(false);
      await s.setWebAutoClearDays(WebAutoClearInterval.days15);
      await s.setWebAutoClearTiming(WebAutoClearTiming.both);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('web_search_suggestions'), isFalse);
      expect(prefs.getString('web_auto_clear_interval'), 'days15');
      expect(prefs.getString('web_auto_clear_timing'), 'both');

      // A fresh load() reads the same store back.
      await s.load();
      expect(s.webAutoClearDays.value, WebAutoClearInterval.days15);
    });
  });
}
