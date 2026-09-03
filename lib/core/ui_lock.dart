import 'package:flutter/foundation.dart';

/// A tiny reference-counted lock that keeps the top chrome awake.
///
/// While any transient UI (the open pill, the Open-URL modal, future
/// popups) is showing, it acquires the lock; HomeScreen's auto-hide timer
/// refuses to hide the chrome while the count is above zero, and restarts
/// its countdown when the last lock is released.
class ChromeLock {
  ChromeLock._();

  static final ChromeLock instance = ChromeLock._();

  final ValueNotifier<int> _locks = ValueNotifier<int>(0);

  bool get isLocked => _locks.value > 0;

  /// Notifies whenever the lock count changes (acquire or release).
  Listenable get listenable => _locks;

  void acquire() => _locks.value = _locks.value + 1;

  void release() {
    if (_locks.value > 0) _locks.value = _locks.value - 1;
  }
}
