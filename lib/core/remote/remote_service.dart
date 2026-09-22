import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/osd/osd_controller.dart';
import '../browser_service.dart';
import '../media_utils.dart';
import '../player_service.dart';
import '../queue_service.dart';
import '../settings_service.dart';
import '../subtitle_service.dart';
import '../tune_service.dart';
import '../url_library_service.dart';
import '../window_state_service.dart';
import 'remote_command_handler.dart';
import 'remote_firewall.dart';
import 'remote_network.dart';
import 'remote_pairing.dart';
import 'remote_protocol.dart';
import 'remote_web_media_bridge.dart';

/// Lifecycle visible to the Remote panel and Settings.
enum RemoteStatus { off, starting, running, failed }

/// The PC's Resume toast as the snapshot carries it (remote.md §17.5).
///
/// The toast is the one *interactive* card on the PC deck: it appears when an
/// item lands at a remembered position and offers **Restart** ("you resumed at
/// 12:34 — start over?"). The phone mirrors it rather than inventing an offer
/// of its own, so the two always agree; `null` means the toast is not on
/// screen, and **presence is the offer** — there is no separate `offered`
/// flag for the phone to disagree with.
///
/// Pure and card-in/card-out, so the mapping is unit-testable without the
/// deck, the engine or a socket.
Map<String, Object?>? remoteResumeOffer(OsdCard? card) =>
    card is OsdResumeCard
        ? <String, Object?>{'position': card.position.inMilliseconds}
        : null;

class RemoteService {
  RemoteService._internal();
  static final RemoteService instance = RemoteService._internal();

  final ValueNotifier<RemoteStatus> status =
      ValueNotifier<RemoteStatus>(RemoteStatus.off);
  final ValueNotifier<String?> statusDetail = ValueNotifier<String?>(null);
  final ValueNotifier<int?> port = ValueNotifier<int?>(null);
  final ValueNotifier<String?> address = ValueNotifier<String?>(null);
  final ValueNotifier<String?> networkName = ValueNotifier<String?>(null);
  final ValueNotifier<List<RemoteDevice>> devices =
      ValueNotifier<List<RemoteDevice>>(const <RemoteDevice>[]);
  final ValueNotifier<String?> pairingCode = ValueNotifier<String?>(null);
  final ValueNotifier<int> connectedCount = ValueNotifier<int>(0);
  /// Rebuild tick for the delayed Windows Firewall hint.
  final ValueNotifier<int> firewallTick = ValueNotifier<int>(0);

  final RemoteDeviceStore _store = RemoteDeviceStore();
  final RemotePairing pairing = RemotePairing();
  final List<_RemoteConnection> _connections = <_RemoteConnection>[];
  int _pendingConnections = 0;
  int _lifecycleGeneration = 0;
  final List<VoidCallback> _removeObservers = <VoidCallback>[];

  HttpServer? _server;
  Timer? _eventTimer;
  Timer? _positionTimer;
  Timer? _retryTimer;
  Timer? _firewallTimer;
  Timer? _webMediaTimer;
  bool _loaded = false;
  bool _dirty = false;
  bool _everConnected = false;
  int _revision = 0;
  String? _controllerId;
  bool _webHasMedia = false;
  DateTime? _startedAt;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;

