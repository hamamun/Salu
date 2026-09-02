import 'package:flutter/foundation.dart';

/// Hardware decoding modes exposed to the user (Phase 5 · Step 4).
///
/// IINA doesn't silently fall back — it lets power users choose. SALU maps
/// the choice straight onto mpv's `hwdec` property.
enum HwdecMode {
  auto('auto', 'Auto (GPU)', 'Let mpv pick the best GPU decoder'),
  disabled('no', 'Disabled (CPU)', 'Force software decoding on the CPU');

  const HwdecMode(this.mpvValue, this.label, this.description);

  /// The literal value handed to mpv's `hwdec` property.
  final String mpvValue;
  final String label;
  final String description;

  /// Key persisted in preferences ('auto' / 'disabled').
  String get prefKey => this == HwdecMode.auto ? 'auto' : 'disabled';

  static HwdecMode fromPref(String value) =>
      value == 'disabled' ? HwdecMode.disabled : HwdecMode.auto;
}

/// Applies the user's `hwdec` preference to the live mpv instance.
class HwdecManager {
  HwdecManager._();

  /// Pushes [mode] into mpv via the supplied property setter and reports the
  /// decoder that ends up active.
  static Future<void> apply(
    HwdecMode mode,
    Future<void> Function(String name, String value) setProperty,
  ) async {
    await setProperty('hwdec', mode.mpvValue);
    debugPrint('[SALU] hwdec preference applied: ${mode.mpvValue}');
  }
}
