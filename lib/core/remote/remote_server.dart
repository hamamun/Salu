import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../app_prefs.dart';
import '../player_service.dart';
import 'command_handler.dart';
import 'mdns_broadcaster.dart';
import 'state_broadcaster.dart';
import 'websocket_server.dart';

/// Lifecycle facade for SALU's Android remote backend (Phase 8).
///
/// Owns the three moving pieces — the [RemoteWebSocketServer] (commands in),
/// the [PlayerStateBroadcaster] (state out) and the [MdnsBroadcaster]
/// (auto-discovery) — and keeps them running for exactly as long as the
/// user's "Enable Remote Control Server" switch is on. Flip it off and every
/// socket is closed, the mDNS responder shuts down, and the app makes zero
/// background network calls again (Phase 8 · Step 4).
class RemoteServer extends ChangeNotifier {
  RemoteServer._();

  static final RemoteServer instance = RemoteServer._();

  /// Preferred listen port per the spec; if something already holds it we
  /// climb up to [maxPortAttempts] further ports and report the winner.
  static const int defaultPort = 8080;
  static const int maxPortAttempts = 10;

  final RemoteWebSocketServer _sockets = RemoteWebSocketServer();
  RemoteCommandHandler? _commands;
  PlayerStateBroadcaster? _broadcaster;
  MdnsBroadcaster? _mdns;

  bool _installed = false;
  bool _switching = false;
  bool _pendingSync = false;
  int _activePort = 0;
  String? _lastError;

  bool get running => _sockets.isRunning;
  int get port => _activePort;
  int get clientCount => _sockets.clientCount;
  String? get lastError => _lastError;

  /// Wire the plumbing once (idempotent), then honour the stored preference.
  Future<void> install() async {
    if (_installed) return;
    _installed = true;

    _broadcaster = PlayerStateBroadcaster(
      player: PlayerService.instance,
      broadcast: (Map<String, Object?> payload) {
        if (running) _sockets.broadcast(payload);
      },
    );
    _commands = RemoteCommandHandler(
      PlayerService.instance,
      stateProvider: () => _broadcaster?.snapshot() ?? const <String, Object?>{},
    );

    _sockets.onMessage = (RemoteClient client, Map<String, dynamic> message) =>
        _commands?.handle(client, message);
    _sockets.onClientConnected = _onClientConnected;
    _sockets.onClientDisconnected = (_) => notifyListeners();

    AppPrefs.instance.addListener(_onPrefsChanged);
    await refreshAddressCache();
    await syncWithPreferences();
  }

  void _onPrefsChanged() => unawaited(syncWithPreferences());

  void _onClientConnected(RemoteClient client) {
    // New controller? Introduce SALU and hand it a full state snapshot right
    // away so its UI is correct from the first frame.
    client.sendJson(<String, Object?>{
      'type': 'hello',
      'app': AppInfo.name,
      'version': AppInfo.version,
      'protocol': 1,
      'port': _activePort,
      'state': _broadcaster?.snapshot(),
    });
    notifyListeners();
  }

  /// Starts or stops the whole stack based on [AppPrefs.remoteControlEnabled].
  Future<void> syncWithPreferences() async {
    if (_switching) {
      _pendingSync = true; // Toggle flipped mid-start: run once more after.
      return;
    }
    _switching = true;
    try {
      do {
        _pendingSync = false;
        if (AppPrefs.instance.remoteControlEnabled) {
          await _start();
        } else {
          await _stop();
        }
      } while (_pendingSync);
    } finally {
      _switching = false;
    }
  }

  Future<void> _start() async {
    if (running) return;
    _lastError = null;
    for (int attempt = 0; attempt < maxPortAttempts; attempt++) {
      final int candidate = defaultPort + attempt;
      try {
        await _sockets.start(port: candidate);
        _activePort = candidate;
        _broadcaster?.attach();
        _mdns = MdnsBroadcaster(port: candidate);
        unawaited(_mdns!.start());
        await refreshAddressCache();
        debugPrint('[SALU/remote] server up on port $candidate '
            '(${localAddresses().length} LAN address(es))');
        notifyListeners();
        return;
      } catch (error) {
        _lastError = '$error';
        debugPrint('[SALU/remote] port $candidate busy/unusable: $error');
      }
    }
    debugPrint('[SALU/remote] could not bind any port '
        '($defaultPort–${defaultPort + maxPortAttempts - 1}): $_lastError');
    notifyListeners();
  }

  Future<void> _stop() async {
    if (!running && _mdns == null) return;
    _broadcaster?.detach();
    await _sockets.stop();
    await _mdns?.stop();
    _mdns = null;
    _activePort = 0;
    notifyListeners();
  }

  /// The LAN IPv4 addresses a companion app should dial, e.g.
  /// `192.168.1.42:8080` entries for the Settings status card.
  List<String> endpoints() {
    if (!running) return const <String>[];
    return <String>[
      for (final String address in localAddresses()) 'ws://$address:$_activePort',
    ];
  }

  static List<String> localAddresses() {
    final List<String> out = <String>[];
    try {
      // Synchronous snapshot via the async API's cached answers is not
      // available — this helper is only called from async UI contexts that
      // tolerate a tiny delay, so do a raw loopback-safe enumeration instead.
      for (final InternetAddress address
          in _cachedInterfaceAddresses ?? const <InternetAddress>[]) {
        out.add(address.address);
      }
    } catch (_) {
      // Never let the status card break the app.
    }
    return out;
  }

  /// Refreshed by [install] and whenever the server (re)starts.
  static List<InternetAddress>? _cachedInterfaceAddresses;

  static Future<void> refreshAddressCache() async {
    try {
      final List<InternetAddress> found = <InternetAddress>[];
      for (final NetworkInterface interface
          in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final InternetAddress address in interface.addresses) {
          if (address.rawAddress.length == 4 && !address.isLoopback) {
            found.add(address);
          }
        }
      }
      _cachedInterfaceAddresses = found;
    } catch (error) {
      debugPrint('[SALU/remote] address scan failed: $error');
    }
  }

  @override
  void dispose() {
    if (_installed) {
      AppPrefs.instance.removeListener(_onPrefsChanged);
    }
    _broadcaster?.detach();
    unawaited(_sockets.stop());
    unawaited(_mdns?.stop());
    super.dispose();
  }
}
