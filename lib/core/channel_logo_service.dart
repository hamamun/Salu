import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Provider logo images (playlist_imp.md §10.4 · point 2 Final).
///
/// Fetches a playlist-supplied `tvg-logo` address lazily — only rows the
/// panel actually builds ever ask — into a bounded RAM-only LRU cache.
/// No disk, no prefetch, no retry loop:
///
/// - HTTP(S) network images only, plus local files named by a local
///   playlist; anything else resolves to "no image".
/// - One in-flight request per address (identical rows share it), at most
///   [maxConcurrent] concurrent fetches, [fetchTimeout] per request and
///   [maxImageBytes] per image — a hostile 200 MB "logo" is dropped, not
///   decoded. Results bind to the requested address, never a recycled
///   row index, so fast scrolling cannot mis-attach an image.
/// - [cancelStale] aborts in-flight network work when the source changes
///   (a new load, a clear). The cache itself is address-keyed and stays.
/// - A missing/invalid/failed logo is just an empty slot: no spinner, no
///   error mark, and never the failure toast or the channel skip — a logo
///   failure is not a channel failure.
/// - Logo addresses may carry credentials: they are never rendered or
///   logged (§10.10e), and no playlist credentials are ever forwarded —
///   the request carries only the logo address itself.
///
/// Budgets below are implementation defaults, verified in M-10.
class ChannelLogoService {
  ChannelLogoService._internal();

  /// The one and only logo cache for the whole app.
  static final ChannelLogoService instance = ChannelLogoService._internal();

  /// Logo images kept in RAM at most (LRU-evicted past either bound).
  static const int maxEntries = 200;

  /// Decoded-transfer bytes kept at most (~a screen of small artworks).
  static const int maxBytes = 32 * 1024 * 1024;

  /// A single image transfer past this is dropped, not decoded.
  static const int maxImageBytes = 512 * 1024;

  /// Concurrent network fetches at most (playback never waits for these).
  static const int maxConcurrent = 6;

  /// One request may take this long (connect + idle-between-chunks).
  static const Duration fetchTimeout = Duration(seconds: 10);

  final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  int _cachedBytes = 0;

  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};

  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  HttpClient? _client;

  /// Entries currently cached (M-10 diagnostics).
  int get cachedEntries => _cache.length;

  /// Transfer bytes currently cached (M-10 diagnostics).
  int get cachedBytes => _cachedBytes;
  /// In-flight fetches right now (M-10 diagnostics).
  int get inflightCount => _inflight.length;

  /// Image bytes for [logoUrl], or `null` for "no image" (missing,
  /// invalid, failed, over budget — all the same empty slot, by design).
  /// Never throws; never logs the address.
  Future<Uint8List?> fetch(String? logoUrl) {
    if (logoUrl == null || logoUrl.isEmpty) return Future<Uint8List?>.value();
    final Uint8List? hit = _cache.remove(logoUrl);
    if (hit != null) {
      // Reinsert: the hit is the most-recently-used entry again.
      _cache[logoUrl] = hit;
      return Future<Uint8List?>.value(hit);
    }
    return _inflight.putIfAbsent(logoUrl, () => _load(logoUrl));
  }

  /// Aborts in-flight network fetches (a new load, a clear, shutdown).
  /// Already-cached bytes stay — they are address-keyed, bounded, and
  /// valid for any playlist that names them.
  void cancelStale() {
    _client?.close(force: true);
    _client = null;
  }

  /// Empties the cache (tests only).
  @visibleForTesting
  void debugClear() {
    _cache.clear();
    _cachedBytes = 0;
  }

  Future<Uint8List?> _load(String logoUrl) async {
    await _acquire();
    try {
      final Uint8List? bytes = _isNetwork(logoUrl)
          ? await _fetchNetwork(logoUrl)
          : await _readFile(logoUrl);
      if (bytes != null && bytes.isNotEmpty) _store(logoUrl, bytes);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _inflight.remove(logoUrl);
      _release();
    }
  }

  static bool _isNetwork(String s) {
    final String head = s.length >= 8
        ? s.substring(0, 8).toLowerCase()
        : s.toLowerCase();
    return head.startsWith('https://') || head.startsWith('http://');
  }

  Future<Uint8List?> _fetchNetwork(String logoUrl) async {
    final HttpClient client = _client ??= HttpClient()
      ..connectionTimeout = fetchTimeout
      ..autoUncompress = true;
    final Uri uri = Uri.parse(logoUrl);
    final HttpClientRequest request = await client
        .getUrl(uri)
        .timeout(fetchTimeout);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
    final HttpClientResponse response =
        await request.close().timeout(fetchTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    if (response.contentLength > maxImageBytes) {
      await response.drain<void>();
      return null;
    }
    final List<int> all = <int>[];
    await for (final List<int> chunk
        in response.timeout(fetchTimeout)) {
      all.addAll(chunk);
      if (all.length > maxImageBytes) return null;
    }
    if (all.isEmpty) return null;
    return Uint8List.fromList(all);
  }

  Future<Uint8List?> _readFile(String logoUrl) async {
    try {
      final File file = File(logoUrl);
      final int length = await file.length();
      if (length <= 0 || length > maxImageBytes) return null;
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length > maxImageBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _store(String logoUrl, Uint8List bytes) {
    final Uint8List? replaced = _cache.remove(logoUrl);
    if (replaced != null) _cachedBytes -= replaced.length;
    _cache[logoUrl] = bytes;
    _cachedBytes += bytes.length;
    while ((_cache.length > maxEntries || _cachedBytes > maxBytes) &&
        _cache.isNotEmpty) {
      final String oldest = _cache.keys.first;
      final Uint8List? evicted = _cache.remove(oldest);
      if (evicted != null) _cachedBytes -= evicted.length;
    }
    if (_cachedBytes < 0) _cachedBytes = 0;
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final Completer<void> waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      final Completer<void> waiter = _waiters.removeAt(0);
      if (!waiter.isCompleted) waiter.complete();
      return;
    }
    if (_active > 0) _active--;
  }
}
