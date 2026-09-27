import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'update_manifest.dart';

/// SALU's NuGet client (updater.md §4) — the WebView2 Connector's upstream.
///
/// Two halves, both testable without the network:
/// * feed queries — `…/v3-flatcontainer/microsoft.web.webview2/index.json`
///   and the `.nupkg` download URL;
/// * `.nupkg` unzipping — a `.nupkg` is a plain ZIP, so the loader DLL is
///   pulled out by a small reader here (STORED + DEFLATE entries, the only
///   two a nupkg ever uses) instead of a new dependency. The ZIP's own
///   CRC-32 is checked on every extracted entry — that is the "verify
///   integrity" step of updater.md §3 compressed into the read itself.
///
/// HTTP is injected ([fetchText] / callers stream the package bytes), so
/// this file never opens a socket of its own.
class NugetClient {
  NugetClient({required this.fetchText});

  /// How feed documents are fetched. Production wires an HTTP GET that
  /// adds the User-Agent header GitHub/NuGet expect; tests hand back
  /// canned JSON.
  final Future<String> Function(Uri url) fetchText;

  /// The package id (lowercase — the flat container URL rules).
  static const String packageId = 'microsoft.web.webview2';

  /// Where the x64 loader lives inside the `.nupkg` (updater.md §4).
  static const String dllEntryPath = 'build/native/x64/WebView2Loader.dll';

  /// `GET …/v3-flatcontainer/microsoft.web.webview2/index.json`.
  static Uri indexUrl() {
    return Uri.parse('https://api.nuget.org/v3-flatcontainer/$packageId/index.json');
  }

  /// The `.nupkg` download URL for [version] (updater.md §4, step 2).
  /// Flat-container paths are lowercased — package id and version both.
  static Uri packageUrlFor(String version) {
    final String v = version.toLowerCase();
    return Uri.parse(
      'https://api.nuget.org/v3-flatcontainer/$packageId/$v/$packageId.$v.nupkg',
    );
  }

