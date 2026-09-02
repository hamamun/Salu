import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One connected remote controller (the future SALU Android app).
class RemoteClient {
  RemoteClient._(this._channel, this.address);

  final WebSocketChannel _channel;

  /// `ip:port` of the peer, handy for logs and the Settings status card.
  final String address;

  void sendJson(Map<String, Object?> payload) {
    try {
      _channel.sink.add(jsonEncode(payload));
    } catch (error) {
      debugPrint('[SALU/remote] send failed: $error');
    }
  }

  void close() {
    try {
      _channel.sink.close();
    } catch (_) {
      // Already gone — nothing to do.
    }
  }
}

/// Reply shape accepted back from the command layer; `null` sends nothing.
typedef RemoteMessageHandler = Map<String, Object?>? Function(
    RemoteClient client, Map<String, dynamic> message);

typedef RemoteClientEvent = void Function(RemoteClient client);

/// SALU's invisible local WebSocket server (Phase 8 · Step 1).
///
/// Built on `shelf` + `shelf_web_socket`, bound to `0.0.0.0` so any device on
/// the same Wi‑Fi can reach it. The wire protocol is deliberately minimal:
/// one JSON object per message, `{"action": …}` inbound and `{"type": …}`
/// outbound. Non-WebSocket `GET /health` requests answer with a small JSON
/// document so companion apps can probe SALU without a handshake.
///
/// The server never runs on its own — [RemoteServer] (the facade in
/// `remote_server.dart`) only starts it while the user's
/// "Enable Remote Control Server" toggle is ON.
class RemoteWebSocketServer {
  HttpServer? _server;
  final Set<RemoteClient> _clients = <RemoteClient>{};

  /// Called for every JSON object received from a client; the returned map
  /// (when not `null`) is sent straight back to that client.
  RemoteMessageHandler? onMessage;

  /// Fired when a client connects (used to push a `hello` + state snapshot)
  /// and when one disconnects (to refresh the Settings status).
  RemoteClientEvent? onClientConnected;
  RemoteClientEvent? onClientDisconnected;

  bool get isRunning => _server != null;

  int get clientCount => _clients.length;

  Set<RemoteClient> get clients => Set<RemoteClient>.unmodifiable(_clients);

  Future<void> start({String host = '0.0.0.0', int port = 8080}) async {
    if (_server != null) return;

    FutureOr<shelf.Response> handler(shelf.Request request) {
      if (request.method == 'GET' && request.url.path == 'health') {
        return shelf.Response.ok(
          jsonEncode(<String, Object?>{
            'app': 'SALU',
            'ok': true,
            'clients': _clients.length,
          }),
          headers: <String, String>{'Content-Type': 'application/json'},
        );
      }

      final String address = _describePeer(request);
      final shelf.Handler upgrade = webSocketHandler(
        (WebSocketChannel channel, String? subprotocol) =>
            _onConnect(channel, address),
        pingInterval: const Duration(seconds: 25),
      );
      return upgrade(request);
    }

    _server = await shelf_io.serve(handler, host, port);
    debugPrint('[SALU/remote] WebSocket server listening on ws://$host:$port');
  }

  Future<void> stop() async {
    for (final RemoteClient client in _clients.toList()) {
      client.close();
    }
    _clients.clear();
    final HttpServer? server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
      debugPrint('[SALU/remote] WebSocket server stopped');
    }
  }

  void _onConnect(WebSocketChannel channel, String address) {
    final RemoteClient client = RemoteClient._(channel, address);
    _clients.add(client);
    onClientConnected?.call(client);

    channel.stream.listen(
      (Object? event) => _onData(client, event),
      onDone: () => _onDone(client),
      onError: (Object _) => _onDone(client),
      cancelOnError: true,
    );
  }

  void _onData(RemoteClient client, Object? event) {
    if (event is! String) return; // Binary frames are not part of the protocol.
    final Object? decoded;
    try {
      decoded = jsonDecode(event);
    } on FormatException {
      client.sendJson(<String, Object?>{
        'type': 'error',
        'message': 'Expected a JSON object.',
      });
      return;
    }
    if (decoded is! Map) {
      client.sendJson(<String, Object?>{
        'type': 'error',
        'message': 'Expected a JSON object.',
      });
      return;
    }
    final Map<String, Object?>? reply =
        onMessage?.call(client, Map<String, dynamic>.from(decoded));
    if (reply != null) client.sendJson(reply);
  }

  void _onDone(RemoteClient client) {
    if (_clients.remove(client)) {
      onClientDisconnected?.call(client);
    }
  }

  /// Pushes [payload] to every connected client (state broadcasts).
  void broadcast(Map<String, Object?> payload) {
    if (_clients.isEmpty) return;
    for (final RemoteClient client in _clients.toList()) {
      client.sendJson(payload);
    }
  }

  /// Best-effort peer description from the underlying shelf_io request.
  static String _describePeer(shelf.Request request) {
    final HttpConnectionInfo? connectionInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final InternetAddress? remoteAddress = connectionInfo?.remoteAddress;
    final int? remotePort = connectionInfo?.remotePort;
    if (remoteAddress == null || remotePort == null) {
      return 'lan-client';
    }
    return '${remoteAddress.address}:$remotePort';
  }
}
