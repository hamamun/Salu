import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/player_service.dart';

/// Unified global visibility state for the SALU chrome (title bar + OSC).
///
/// Phase 3 · Step 1. Moving the mouse anywhere over the window reveals the
/// chrome; after [autoHideDelay] of stillness it fades back out. Interactive
/// surfaces (OSC, panels, menus) call [lockInteraction] so the chrome never
/// disappears from underneath the user's pointer.
class UiVisibilityManager extends ChangeNotifier {
  UiVisibilityManager._();

  static final UiVisibilityManager instance = UiVisibilityManager._();

  static const Duration autoHideDelay = Duration(seconds: 3);

  bool _visible = true;
  int _locks = 0;
  Timer? _timer;

  /// Whether the title bar + OSC are currently shown.
  bool get visible => _visible;

  /// True while something is actively holding the chrome open.
  bool get interactionLocked => _locks > 0;

  /// Called on any mouse movement / activity over the window.
  void wake() {
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
    _restartTimer();
  }

  /// Hold the chrome open (OSC hover, panel open, drag in progress…).
  void lockInteraction() {
    _locks++;
    _timer?.cancel();
    if (!_visible) {
      _visible = true;
      notifyListeners();
    }
  }

  void unlockInteraction() {
    if (_locks > 0) _locks--;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(autoHideDelay, () {
      if (_locks > 0) return;
      // Keep the chrome up while nothing is playing — there is no video to
      // obstruct, and the user still needs the window controls.
      if (PlayerService.instance.hasMedia.value) {
        _visible = false;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
