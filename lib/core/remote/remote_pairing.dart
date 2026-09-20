import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ambiguous glyphs are deliberately absent. Eight characters provide 40
/// bits of entropy while remaining easy to read over a video call.
const String remotePairingAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

String generatePairingCode({math.Random? random}) {
  final math.Random source = random ?? math.Random.secure();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 8; i++) {
    out.write(remotePairingAlphabet[source.nextInt(remotePairingAlphabet.length)]);
  }
  return out.toString();
}

String formatPairingCode(String code) {
  final String clean = code.replaceAll('-', '').trim().toUpperCase();
  if (clean.length <= 4) return clean;
  return '${clean.substring(0, 4)}-${clean.substring(4)}';
}

/// Case- and separator-insensitive form of a pairing code.
///
/// Everything that is not a letter or a digit is dropped, so `7K4M-QP2X`,
/// `7k4m qp2x` and the QR's `7K4MQP2X` are one and the same code. Two bugs
/// lived in the previous one-liner and both looked like "the app is flaky":
///   * `r'[-\\s]'` is a *raw* string, so the regex saw `-`, a backslash and
///     the letter `s` — it never stripped whitespace, and it ate the `S` out
///     of any code containing one (about one code in thirty-one could never
///     be accepted, and it looked random);
///   * nothing else was tolerated, so a single stray character typed on a
///     phone keyboard failed the whole pairing with a misleading `bad_code`.
String normalizePairingCode(String code) =>
    code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

String generateDeviceToken({math.Random? random}) {
  final math.Random source = random ?? math.Random.secure();
  final List<int> bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String hashDeviceToken(String token) => sha256.convert(utf8.encode(token)).toString();

@immutable
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.tokenHash,
    required this.addedAt,
    this.lastSeenAt,
    this.online = false,
    this.control = false,
  });

  final String id;
  final String name;
  final String platform;
  final String tokenHash;
  final DateTime addedAt;
  final DateTime? lastSeenAt;
  final bool online;
  final bool control;

  RemoteDevice copyWith({
    String? name,
    String? platform,
    String? tokenHash,
    DateTime? addedAt,
    DateTime? lastSeenAt,
    bool? online,
    bool? control,
  }) => RemoteDevice(
        id: id,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        tokenHash: tokenHash ?? this.tokenHash,
        addedAt: addedAt ?? this.addedAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        online: online ?? this.online,
        control: control ?? this.control,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        'tokenHash': tokenHash,
        'addedAt': addedAt.toIso8601String(),
        if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
      };

  Map<String, Object?> toPublicJson() => <String, Object?>{
        'id': id,
        'name': name,
        'online': online,
        'control': control,
      };

  static RemoteDevice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String? id = raw['id'] as String?;
    final String? name = raw['name'] as String?;
    final String? tokenHash = raw['tokenHash'] as String?;
    if (id == null || id.isEmpty || name == null || tokenHash == null) {
      return null;
    }
    DateTime parseDate(Object? value, DateTime fallback) =>
        DateTime.tryParse(value as String? ?? '') ?? fallback;
    final DateTime now = DateTime.now();
    return RemoteDevice(
      id: id,
      name: name,
      platform: raw['platform'] as String? ?? 'unknown',
      tokenHash: tokenHash,
      addedAt: parseDate(raw['addedAt'], now),
      lastSeenAt: raw['lastSeenAt'] is String
          ? DateTime.tryParse(raw['lastSeenAt'] as String)
          : null,
    );
  }
}