  String get serverName => Platform.localHostname;
  bool get isRunning => _server != null;
  bool get firewallHintVisible =>
      _startedAt != null &&
      !_everConnected &&
      DateTime.now().difference(_startedAt!) >= const Duration(seconds: 90);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _store.load();
    _refreshDevices();
    final SettingsService settings = SettingsService.instance;
    RemoteFirewallService.instance.preferredPortOf =
        () => settings.remotePort.value;
    settings.remoteEnabled.addListener(_onRemoteEnabledChanged);
    settings.remotePort.addListener(_onPortChanged);
    if (!settings.remoteEnabled.value) {
      status.value = RemoteStatus.off;
      statusDetail.value = 'Remote is off — turn it on in Settings';
    }
  }

  /// Starts after the first frame. It is intentionally fire-and-forget so a
  /// port or network problem can never delay a cold player launch.
  void scheduleStartup() {
    unawaited(Future<void>.delayed(Duration.zero, () async {
      await load();
      if (SettingsService.instance.remoteEnabled.value) await start();
    }));
  }

  Future<void> start() async {
    if (_server != null || status.value == RemoteStatus.starting) return;
    final int generation = ++_lifecycleGeneration;
    status.value = RemoteStatus.starting;
    statusDetail.value = 'Starting…';
    _startedAt = DateTime.now();
    _everConnected = false;
    try {
      final List<RemoteNetworkAddress> networks = await enumerateRemoteAddresses();
      final List<RemoteNetworkAddress> usable = networks
          .where((RemoteNetworkAddress item) =>
              isPrivateRemoteIpv4(item.host) && !isLoopbackRemoteIpv4(item.host))
          .toList();
      if (usable.isNotEmpty) {
        address.value = usable.first.host;
        networkName.value = usable.first.interfaceName;
        statusDetail.value = null;
      } else {
        address.value = null;
        networkName.value = null;
        statusDetail.value = 'SALU is not on a local network';
      }
      final int preferred = SettingsService.instance.remotePort.value;
      HttpServer? bound;
      int? boundPort;
      for (int candidate = preferred; candidate <= preferred + 9; candidate++) {
        try {
          bound = await HttpServer.bind(InternetAddress.anyIPv4, candidate,
              shared: false);
          boundPort = candidate;
          break;
        } on SocketException {
          // Try the next memorable port.
        }
      }
      bound ??= await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: false);
      boundPort ??= bound.port;
      if (generation != _lifecycleGeneration ||
          !SettingsService.instance.remoteEnabled.value) {
        await bound.close(force: true);
        address.value = null;
        networkName.value = null;
        port.value = null;
        return;
      }
      _server = bound;
      port.value = boundPort;
      if (pairing.panelOpen) pairingCode.value = pairing.code;
      bound.listen(_onRequest, onError: _onServerError, cancelOnError: false);
      _installObservers();
      _eventTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (_dirty) _flushState();
      });
      _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final PlayerService player = PlayerService.instance;
        if (!player.isPlaying.value) return;
        final Duration position = player.position.value;
        final Duration duration = player.duration.value;
        if (position != _lastPosition || duration != _lastDuration) {
          _lastPosition = position;
          _lastDuration = duration;
          _markDirty();
        }
      });
      _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshNetwork());
      _firewallTimer = Timer(const Duration(seconds: 90), () {
        firewallTick.value++;
        _markDirty();
      });
      status.value = RemoteStatus.running;
      // §8.3 (2026-09-21): every start re-verifies the firewall rule covers
      // the *running* exe — the moved-folder trap and the Cancel trap both
      // surface here, and the result feeds the panel's Fix row. Silent on
      // healthy machines; it never blocks or delays the listener itself.
      unawaited(RemoteFirewallService.instance.recheck());
      if (statusDetail.value == null) {
        debugPrint('[SALU] remote: listening on 0.0.0.0:$boundPort '
            '(${usable.isEmpty ? 'no private adapter' : '${usable.first.interfaceName} ${usable.first.host}'})');
      }
      _startWebMediaPolling();
      _markDirty();
    } catch (error) {
      status.value = RemoteStatus.failed;
      statusDetail.value = 'Couldn\'t start the remote (port busy)';
      debugPrint('[SALU] remote: failed to start: $error');
      await _stopTimers();
    }
  }

  Future<void> stop({String detail = 'Remote is off — turn it on in Settings'}) async {
    _lifecycleGeneration++;
    final HttpServer? server = _server;
    _server = null;
    await _stopTimers();
    for (final _RemoteConnection connection in List<_RemoteConnection>.of(_connections)) {
      await connection.close(RemoteCloseCode.disabled, 'Remote is switched off.');
    }
    _connections.clear();
    connectedCount.value = 0;
    for (final VoidCallback remove in _removeObservers) {
      remove();
    }
    _removeObservers.clear();
    await server?.close(force: true);
    port.value = null;
    address.value = null;
    networkName.value = null;
    final bool panelWasOpen = pairing.panelOpen;
    pairingCode.value = null;
    if (panelWasOpen) {
      // Keep the dialog's lifecycle alive while the toggle is flipped, but
      // invalidate the old QR. start() publishes the fresh code again.
      pairing.rotate();
    } else {
      pairing.closePanel();
    }
    status.value = RemoteStatus.off;
    statusDetail.value = detail;
    _refreshDevices();
  }

  Future<void> restart() async {
    await stop(detail: 'Restarting…');
    if (SettingsService.instance.remoteEnabled.value) await start();
  }

  Future<void> _onRemoteEnabledChanged() async {
    if (SettingsService.instance.remoteEnabled.value) {
      await start();
    } else {
      await stop();
      // File browsing is a separate setting, but disabling the listener also
      // closes its privacy surface. The user may turn file access back on
      // independently after Remote is enabled again.
      if (SettingsService.instance.remoteFileAccess.value) {
        await SettingsService.instance.setRemoteFileAccess(false);
      }
    }
  }

  void _onPortChanged() {
    if (_server != null) unawaited(restart());
  }

  Future<void> _refreshNetwork() async {
    if (_server == null) return;
    final List<RemoteNetworkAddress> list = await enumerateRemoteAddresses();
    final String? next = list.isEmpty ? null : list.first.host;
    if (next != address.value) {
      address.value = next;
      networkName.value = list.isEmpty ? null : list.first.interfaceName;
      statusDetail.value = next == null ? 'SALU is not on a local network' : null;
      _markDirty();
    }
  }

  void openPairingPanel() {
    pairing.openPanel();
    pairingCode.value = pairing.code;
    // Opening the help surface is worth one fresh probe — a stale answer
    // (rule allowed moments ago in Windows' own popup) must never show the
    // Fix row.
    unawaited(RemoteFirewallService.instance.recheck());
    _markDirty();
  }

  void closePairingPanel() {
    pairing.closePanel();
    pairingCode.value = null;
  }

  String? get qrPayload {
    final String? host = address.value;
    final int? boundPort = port.value;
    final String? code = pairingCode.value ?? (pairing.panelOpen ? pairing.code : null);
    if (host == null || boundPort == null || code == null) return null;
    return Uri(
      scheme: 'salu',
      host: 'pair',
      queryParameters: <String, String>{
        'v': '$protocolVersion',
        'n': serverName,
        'h': host,
        'p': '$boundPort',
        'c': normalizePairingCode(code),
      },
    ).toString();
  }

  Future<void> forgetDevice(String id) async {
    await _store.forget(id);
    for (final _RemoteConnection connection in List<_RemoteConnection>.of(_connections)) {
      if (connection.deviceId == id) {
        await connection.close(RemoteCloseCode.unauthorized, 'Device forgotten.');
      }
    }
    if (_controllerId == id) _controllerId = null;
    _refreshDevices();
    _markDirty();
  }

  void _onRequest(HttpRequest request) {
    final String? origin = request.headers.value('origin');
    final InternetAddress? peer = request.connectionInfo?.remoteAddress;
    final String host = peer?.address ?? '';
    final bool localProbe = isLoopbackRemoteIpv4(host);
    if (peer == null || (!isPrivateRemoteIpv4(host) && !localProbe)) {
      debugPrint('[SALU] remote: rejected $host (not a private address)');
      unawaited(_rejectRequest(request, RemoteCloseCode.notPrivateLan));
      return;
    }
    if (origin != null) {
      unawaited(_rejectRequest(request, RemoteCloseCode.unauthorized));
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      unawaited(_rejectRequest(request, RemoteCloseCode.unauthorized));
      return;
    }
    if (_connections.length + _pendingConnections >= 4) {
      unawaited(_rejectRequest(request, RemoteCloseCode.tooManyConnections));
      return;
    }
    _pendingConnections++;
    unawaited(_upgrade(request));
  }

  Future<void> _upgrade(HttpRequest request) async {
    try {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 20);
      final _RemoteConnection connection = _RemoteConnection(this, socket);
      _connections.add(connection);
      _updateConnectedCount();
      await connection.send(RemoteProtocol.hello(
        version: '0.1.0',
        name: serverName,
        state: _snapshot(),
      ));
      connection.start();
      _startWebMediaPolling();
    } catch (error) {
      debugPrint('[SALU] remote: websocket upgrade failed: $error');
    } finally {
      _pendingConnections--;
    }
  }

  Future<void> _rejectRequest(HttpRequest request, int code) async {
    try {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    } catch (_) {}
  }

  void _onServerError(Object error, StackTrace stack) {
    debugPrint('[SALU] remote: server error: $error');
  }

  void _installObservers() {
    final PlayerService player = PlayerService.instance;
    final QueueService queue = QueueService.instance;
    final BrowserService browser = BrowserService.instance;
    final WindowStateService window = WindowStateService.instance;
    final SettingsService settings = SettingsService.instance;
    final List<ValueListenable<Object?>> sources = <ValueListenable<Object?>>[
      player.transportState,
      player.isPlaying,
      player.hasMedia,
      player.currentTitle,
      player.position,
      player.duration,
      player.volumeLevel,
      player.isMuted,
      player.isBuffering,
      player.shuffleOn,
      player.repeatMode,
      player.trackSurface,
      player.subDelay,
      queue.items,
      queue.index,
      browser.webTitle,
      browser.webUrl,
      browser.webCanBack,
      browser.webCanForward,
      browser.webLoading,
      browser.webTabCount,
      browser.pageFullscreen,
      window.mode,
      window.isFullscreen,
      settings.remoteFileAccess,
      settings.autoEq,
      settings.subtitleLanguage,
      settings.subtitleAutoDownload,
      settings.subtitleApiKey,
      settings.subtitleUsername,
      settings.subtitlePassword,
      UrlLibraryService.instance.entries,
      TuneService.instance.fileKind,
      TuneService.instance.eq,
      TuneService.instance.eqStop,
      TuneService.instance.eqCustom,
      TuneService.instance.speedStop,
      // The deck's one slot: the Resume toast appearing (or closing on its
      // own 4 s TTL, on Esc, on a click-outside, or on any transport action)
      // is what makes and unmakes the phone's Start over seat (§17.5).
      OsdController.instance.current,
    ];
    browser.mode.addListener(_onBrowserModeChanged);
    _removeObservers.add(() => browser.mode.removeListener(_onBrowserModeChanged));
    for (final ValueListenable<Object?> source in sources) {
      source.addListener(_markDirty);
      _removeObservers.add(() => source.removeListener(_markDirty));
    }
  }

  void _onBrowserModeChanged() {
    _startWebMediaPolling();
    _markDirty();
  }

  void _startWebMediaPolling() {
    _webMediaTimer?.cancel();
    if (!_connections.any((connection) => connection.isAuthenticated) ||
        !BrowserService.instance.isWeb) {
      if (_webHasMedia) {
        _webHasMedia = false;
        _markDirty();
      }
      return;
    }
    _webMediaTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_connections.any((connection) => connection.isAuthenticated) ||
          !BrowserService.instance.isWeb) {
        return;
      }
      final Object? raw = await BrowserService.instance.remoteExecuteScript(
          '''(${RemoteWebMediaScripts.find})''');
      final bool found = raw == true;
      if (found != _webHasMedia) {
        _webHasMedia = found;
        _markDirty();
      }
    });
  }

  void _markDirty() {
    if (_server == null) return;
    _dirty = true;
  }

  void _flushState() {
    if (!_dirty || _server == null) return;
    _dirty = false;
    final Map<String, Object?> message =
        RemoteProtocol.state(_snapshot(revision: ++_revision));
    for (final _RemoteConnection connection in List<_RemoteConnection>.of(_connections)) {
      if (connection.isAuthenticated) unawaited(connection.send(message));
    }
  }

  Map<String, Object?> _snapshot({int? revision}) {
    final PlayerService player = PlayerService.instance;
    final QueueService queue = QueueService.instance;
    final BrowserService browser = BrowserService.instance;
    final TuneService tune = TuneService.instance;
    final SettingsService settings = SettingsService.instance;
    final String queueKind = !queue.hasQueue
        ? 'empty'
        : (queue.isChannelList ? 'channels' : 'files');
    final String? path = player.currentPath.value;
    final String? kind = queue.isChannelList
        ? 'channel'
        : path == null
            ? null
            : (MediaUtils.isVideo(path) ? 'video' : 'audio');
    final Map<String, Object?> snapshot = <String, Object?>{
      'proto': protocolVersion,
      'rev': revision ?? _revision,
      'at': DateTime.now().millisecondsSinceEpoch,
      'mode': browser.isWeb ? 'web' : 'player',
      'window': <String, Object?>{
        'mode': windowModeName(WindowStateService.instance.mode.value),
        'fullscreen': WindowStateService.instance.isFullscreen.value,
      },
      'playback': <String, Object?>{
        'state': player.transportState.value.name,
        'hasMedia': player.hasMedia.value,
        'title': player.currentTitle.value,
        if (kind != null) 'kind': kind,
        'position': player.position.value.inMilliseconds,
        'duration': player.duration.value.inMilliseconds,
        'buffering': player.isBuffering.value,
        'seekable': player.duration.value > Duration.zero && !queue.isChannelList,
        'volume': player.volumeLevel.value.round().clamp(0, 100),
        'muted': player.isMuted.value,
        'shuffle': player.shuffleOn.value,
        'repeat': player.repeatMode.value.name,
        // Mirrors the Resume toast exactly — `null` whenever it is not up.
        'resume': remoteResumeOffer(OsdController.instance.current.value),
      },
      'queue': <String, Object?>{
        'kind': queueKind,
        'count': queue.length,
        'index': queue.index.value,
      },
      'control': _controllerId == null ? null : <String, Object?>{
        'deviceId': _controllerId,
        'name': _store.find(_controllerId!)?.name,
      },
      'devices': devices.value.map((RemoteDevice d) => d.toPublicJson()).toList(),
      'web': <String, Object?>{
        'title': browser.webTitle.value,
        'url': browser.webUrl.value,
        'canBack': browser.webCanBack.value,
        'canForward': browser.webCanForward.value,
        'loading': browser.webLoading.value,
        'tabs': browser.webTabCount.value,
        'fullscreen': browser.pageFullscreen.value,
        'hasMedia': browser.isWeb && _webHasMedia,
      },
      'tracks': <String, Object?>{
        'audio': player.trackSurface.value.audio.length,
        'subs': player.trackSurface.value.embeddedSubs.length +
            player.trackSurface.value.localSubs.length,
        'subSelected': player.hasSubtitleSelected,
      },
      'tune': <String, Object?>{
        'kind': tune.fileKind.value.name,
        'preset': tune.eqStop.value,
        'custom': tune.eqCustom.value,
        'autoEq': settings.autoEq.value,
        'speed': tune.speedStop.value ?? 'x1',
      },
      'subs': <String, Object?>{
        'delay': player.subDelay.value,
        'lang': settings.subtitleLanguage.value,
        'autoDownload': settings.subtitleAutoDownload.value,
        'engine': <String, Object?>{
          'key': SubtitleService.instance.keyConfigured,
          'signedIn': SubtitleService.instance.signedIn,
          'quotaPaused': SubtitleService.instance.quotaPaused,
        },
      },
      'files': <String, Object?>{'enabled': settings.remoteFileAccess.value},
      'library': <String, Object?>{
        'count': _libraryCount(),
      },
    };
    return RemoteSnapshot.fromValues(snapshot).toJson();
  }

  int _libraryCount() => UrlLibraryService.instance.entries.value.length;

  void _onConnectionClosed(_RemoteConnection connection) {
    _connections.remove(connection);
    _updateConnectedCount();
    if (connection.deviceId != null) _store.setOnline(connection.deviceId!, false);
    _refreshDevices();
    _startWebMediaPolling();
    _markDirty();
  }

  Future<void> _stopTimers() async {
    _eventTimer?.cancel();
    _positionTimer?.cancel();
    _retryTimer?.cancel();
    _firewallTimer?.cancel();
    _webMediaTimer?.cancel();
    _eventTimer = null;
    _positionTimer = null;
    _retryTimer = null;
    _firewallTimer = null;
    _webMediaTimer = null;
  }

  void _updateConnectedCount() {
    connectedCount.value = _connections.where((connection) => connection.isAuthenticated).length;
  }

  void _refreshDevices() {
    final List<RemoteDevice> next = _store.devices.map((RemoteDevice device) {
      final bool online = _connections.any((c) => c.deviceId == device.id);
      return device.copyWith(online: online, control: device.id == _controllerId);
    }).toList(growable: false);
    devices.value = List<RemoteDevice>.unmodifiable(next);
  }

  Future<void> _handleAuth(_RemoteConnection connection, Map<String, Object?> map) async {
    if (!RemoteProtocol.isVersion(map['proto'])) {
      await connection.send(RemoteProtocol.error(
          map['id'] is num ? (map['id'] as num).toInt() : 0,
          RemoteErrorCode.versionMismatch,
          'Update SALU Remote.',
          proto: protocolVersion));
      await connection.close(RemoteCloseCode.versionMismatch, 'Protocol mismatch.');
      return;
    }
    final Map<String, Object?> device = map['device'] is Map
        ? (map['device'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final String id = '${device['id'] ?? ''}'.trim();
    final String name = '${device['name'] ?? 'Phone'}'.trim();
    final String platform = '${device['platform'] ?? 'unknown'}';
    final Object? rawToken = map['token'];
    final Object? rawPair = map['pair'];
    RemoteDevice? known;
    String? token;
    if (rawToken is String && rawToken.isNotEmpty) {
      known = _store.findByToken(rawToken);
      token = rawToken;
      if (known == null) {
        await connection.failAuth(
          RemoteErrorCode.badToken,
          'This phone is no longer paired.',
          id: map['id'] is num ? (map['id'] as num).toInt() : 0,
        );
        return;
      }
    } else if (rawPair is String && pairing.accepts(rawPair)) {
      token = generateDeviceToken();
      final String deviceId = id.isEmpty ? _newDeviceId() : id;
      known = await _store.remember(
        id: deviceId,
        name: name,
        platform: platform,
        token: token,
      );
      pairing.pairedSuccessfully();
      pairingCode.value = pairing.panelOpen ? pairing.code : null;
      debugPrint('[SALU] remote: ${known.name} paired (${known.id})');
    } else {
      await connection.failAuth(
        RemoteErrorCode.badCode,
        'That pairing code is not valid.',
        id: map['id'] is num ? (map['id'] as num).toInt() : 0,
      );
      return;
    }
    // A remembered token identifies the device; the client-supplied id is
    // only metadata and never overrides that identity. Every path above
    // either returns or leaves both [known] and [token] assigned, so no
    // null check is needed here.
    await _store.touch(known.id, name: name, platform: platform);
    _store.setOnline(known.id, true);
    connection.authenticated(known.id, name);
    _updateConnectedCount();
    _everConnected = true;
    _refreshDevices();
    _startWebMediaPolling();
    _markDirty();
    await connection.send(RemoteProtocol.authOk(
      id: map['id'] is num ? (map['id'] as num).toInt() : 0,
      deviceId: known.id,
      token: token,
      serverName: serverName,
      version: '0.1.0',
    ));
    await connection.send(RemoteProtocol.state(_snapshot(revision: ++_revision)));
  }

  void takeControl(String deviceId) {
    if (_controllerId == deviceId) return;
    _controllerId = deviceId;
    _store.setControl(deviceId);
    _refreshDevices();
    _markDirty();
  }

  String _newDeviceId() {
    final String candidate = generateDeviceToken().substring(0, 10);
    return candidate;
  }

  Future<void> _ensurePlayerAndFocus() async {
    // A remote press should not steal another app's focus when SALU is
    // already the Player surface (or the always-on-top mini bar). Web mode
    // is the one case where the command deliberately pulls SALU forward.
    if (!BrowserService.instance.isWeb) return;
    await BrowserService.instance.setMode(SaluMode.player);
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
}

/// A connection has exactly one auth timer and one sliding command window.
class _RemoteConnection {
  _RemoteConnection(this.service, this.socket);

  final RemoteService service;
  final WebSocket socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _authTimer;
  bool _authenticated = false;
  bool get isAuthenticated => _authenticated;
  bool _closed = false;
  String? deviceId;
  String? deviceName;
  RemoteCommandHandler? _handler;
  final List<DateTime> _commands = <DateTime>[];

  void start() {
    _authTimer = Timer(const Duration(seconds: 5), () {
      if (!_authenticated) unawaited(failAuth('auth_timeout', 'Authentication timed out.'));
    });
    _subscription = socket.listen(
      (Object? event) => unawaited(_message(event)),
      onDone: () => unawaited(close()),
      onError: (Object error, StackTrace stack) => unawaited(close()),
      cancelOnError: true,
    );
  }

  Future<void> _message(Object? event) async {
    if (_closed || event is! String) return;
    Map<String, Object?> message;
    try {
      message = RemoteProtocol.decode(event);
    } on RemoteProtocolException catch (error) {
      await close(RemoteCloseCode.unauthorized, error.message);
      return;
    }
    if (!_authenticated) {
      if (message['type'] != 'auth') {
        await failAuth('auth_required', 'Authenticate before sending commands.');
        return;
      }
      await service._handleAuth(this, message);
      return;
    }
    final RemoteCommand? command = RemoteCommand.tryParse(message);
    if (command == null || !RemoteProtocol.isVersion(message['proto'])) {
      await send(RemoteProtocol.error(
          message['id'] is num ? (message['id'] as num).toInt() : 0,
          RemoteErrorCode.versionMismatch,
          'Update SALU Remote.'));
      return;
    }
    final DateTime now = DateTime.now();
    _commands.removeWhere((DateTime item) => now.difference(item) >= const Duration(seconds: 1));
    if (_commands.length >= 30) {
      await send(RemoteProtocol.error(command.id, RemoteErrorCode.tooFast, 'Too many commands.'));
      return;
    }
    _commands.add(now);
    // Control is informational rather than a permission lock: the phone
    // issuing a real command becomes the device shown in the snapshot.
    if (command.verb != 'ping') service.takeControl(deviceId!);
    final RemoteCommandHandler? handler = _handler;
    if (handler == null) {
      await failAuth('auth_required', 'Authenticate before sending commands.');
      return;
    }
    final RemoteCommandResponse response = await handler.handle(command).timeout(
      const Duration(seconds: 3),
      onTimeout: () => const RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'The PC is busy — try again in a moment.',
      ),
    );
    if (response.ok) {
      if (response.result != null && response.result!.containsKey('type')) {
        await send(<String, Object?>{
          'id': command.id,
          'proto': protocolVersion,
          ...response.result!,
        });
      } else {
        await send(RemoteProtocol.ack(command.id, result: response.result));
      }
      if (command.verb == 'state_get') {
        service._markDirty();
        service._flushState();
      }
      service._startWebMediaPolling();
      service._markDirty();
    } else {
      await send(RemoteProtocol.error(command.id, response.code!, response.message!));
    }
  }

  void authenticated(String id, String name) {
    _authenticated = true;
    _authTimer?.cancel();
    deviceId = id;
    deviceName = name;
    _handler = RemoteCommandHandler(
      ensurePlayerAndFocus: service._ensurePlayerAndFocus,
      onControl: () => service.takeControl(deviceId!),
      webMedia: RemoteWebMediaBridge(
        executeScript: BrowserService.instance.remoteExecuteScript,
      ),
    );
  }

  Future<void> failAuth(String code, String message, {int id = 0}) async {
    if (_closed) return;
    await send(RemoteProtocol.error(id, code, message));
    await close(RemoteCloseCode.unauthorized, message);
  }

  Future<void> send(Map<String, Object?> message) async {
    if (_closed) return;
    try {
      socket.add(RemoteProtocol.encode(message));
    } on RemoteProtocolException {
      // A large on-demand result must fail the one request, not tear down a
      // healthy authenticated socket. Handshake/state frames are bounded by
      // construction; an oversized command response gets a normal error.
      final Object? rawId = message['id'];
      if (rawId is num && message['type'] != 'hello' && message['type'] != 'state') {
        try {
          socket.add(RemoteProtocol.encode(RemoteProtocol.error(
            rawId.toInt(),
            RemoteErrorCode.busy,
            'The response is too large; request a smaller page.',
          )));
          return;
        } catch (_) {}
      }
      await close(RemoteCloseCode.unauthorized, 'Message too large.');
    }
  }

  Future<void> close([int code = 1000, String reason = '']) async {
    if (_closed) return;
    _closed = true;
    _authTimer?.cancel();
    await _subscription?.cancel();
    try {
      await socket.close(code, reason);
    } catch (_) {}
    service._onConnectionClosed(this);
  }
}

String windowModeName(WindowMode mode) => mode == WindowMode.mini ? 'mini' : 'full';

