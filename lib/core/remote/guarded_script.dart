import 'dart:async';

import '../browser_service.dart';

/// One outstanding browser script at a time (pc_part.md Part F4).
///
/// A Dart timeout does not cancel the underlying WebView call and does not
/// clear this guard. The next script is submitted only after the original
/// operation settles, so a stalled controller is not piled with retries.
class GuardedBrowserScript {
  GuardedBrowserScript({Future<Object?> Function(String script)? execute})
      : _execute = execute;

  static final GuardedBrowserScript instance = GuardedBrowserScript();

  final Future<Object?> Function(String script)? _execute;
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Scripts whose underlying operation has not settled, including one
  /// whose caller already timed out.
  int get pending => _pending;

  bool get busy => _pending > 0;

  Future<Object?> run(
    String script, {
    Duration? timeout,
    int? generation,
    int Function()? generationOf,
  }) {
    final Completer<Object?> done = Completer<Object?>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      _pending++;
      try {
        final int? captured = generation ?? generationOf?.call();
        final Future<Object?> Function(String script) exec =
            _execute ?? BrowserService.instance.remoteExecuteScript;
        final Future<Object?> operation = exec(script);
        if (timeout == null) {
          _complete(done, await _read(operation), captured, generationOf);
          return;
        }
        try {
          _complete(
            done,
            await operation.timeout(timeout),
            captured,
            generationOf,
          );
        } on TimeoutException {
          // Release the caller. The WebView call is still running, and this
          // guard stays held until it settles so nothing else is submitted.
          if (!done.isCompleted) done.complete(null);
          try {
            await operation;
          } catch (_) {}
        }
      } catch (_) {
        if (!done.isCompleted) done.complete(null);
      } finally {
        _pending--;
      }
    });
    return done.future;
  }
}

Future<Object?> _read(Future<Object?> operation) async {
  try {
    return await operation;
  } catch (_) {
    return null;
  }
}

void _complete(
  Completer<Object?> done,
  Object? value,
  int? captured,
  int Function()? generationOf,
) {
  if (done.isCompleted) return;
  final bool stale = captured != null &&
      generationOf != null &&
      generationOf() != captured;
  done.complete(stale ? null : value);
}
