import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Dependency-free mDNS (Bonjour) broadcaster for SALU's remote server
/// (Phase 8 · Step 1 — "Auto-Discovery").
///
/// Announces the PC on the Wi‑Fi as a `_salu-remote._tcp.local` service so
/// the Android companion app can find SALU's IP + port with a standard
/// `multicast_dns` query — no manual IP typing, no extra packages, and no
/// Bonjour/Zeroconf native dependency: the DNS answer packets are built by
/// hand and pushed over a multicast UDP socket (RFC 6762 on the wire).
///
/// Behaviour:
///  * sends an unsolicited multicast answer burst at startup, then quietly
///    re-announces so caches never expire;
///  * listens on 5353 and unicast-replies to any PTR/SRV/A query that
///    mentions SALU's service;
///  * everything is wrapped in try/catch — a blocked port (firewall) simply
///    disables discovery, the WebSocket server itself keeps working.
class MdnsBroadcaster {
  MdnsBroadcaster({required this.port});

  /// Port the companion should dial once the service resolves.
  final int port;

  static const String serviceType = '_salu-remote._tcp';
  static const String mDnsGroup = '239.255.255.250';
  static const int mDnsPort = 5353;

  /// Answer TTL. Announcements repeat well below this window.
  static const int _ttl = 120;
  static const Duration _reannounce = Duration(seconds: 60);

  RawDatagramSocket? _socket;
  Timer? _repeatTimer;
  final List<Timer> _burst = <Timer>[];

  /// Cached LAN IPv4 addresses used in the A records (refreshed on announce).
  List<InternetAddress> _addresses = const <InternetAddress>[];

  bool get isRunning => _socket != null;

  /// Human-readable service instance, e.g. `salu-pc._salu-remote._tcp.local`.
  String get instanceLabel {
    final String raw = Platform.localHostname
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return raw.isEmpty ? 'salu-pc' : raw;
  }

  String get _instanceFqdn => '$instanceLabel.$serviceType.local';
  String get _serviceFqdn => '$serviceType.local';
  String get _hostFqdn => '$instanceLabel.local';

