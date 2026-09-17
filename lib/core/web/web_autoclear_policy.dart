import '../settings_service.dart';

/// The auto-clear schedule (web.md · "Auto-clear — LOCKED": off by default,
/// every 7 / 15 / 30 days, at player open / player close / both).
///
/// Pure policy — no prefs, no files — so the due-date arithmetic and the
/// timing gate are unit-testable (`test/web_autoclear_test.dart`).
class WebAutoClearPolicy {
  WebAutoClearPolicy._();

  /// Which moment the clear runs at (the Settings choice, and the app's
  /// two lifecycle events, spelled with the same two words).
  static bool firesAt(
    WebAutoClearTiming timing,
    WebAutoClearTrigger trigger,
  ) {
    if (timing == WebAutoClearTiming.both) return true;
    if (timing == WebAutoClearTiming.onOpen) {
      return trigger == WebAutoClearTrigger.open;
    }
    return trigger == WebAutoClearTrigger.close;
  }

  /// Whether the interval has elapsed. A store that has never been cleared
  /// is due immediately — the data has simply existed since install.
  static bool isDue({
    required WebAutoClearInterval interval,
    required DateTime now,
    DateTime? lastRun,
  }) {
    if (interval == WebAutoClearInterval.off) return false;
    if (lastRun == null) return true;
    return now.difference(lastRun) >= Duration(days: interval.days);
  }
}