/// Owns only the remembered-device hashes. Plain tokens never enter prefs.
class RemoteDeviceStore {
  RemoteDeviceStore({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String preferencesKey = 'remote_devices';
  SharedPreferences? _preferences;
  final List<RemoteDevice> _devices = <RemoteDevice>[];

  List<RemoteDevice> get devices => List<RemoteDevice>.unmodifiable(_devices);

  Future<void> load() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final List<String> encoded = <String>[];
      final String? jsonList = _preferences!.getString(preferencesKey);
      if (jsonList != null) {
        final Object? decoded = jsonDecode(jsonList);
        if (decoded is List) {
          encoded.addAll(decoded.whereType<Map>().map((Map value) => jsonEncode(value)));
        }
      } else {
        encoded.addAll(_preferences!.getStringList(preferencesKey) ?? const <String>[]);
      }
      _devices
        ..clear()
        ..addAll(encoded.map((String value) {
          try {
            return RemoteDevice.fromJson(jsonDecode(value));
          } catch (_) {
            return null;
          }
        }).whereType<RemoteDevice>());
    } catch (_) {
      _devices.clear();
    }
  }

  RemoteDevice? find(String id) {
    for (final RemoteDevice device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  RemoteDevice? findByToken(String token) {
    final String hash = hashDeviceToken(token);
    for (final RemoteDevice device in _devices) {
      if (device.tokenHash == hash) return device;
    }
    return null;
  }

  Future<RemoteDevice> remember({
    required String id,
    required String name,
    required String platform,
    required String token,
  }) async {
    final RemoteDevice? old = find(id);
    final RemoteDevice device = RemoteDevice(
      id: id,
      name: name.trim().isEmpty ? 'Phone' : name.trim(),
      platform: platform,
      tokenHash: hashDeviceToken(token),
      addedAt: old?.addedAt ?? DateTime.now(),
      lastSeenAt: DateTime.now(),
      online: old?.online ?? false,
      control: old?.control ?? false,
    );
    if (old == null) {
      _devices.add(device);
    } else {
      _devices[_devices.indexOf(old)] = device;
    }
    await _save();
    return device;
  }

  Future<void> touch(String id, {String? name, String? platform}) async {
    final RemoteDevice? old = find(id);
    if (old == null) return;
    _devices[_devices.indexOf(old)] = old.copyWith(
      name: name == null || name.trim().isEmpty ? null : name.trim(),
      platform: platform,
      lastSeenAt: DateTime.now(),
    );
    await _save();
  }

  void setOnline(String id, bool online) {
    final RemoteDevice? old = find(id);
    if (old == null) return;
    _devices[_devices.indexOf(old)] = old.copyWith(online: online);
  }

  void setControl(String? id) {
    for (int i = 0; i < _devices.length; i++) {
      final RemoteDevice item = _devices[i];
      _devices[i] = item.copyWith(control: item.id == id);
    }
  }

  Future<void> forget(String id) async {
    _devices.removeWhere((RemoteDevice device) => device.id == id);
    await _save();
  }

  Future<void> _save() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setString(
        preferencesKey,
        jsonEncode(_devices.map((RemoteDevice d) => d.toJson()).toList()),
      );
    } catch (_) {}
  }
}

/// Pairing-code lifecycle. The service changes the code only through these
/// explicit events, never while a QR dialog is visible.
class RemotePairing {
  RemotePairing({math.Random? random}) : _random = random;

  final math.Random? _random;
  String? _code;
  DateTime? _createdAt;
  bool _panelOpen = false;

  String get code => _code ??= _newCode();
  DateTime get createdAt => _createdAt ??= DateTime.now();
  bool get panelOpen => _panelOpen;

  String _newCode() {
    _createdAt = DateTime.now();
    return generatePairingCode(random: _random);
  }

  void openPanel() {
    _panelOpen = true;
    // A fresh process/session always has a fresh code, but reopening an
    // already visible panel must not rotate it.
    _code ??= _newCode();
  }

  void closePanel() {
    _panelOpen = false;
    rotate();
  }

  void rotate() {
    _code = _newCode();
  }

  bool accepts(String candidate) =>
      normalizePairingCode(candidate) == normalizePairingCode(code);

  void pairedSuccessfully() {
    // A successful pairing invalidates the one-time code even when the QR
    // dialog remains open.
    rotate();
  }
}
