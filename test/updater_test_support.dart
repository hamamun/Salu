import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:salu/core/updater/nuget_client.dart';

/// Test scaffolding for the updater suite — the two binary shapes the
/// pipeline reads, built in memory:
///
/// * [buildZipArchive] — real ZIP bytes (stored and/or deflated), so the
///   `.nupkg` reader is exercised against a faithful container instead of
///   a mock;
/// * [fakePeImage] — synthetic PE headers, enough for the x64 architecture
///   guard (updater.md §9) without shipping binaries in the repo.

void _put16(List<int> out, int v) {
  out.add(v & 0xFF);
  out.add((v >> 8) & 0xFF);
}

void _put32(List<int> out, int v) {
  out.add(v & 0xFF);
  out.add((v >> 8) & 0xFF);
  out.add((v >> 16) & 0xFF);
  out.add((v >> 24) & 0xFF);
}

/// Builds a ZIP archive of [entries] (inner path → bytes). Entries compress
/// with raw DEFLATE unless [deflate] is false (STORED) or the payload is
/// empty. The central directory carries real CRC-32s, so the reader's
/// integrity check has something honest to check.
List<int> buildZipArchive(Map<String, List<int>> entries, {bool deflate = true}) {
  final List<int> bytes = <int>[];
  final List<int> central = <int>[];
  int count = 0;
  entries.forEach((String name, List<int> data) {
    final List<int> nameBytes = name.codeUnits;
    final int crc = crc32Of(data);
    final bool compress = deflate && data.isNotEmpty;
    final List<int> payload =
        compress ? const ZLibEncoder(raw: true).convert(data) : data;
    final int method = compress ? 8 : 0;
    final int localOffset = bytes.length;

    // ── Local file header. ──────────────────────────────────────────────
    _put32(bytes, 0x04034b50);
    _put16(bytes, 20);
    _put16(bytes, 0); // flags
    _put16(bytes, method);
    _put16(bytes, 0); // time
    _put16(bytes, 0); // date
    _put32(bytes, crc);
    _put32(bytes, payload.length);
    _put32(bytes, data.length);
    _put16(bytes, nameBytes.length);
    _put16(bytes, 0); // extra
    bytes.addAll(nameBytes);
    bytes.addAll(payload);

    // ── Central directory entry. ────────────────────────────────────────
    _put32(central, 0x02014b50);
    _put16(central, 20); // version made by
    _put16(central, 20); // version needed
    _put16(central, 0); // flags
    _put16(central, method);
    _put16(central, 0); // time
    _put16(central, 0); // date
    _put32(central, crc);
    _put32(central, payload.length);
    _put32(central, data.length);
    _put16(central, nameBytes.length);
    _put16(central, 0); // extra
    _put16(central, 0); // comment
    _put16(central, 0); // disk start
    _put16(central, 0); // internal attrs
    _put32(central, 0); // external attrs
    _put32(central, localOffset);
    central.addAll(nameBytes);
    count++;
  });

  final int cdOffset = bytes.length;
  bytes.addAll(central);

  // ── End Of Central Directory. ─────────────────────────────────────────
  _put32(bytes, 0x06054b50);
  _put16(bytes, 0); // this disk
  _put16(bytes, 0); // cd disk
  _put16(bytes, count);
  _put16(bytes, count);
  _put32(bytes, central.length);
  _put32(bytes, cdOffset);
  _put16(bytes, 0); // comment length
  return bytes;
}

/// A synthetic PE image — just what `isX64PeImage` reads: `MZ`, the
/// `e_lfanew` pointer, `PE\0\0`, and the machine field. [machine] defaults
/// to `0x8664` (x64); pass `0x014c` (x86) or `0xAA64` (ARM64) to build the
/// rejects.
List<int> fakePeImage({
  int machine = 0x8664,
  bool withPeHeader = true,
  int size = 256,
}) {
  final List<int> bytes = List<int>.filled(size, 0);
  bytes[0] = 0x4D; // 'M'
  bytes[1] = 0x5A; // 'Z'
  bytes[0x3C] = 0x80; // e_lfanew → 0x80
  if (withPeHeader) {
    bytes[0x80] = 0x50; // 'P'
    bytes[0x81] = 0x45; // 'E'
    bytes[0x82] = 0x00;
    bytes[0x83] = 0x00;
    bytes[0x84] = machine & 0xFF;
    bytes[0x85] = (machine >> 8) & 0xFF;
  }
  return bytes;
}

/// Hex SHA-256 of [bytes] — the same digest `SHA2-256SUMS` publishes.
String sha256HexOf(List<int> bytes) => sha256.convert(bytes).toString();

/// A `.nupkg`-shaped archive carrying `build/native/x64/WebView2Loader.dll`
/// (plus the decoys a real package has), for the extraction tests.
List<int> buildFakeNupkg({
  List<int>? loaderDll,
  bool includeLoader = true,
  bool deflate = true,
}) {
  final Map<String, List<int>> entries = <String, List<int>>{
    '[Content_Types].xml': '<Types/>'.codeUnits,
    'package/services/metadata/core-properties/x.psmdcp': '<cp/>'.codeUnits,
    if (includeLoader)
      NugetClient.dllEntryPath: loaderDll ?? fakePeImage(),
    'build/native/x86/WebView2Loader.dll': fakePeImage(machine: 0x014c),
  };
  return buildZipArchive(entries, deflate: deflate);
}

/// Byte list convenience for canned "binary" payloads.
List<int> asciiBytes(String s) => Uint8List.fromList(s.codeUnits);