  /// Highest stable version from an index document's `versions` list
  /// (updater.md §4, step 1: "filters out pre-release tags … and selects
  /// the highest stable version string"). Pure — takes the document text
  /// so tests never touch HTTP. `null` = empty or unparseable feed.
  ///
  /// "Highest" is computed, not "last": the feed is published in
  /// registration order, which is usually ascending — but a republished
  /// older build would break a take-the-last-one reader.
  static String? pickHighestStable(String indexJson) {
    try {
      final Object? doc = jsonDecode(indexJson);
      if (doc is! Map<String, Object?>) return null;
      final Object? raw = doc['versions'];
      if (raw is! List<Object?>) return null;
      String? best;
      for (final Object? v in raw) {
        if (v is! String || v.isEmpty) continue;
        // Pre-release tags (`-prerelease`, `-rc.1`, …) never qualify.
        if (v.contains('-')) continue;
        if (best == null || compareUpdateVersions(v, best) > 0) best = v;
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Asks NuGet for the newest stable `Microsoft.Web.WebView2` version.
  /// Throws when the feed cannot be read — the coordinator turns that
  /// into the quiet offline state (updater.md §8, State 4).
  Future<String?> latestStableVersion() async {
    final String body = await fetchText(indexUrl());
    return pickHighestStable(body);
  }

  /// Pulls `build/native/x64/WebView2Loader.dll` out of a downloaded
  /// `.nupkg`. `null` = the package is corrupt, encrypted, or carries no
  /// x64 loader (CRC mismatch included) — never a partial DLL.
  static List<int>? extractLoaderDll(List<int> nupkg) {
    return zipReadEntry(nupkg, dllEntryPath);
  }
}

// ── Minimal ZIP reader (the `.nupkg` half) ─────────────────────────────────

/// Reads one entry out of a ZIP archive.
///
/// Only what a `.nupkg` needs: central-directory walk, STORED (0) and
/// DEFLATE (8) methods, encryption refused. [entryPath] matches the full
/// inner path (`build/native/x64/WebView2Loader.dll`), case-insensitively
/// — ZIPs are free with case and NuGet is not picky about it.
///
/// Returns `null` for missing entries and for anything damaged: truncated
/// data, unknown compression method, encryption, or a CRC-32 mismatch
/// against the central directory.
List<int>? zipReadEntry(List<int> archive, String entryPath) {
  if (archive.length < 22) return null;
  final ByteData data = ByteData.view(
    archive is Uint8List
        ? archive.buffer
        : Uint8List.fromList(archive).buffer,
    archive is Uint8List ? archive.offsetInBytes : 0,
  );

  // ── End Of Central Directory: scan back over the 64 KB comment window.
  int eocd = -1;
  final int floor = archive.length - 22 - 0xFFFF;
  for (int i = archive.length - 22; i >= (floor < 0 ? 0 : floor); i--) {
    if (_u32(data, i) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return null;
  final int entryCount = _u16(data, eocd + 10);
  int cursor = _u32(data, eocd + 20);
  if (cursor < 0 || cursor + 46 > archive.length) return null;

  final String want = entryPath.replaceAll('\\', '/').toLowerCase();
  for (int e = 0; e < entryCount; e++) {
    if (cursor + 46 > archive.length) return null;
    if (_u32(data, cursor) != 0x02014b50) return null;
    final int flags = _u16(data, cursor + 8);
    final int method = _u16(data, cursor + 10);
    final int crc = _u32(data, cursor + 16);
    final int compressed = _u32(data, cursor + 20);
    final int uncompressed = _u32(data, cursor + 24);
    final int nameLen = _u16(data, cursor + 28);
    final int extraLen = _u16(data, cursor + 30);
    final int commentLen = _u16(data, cursor + 32);
    final int localOffset = _u32(data, cursor + 42);
    if (cursor + 46 + nameLen > archive.length) return null;
    final String name = String.fromCharCodes(Uint8List.view(
      data.buffer,
      data.offsetInBytes + cursor + 46,
      nameLen,
    ));

    if (name.replaceAll('\\', '/').toLowerCase() == want) {
      return _zipExtract(
        data: data,
        archiveLength: archive.length,
        localOffset: localOffset,
        flags: flags,
        method: method,
        crc: crc,
        compressed: compressed,
        uncompressed: uncompressed,
      );
    }
    cursor += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}

List<int>? _zipExtract({
  required ByteData data,
  required int archiveLength,
  required int localOffset,
  required int flags,
  required int method,
  required int crc,
  required int compressed,
  required int uncompressed,
}) {
  // Bit 0 = encrypted entry. Never decrypt, never guess.
  if ((flags & 0x1) != 0) return null;
  // ZIP64 sentinels — a nupkg is never this big; refuse rather than wrap.
  if (compressed < 0 || uncompressed < 0) return null;
  if (localOffset < 0 || localOffset + 30 > archiveLength) return null;
  if (_u32(data, localOffset) != 0x04034b50) return null;
  final int nameLen = _u16(data, localOffset + 26);
  final int extraLen = _u16(data, localOffset + 28);
  final int start = localOffset + 30 + nameLen + extraLen;
  if (start < 0 || start + compressed > archiveLength) return null;
  final Uint8List raw = Uint8List.view(
    data.buffer,
    data.offsetInBytes + start,
    compressed,
  );

  List<int>? out;
  if (method == 0) {
    // Stored — the bytes are the bytes.
    out = raw;
  } else if (method == 8) {
    // Deflate — raw DEFLATE stream, no zlib wrapper.
    try {
      out = const ZLibDecoder(raw: true).convert(raw);
    } catch (_) {
      return null;
    }
  } else {
    return null;
  }
  if (out.length != uncompressed) return null;
  // The archive's own checksum — corruption that survives a length check
  // dies here.
  if (crc32Of(out) != crc) return null;
  return out;
}

int _u16(ByteData d, int o) {
  if (o < 0 || o + 2 > d.lengthInBytes) return -1;
  return d.getUint16(o, Endian.little);
}

int _u32(ByteData d, int o) {
  if (o < 0 || o + 4 > d.lengthInBytes) return -1;
  return d.getUint32(o, Endian.little);
}

/// IEEE CRC-32 (the checksum ZIP itself stores). Exported for the tests'
/// archive builder and any future checksum work.
int crc32Of(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final List<int> _crcTable = _makeCrcTable();

List<int> _makeCrcTable() {
  final List<int> table = List<int>.filled(256, 0);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}
