/// Socket-close diagnostics for pairing with the phone's connection
/// history (pc_part.md Part F4). No URLs, tokens, pairing codes or paths.
///
/// Close code 1001 by itself does not prove Wi-Fi loss or heartbeat
/// expiry — the ages and the event-loop lag are what distinguish a stall
/// from a real disconnect.
String formatRemoteCloseLine({
  required int code,
  required String reason,
  required DateTime at,
  required DateTime openedAt,
  required bool authenticated,
  DateTime? lastFrameAt,
  DateTime? lastSnapshotAt,
  DateTime? lastHeartbeatAt,
  Duration eventLoopLag = Duration.zero,
  int pendingBrowser = 0,
  int lastCommandMs = 0,
}) {
  int age(DateTime? then) =>
      then == null ? -1 : at.difference(then).inMilliseconds;
  return '[SALU] remote: socket closed'
      ' code=$code'
      ' reason=${safeCloseReason(reason)}'
      ' at=${at.toIso8601String()}'
      ' authed=$authenticated'
      ' ageMs=${at.difference(openedAt).inMilliseconds}'
      ' frameAgeMs=${age(lastFrameAt)}'
      ' snapshotAgeMs=${age(lastSnapshotAt)}'
      ' heartbeatAgeMs=${age(lastHeartbeatAt)}'
      ' eventLoopLagMs=${eventLoopLag.inMilliseconds}'
      ' pendingBrowser=$pendingBrowser'
      ' lastCommandMs=$lastCommandMs';
}

const Set<String> _allowedCloseReasons = <String>{
  '',
  'Remote is switched off.',
  'Device forgotten.',
  'Protocol mismatch.',
  'Message too large.',
  'Authentication timed out.',
  'Authenticate before sending commands.',
  'This phone is no longer paired.',
  'That pairing code is not valid.',
  'message exceeds 8 KB',
  'message is not valid JSON',
  'message must be a JSON object',
  'socket error',
};

/// Close reason safe to put on the socket as well as in the log. An empty
/// reason stays empty; a known local reason passes through; anything that
/// could carry a URL, token, pairing code or path is replaced.
String wireCloseReason(String reason) {
  if (reason.isEmpty) return '';
  final String safe = safeCloseReason(reason);
  return safe == 'none' ? '' : safe;
}

/// Known local reasons pass through. Anything that could carry a URL,
/// token, pairing code or path is replaced.
String safeCloseReason(String reason) {
  if (_allowedCloseReasons.contains(reason)) {
    return reason.isEmpty ? 'none' : reason;
  }
  if (reason.contains('://') ||
      reason.contains('\\\\') ||
      reason.contains('/') ||
      reason.length > 80) {
    return 'redacted';
  }
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(reason)) return reason;
  return 'redacted';
}