  Future<void> start() async {
    await stop();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        mDnsPort,
        reuseAddress: true,
        ttl: 255,
      );
    } catch (_) {
      try {
        // Another responder owns 5353 — fall back to send-only announcements
        // from an ephemeral port (clients can still probe the WS /health).
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (error) {
        debugPrint('[SALU/mdns] disabled (socket bind failed): $error');
        _socket = null;
        return;
      }
    }

    final RawDatagramSocket socket = _socket!;
    try {
      socket.broadcastEnabled = true;
      socket.multicastLoopback = true;
      socket.multicastTtl = 2; // Same Wi‑Fi segment only.
    } catch (_) {
      // Some drivers refuse these options — announcements still work.
    }

    await _refreshInterfaces(socket);
    socket.listen(_onEvent);

    // RFC 6762-style startup burst, then a lazy keep-alive timer.
    for (final int ms in <int>[0, 250, 750]) {
      _burst.add(Timer(Duration(milliseconds: ms), announceOnce));
    }
    _repeatTimer = Timer.periodic(_reannounce, (_) {
      unawaited(_refreshInterfaces(socket));
      announceOnce();
    });
    debugPrint('[SALU/mdns] advertising $_instanceFqdn on port $port');
  }

  Future<void> stop() async {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    for (final Timer timer in _burst) {
      timer.cancel();
    }
    _burst.clear();
    _addresses = const <InternetAddress>[];
    _socket?.close();
    _socket = null;
  }

  /// Joins the mDNS group on every interface and refreshes the A-record cache.
  Future<void> _refreshInterfaces(RawDatagramSocket socket) async {
    final List<InternetAddress> addresses = <InternetAddress>[];
    try {
      for (final NetworkInterface interface
          in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final InternetAddress address in interface.addresses) {
          if (address.rawAddress.length == 4) addresses.add(address);
        }
        try {
          socket.joinMulticast(InternetAddress(mDnsGroup), interface);
        } catch (error) {
          debugPrint('[SALU/mdns] join failed on ${interface.name}: $error');
        }
      }
    } catch (error) {
      debugPrint('[SALU/mdns] interface scan failed: $error');
    }
    if (addresses.isNotEmpty) _addresses = List<InternetAddress>.unmodifiable(addresses);
  }

  /// Multicasts one full answer (PTR + SRV + TXT + A per IPv4 address).
  void announceOnce() {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;
    final Uint8List packet = buildAnswer();
    if (packet.isEmpty) return;
    try {
      socket.send(packet, InternetAddress(mDnsGroup), mDnsPort);
    } catch (error) {
      debugPrint('[SALU/mdns] announce failed: $error');
    }
  }

  void _onEvent(RawSocketEvent event) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null || event != RawSocketEvent.read) return;

    final Datagram? datagram = socket.receive();
    if (datagram == null || datagram.length < 12) return;
    final Uint8List data = datagram.data;

    // Only DNS queries (QR bit clear) with at least one question interest us.
    final int flags = (data[2] << 8) | data[3];
    if ((flags & 0x8000) != 0) return;
    final int questions = (data[4] << 8) | data[5];
    if (questions == 0) return;

    // Cheap-but-safe question sniff: does the packet mention our service,
    // instance or hostname? (DNS names are case-insensitive and appear as
    // plain label text in the payload, so substring matching is fine here.)
    final String probe = String.fromCharCodes(
      data.map((int b) => b >= 0x41 && b <= 0x5A ? b + 0x20 : b),
    );
    final bool forUs = probe.contains('salu-remote') ||
        probe.contains(instanceLabel) ||
        probe.contains('salu');
    if (!forUs) return;

    try {
      socket.send(buildAnswer(), datagram.address, datagram.port);
    } catch (error) {
      debugPrint('[SALU/mdns] reply failed: $error');
    }
  }

  // ── DNS packet construction ────────────────────────────────────────────

  Uint8List buildAnswer() {
    final List<Uint8List> records = <Uint8List>[
      // PTR — "there is a SALU remote service on this machine".
      _answer(_serviceFqdn, type: 12, rdata: _nameBytes(_instanceFqdn)),
      // SRV — host + port.
      _answer(
        _instanceFqdn,
        type: 33,
        rdata: <int>[
          0, 0, // priority
          0, 0, // weight
          (port >> 8) & 0xFF, port & 0xFF,
          ..._nameBytes(_hostFqdn),
        ],
      ),
      // TXT — small metadata blob for the companion app.
      _answer(
        _instanceFqdn,
        type: 16,
        rdata: _txtBytes(<String>[
          'name=SALU',
          'player=salu',
          'proto=salu-remote-v1',
        ]),
      ),
      // A — the PC's LAN IPv4 address(es).
      for (final InternetAddress address in _addresses)
        _answer(_hostFqdn, type: 1, rdata: address.rawAddress),
    ];

    // Header: ID 0, response + authoritative, 0 questions, N answers.
    final _ByteWriter out = _ByteWriter()
      ..u16(0) // transaction id
      ..u16(0x8400) // QR=1, AA=1
      ..u16(0) // question count
      ..u16(records.length) // answer count
      ..u16(0) // authority count
      ..u16(0); // additional count
    for (final Uint8List record in records) {
      out.raw(record);
    }
    return out.takeBytes();
  }

  static Uint8List _answer(String name, {required int type, required List<int> rdata}) {
    // CLASS: IN (1) with the top bit set → "cache-flush" (mDNS convention).
    final _ByteWriter w = _ByteWriter()
      ..name(name)
      ..u16(type)
      ..u16(0x8001)
      ..u32(_ttl)
      ..u16(rdata.length)
      ..raw(rdata);
    return w.takeBytes();
  }

  static List<int> _nameBytes(String fqdn) {
    final _ByteWriter w = _ByteWriter()..name(fqdn);
    return w.takeBytes();
  }

  static List<int> _txtBytes(List<String> strings) {
    final List<int> out = <int>[];
    for (final String s in strings) {
      final List<int> bytes = utf8.encode(s);
      final int len = bytes.length > 255 ? 255 : bytes.length;
      out.add(len);
      out.addAll(bytes.take(len));
    }
    return out;
  }
}

/// Tiny big-endian writer — DNS is a very 1987 protocol.
class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void u16(int value) {
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
  }

  void u32(int value) {
    _builder.addByte((value >> 24) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
  }

  void raw(List<int> bytes) => _builder.add(bytes);

  /// Length-prefixed labels, terminated by a zero byte (no name compression).
  void name(String fqdn) {
    for (final String label in fqdn.split('.')) {
      if (label.isEmpty) continue;
      final List<int> bytes = utf8.encode(label);
      if (bytes.isEmpty || bytes.length > 63) continue;
      _builder.addByte(bytes.length);
      _builder.add(bytes);
    }
    _builder.addByte(0);
  }

  Uint8List takeBytes() => _builder.toBytes();
}
