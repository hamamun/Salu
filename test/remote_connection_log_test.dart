import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_connection_log.dart';

void main() {
  test('close diagnostics keep codes and ages, never secrets', () {
    final DateTime opened = DateTime.utc(2026, 9, 26, 12);
    final DateTime at = opened.add(const Duration(seconds: 12));
    final String line = formatRemoteCloseLine(
      code: 1001,
      reason: 'going away https://secret.example/token?c=PAIRCODE C:\\Videos\\a.mkv',
      at: at,
      openedAt: opened,
      authenticated: true,
      lastFrameAt: at.subtract(const Duration(milliseconds: 40)),
      lastSnapshotAt: at.subtract(const Duration(milliseconds: 200)),
      lastHeartbeatAt: at.subtract(const Duration(seconds: 3)),
      eventLoopLag: const Duration(milliseconds: 80),
      pendingBrowser: 1,
      lastCommandMs: 12,
    );
    expect(line, contains('code=1001'));
    expect(line, contains('reason=redacted'));
    expect(line, contains('authed=true'));
    expect(line, contains('ageMs=12000'));
    expect(line, contains('frameAgeMs=40'));
    expect(line, contains('snapshotAgeMs=200'));
    expect(line, contains('heartbeatAgeMs=3000'));
    expect(line, contains('eventLoopLagMs=80'));
    expect(line, contains('pendingBrowser=1'));
    expect(line, contains('lastCommandMs=12'));
    expect(line.contains('secret.example'), isFalse);
    expect(line.contains('PAIRCODE'), isFalse);
    expect(line.contains('Videos'), isFalse);
    expect(line.contains('token'), isFalse);
  });

  test('a known local reason is kept, and 1001 is only a code', () {
    final DateTime at = DateTime.utc(2026, 9, 26, 12, 1);
    final String line = formatRemoteCloseLine(
      code: 1001,
      reason: 'Remote is switched off.',
      at: at,
      openedAt: at,
      authenticated: false,
    );
    expect(line, contains('reason=Remote is switched off.'));
    expect(line, contains('code=1001'));
    expect(line.contains('wifi'), isFalse);
    expect(safeCloseReason('SocketException'), 'SocketException');
  });

  test('the socket close reason is redacted the same way as the log', () {
    expect(wireCloseReason(''), '');
    expect(wireCloseReason('Remote is switched off.'), 'Remote is switched off.');
    expect(
      wireCloseReason('https://secret.example/token'),
      'redacted',
    );
  });
}
