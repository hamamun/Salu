import 'dart:async';

/// The browser owns its tabs and their WebView controllers. This bridge is
/// only the narrow read/write seam needed by the remote server; it never
/// mirrors tab contents or creates a second navigation implementation.
class RemoteBrowserBridge {
  RemoteBrowserBridge._();
  static final RemoteBrowserBridge instance = RemoteBrowserBridge._();

  Future<void> Function(String action)? _navigate;
  Future<Object?> Function(String script)? _executeScript;

  void register({
    required Future<void> Function(String action) navigate,
    required Future<Object?> Function(String script) executeScript,
  }) {
    _navigate = navigate;
    _executeScript = executeScript;
  }

  void clear() {
    _navigate = null;
    _executeScript = null;
  }

  bool get active => _navigate != null;

  Future<bool> navigate(String action) async {
    final Future<void> Function(String)? handler = _navigate;
    if (handler == null) return false;
    if (!<String>{'back', 'forward', 'reload', 'stop', 'home'}.contains(action)) {
      return false;
    }
    try {
      await handler(action);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Object?> executeScript(String script) async {
    final Future<Object?> Function(String)? handler = _executeScript;
    if (handler == null) return null;
    return handler(script);
  }
}
