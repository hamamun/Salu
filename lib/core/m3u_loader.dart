import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../ui/osd/osd_controller.dart';
import 'channel_service.dart';
import 'favourites_service.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// The m3u/IPTV load path (playlist_imp.md §10 · M-1/M-2/M-3).
///
///   · SALU fetches & parses the list ITSELF — a playlist URL is never
///     handed to mpv (M2).
///   · The byte stream is capped at 64 MB (M14); parsing runs OFF the
///     UI thread (M13) and hands rows back progressively (~200-row
///     chunks) so a thousand-channel list paints before parse ends.
///   · Every entry becomes a QueueItem with a precomputed lowercase
///     search key over name + group ONLY (M15 — never the URL, which can
///     carry credentials).
class M3uLoader {
  M3uLoader._();

  static final M3uLoader instance = M3uLoader._();

  /// The byte ceiling for a fetched playlist (M14).
  static const int maxBytes = 64 * 1024 * 1024;

  /// Whether [target] routes here: an `.m3u`/`.m3u8` path or URL
  /// (extension - routed before fetching; a non-mobile case is a plain
  /// media stream and still goes to the engine).
  static bool looksLikePlaylist(String target) {
    final String t = target.trim();
    if (t.isEmpty) return false;
    final String path = t.split('?').first.toLowerCase();
    return path.endsWith('.m3u') || path.endsWith('.m3u8');
  }

  /// The playlist key: URL → HOST (providers rotate credentials, M12);
  /// local file → its path.
  static String hostOf(String source) {
    final Uri? uri = Uri.tryParse(source);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return uri.host;
    }
    return 'file:$source';
  }

  /// Fetches, parses and OPENS a channel list from [source] (a URL or a
  /// local file path). Failures are plain transient toasts; a good list
  /// just starts playing its first channel.
  Future<void> open(String source) async {
    final String src = source.trim();
    if (src.isEmpty) return;

    final OsdLoadingCard loading = OsdLoadingCard();
    final OsdController osd = OsdController.instance;
    osd.show(loading);
    // M42 — the whole fetch/parse reuses the live shimmer on both chrome
    // surfaces (timeline + hairline) via this one flag.
    PlayerService.instance.playlistLoading.value = true;

    List<Uint8List> chunks;
    try {
      chunks = <Uint8List>[await _readBytes(src)];
    } catch (e) {
      osd.dismissCard(loading);
      PlayerService.instance.playlistLoading.value = false;
      _failToast(e);
      return;
    }
    final Uint8List bytes = chunks.first;
    if (bytes.lengthInBytes >= maxBytes) {
      osd.dismissCard(loading);
      PlayerService.instance.playlistLoading.value = false;
      _failToast('Playlist exceeds 64 MB');
      return;
    }

    final ReceivePort port = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(_parseWorker, <Object>[
        bytes,
        port.sendPort,
        src,
      ]);
    } catch (_) {
      port.close();
      osd.dismissCard(loading);
      PlayerService.instance.playlistLoading.value = false;
      _failToast('Playlist failed to load');
      return;
    }

    final List<QueueItem> items = <QueueItem>[];
    bool announcedBases = false;
    String? failure;
    await for (final Object? message in port) {
      if (message is List<QueueItem>) {
        items.addAll(message);
        loading.count.value = items.length;
        // Progressive mount: first chunk opens the list so rows paint
        // (~200 rows, usually before the parse finishes); later chunks
        // just append to the queue's VALUE — no re-open, no view reset.
        if (!announcedBases && items.isNotEmpty) {
          announcedBases = true;
          ChannelService.instance.notePlaylistHost(hostOf(src));
          FavouritesService.instance.setPlaylistHost(hostOf(src));
          await PlayerService.instance.openChannelList(items, startIndex: 0);
        } else if (items.length > QueueService.instance.items.value.length) {
          QueueService.instance.items.value =
              List<QueueItem>.unmodifiable(items);
        }
      } else if (message is _ParseDone) {
        if (items.isNotEmpty &&
            QueueService.instance.items.value.length != items.length) {
          QueueService.instance.items.value =
              List<QueueItem>.unmodifiable(items);
        }
        break;
      } else if (message is _ParseFailed) {
        failure = message.reason;
        break;
      }
    }
    worker.kill();
    port.close();
    PlayerService.instance.playlistLoading.value = false;

    osd.dismissCard(loading);
    if (failure != null) {
      _failToast(failure);
      return;
    }
    if (items.isEmpty) {
      _failToast('Playlist is empty');
      return;
    }
    debugPrint('[SALU] m3u loaded: ${items.length} entries from $src');
  }

  // ── Fetching (byte-capped, streamed) ────────────────────────────────

  Future<Uint8List> _readBytes(String src) async {
    // Local file.
    if (!src.startsWith('http://') && !src.startsWith('https://')) {
      final File file = File(src);
      if (!await file.exists()) throw 'Playlist not found';
      final int size = await file.length();
      if (size > maxBytes) return Uint8List(maxBytes);
      return file.readAsBytes();
    }
    // URL — streamed so the 64 MB ceiling never materialises a bigger
    // buffer than allowed.
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(src));
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw 'Playlist answered ${response.statusCode}';
      }
      final BytesBuilder builder = BytesBuilder();
      await for (final List<int> chunk in response) {
        builder.add(chunk);
        if (builder.length >= maxBytes) break; // ceiling — stop reading
      }
      return builder.toBytes();
    } on SocketException {
      throw 'Playlist unreachable';
    } finally {
      client.close();
    }
  }

  // ── The worker isolate (M13) ─────────────────────────────────────────

  static void _parseWorker(List<Object> args) {
    final Uint8List bytes = args[0] as Uint8List;
    final SendPort port = args[1] as SendPort;
    final String base = args[2] as String;
    try {
      final String text = utf8.decode(bytes, allowMalformed: true);
      _parseBody(text, base, port);
      port.send(const _ParseDone());
    } catch (e) {
      port.send(const _ParseFailed('Playlist failed to parse'));
    }
  }

  /// Sends completed items back in ~200-row chunks (progressive rows).
  static void _parseBody(String text, String base, SendPort port) {
    final Uri? baseUri =
        base.startsWith('http') ? Uri.tryParse(base) : null;
    final String baseDir = base.startsWith('http')
        ? ''
        : base.substring(
            0,
            base.length - (base.split(RegExp(r'[\\/]')).last.length),
          );

    List<QueueItem> batch = <QueueItem>[];
    void flush() {
      if (batch.isEmpty) return;
      port.send(batch);
      batch = <QueueItem>[];
    }

    String? pendingAttrsBlock;
    String? pendingName;

    // M44 — intern the three tag fields at parse time: 50 000 entries
    // carry ~28 unique values, not 150 000 distinct strings.
    final Map<String, String> internPool = <String, String>{};
    String? internTag(String? v) {
      if (v == null) return null;
      return internPool.putIfAbsent(v, () => v);
    }

    void commit(String rawUrl) {
      final String url = rawUrl.trim();
      if (url.isEmpty || url.startsWith('#')) return;
      String resolved = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        if (baseUri != null) {
          resolved = baseUri.resolve(url).toString();
        } else if (File(url).existsSync()) {
          resolved = url;
        } else if (baseDir.isNotEmpty) {
          resolved = '$baseDir$url';
        }
      }
      final Map<String, String> attrs =
          pendingAttrsBlock == null
              ? const <String, String>{}
              : _parseAttributes(pendingAttrsBlock!);
      String? group = attrs['group-title']?.trim();
      if (group == null || group.isEmpty) group = null;
      group = internTag(group);
      final String? language = internTag(_emptyToNull(attrs['tvg-language']));
      final String? country = internTag(_emptyToNull(attrs['tvg-country']));
      // M16: the provider's channel number, or NOTHING — a channel
      // without one leaves the slot empty (never 0, never an invented
      // ordinal, never "LIVE").
      final String? chno = _emptyToNull(attrs['channel-number'] ??
          attrs['tvg-chno']);
      final String name = pendingName ?? MediaUtils.displayName(resolved);

      final String searchKey = ('$name|${group ?? ''}').toLowerCase();
      batch.add(QueueItem(
        resolved,
        name: name,
        group: group,
        language: language,
        country: country,
        chno: chno,
        tvgId: _emptyToNull(attrs['tvg-id']),
        searchKey: searchKey,
      ));
      pendingAttrsBlock = null;
      pendingName = null;
      if (batch.length >= 200) flush();
    }

    final List<String> lines = text.split(RegExp(r'\r\n|\r|\n'));
    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final String tag = line.toUpperCase();
        if (tag.startsWith('#EXTINF:')) {
          final int splitAt = _firstCommaOutsideQuotes(line.substring(8));
          if (splitAt >= 0) {
            pendingAttrsBlock = line.substring(8, splitAt);
            pendingName = line.substring(splitAt + 1).trim();
            if (pendingName!.isEmpty) pendingName = null;
          } else {
            pendingAttrsBlock = line.substring(8);
            pendingName = null;
          }
        } else if (tag.startsWith('#EXTGRP:')) {
          // Legacy group marker → maps onto `group-title` unless the
          // EXTINF itself carries one. EXTGRP usually appears BETWEEN
          // EXTINF and the URL, so append it to the pending EXTINF attrs
          // instead of requiring the attr block to be absent.
          final String g = line.substring(8).trim();
          if (g.isNotEmpty &&
              !_hasAttribute(pendingAttrsBlock, 'group-title')) {
            final String safe = g
                .replaceAll('"', '')
                .replaceAll("'", '')
                .trim();
            if (safe.isNotEmpty) {
              pendingAttrsBlock = <String>[
                if (pendingAttrsBlock != null &&
                    pendingAttrsBlock!.trim().isNotEmpty)
                  pendingAttrsBlock!.trim(),
                'group-title="$safe"',
              ].join(' ');
            }
          }
        }
        continue;
      }
      commit(line);
    }
    flush();
  }

  static String? _emptyToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  /// The attribute block ends at the first comma OUTSIDE quotes — quoted
  /// values are allowed to carry commas. Providers use both quote types.
  static int _firstCommaOutsideQuotes(String s) {
    String? quote;
    bool maybeQuotedValue = false;
    for (int i = 0; i < s.length; i++) {
      final String c = s[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '=') {
        maybeQuotedValue = true;
        continue;
      }
      if (maybeQuotedValue && c.trim().isEmpty) continue;
      if (maybeQuotedValue && (c == '"' || c == "'")) {
        quote = c;
        maybeQuotedValue = false;
        continue;
      }
      maybeQuotedValue = false;
      if (c == ',') return i;
    }
    return -1;
  }

  static bool _hasAttribute(String? block, String name) {
    if (block == null || block.trim().isEmpty) return false;
    final String want = name.toLowerCase();
    for (final RegExpMatch m in _attrRe.allMatches(block)) {
      if (m.group(1)?.toLowerCase() != want) continue;
      final String value = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      if (value.trim().isNotEmpty) return true;
    }
    return false;
  }

  // Attribute values in IPTV lists are not as clean as the spec examples:
  // double quoted, single quoted and bare values all appear in the wild,
  // and provider key casing is inconsistent. Normalize keys to lowercase
  // so group-title/tvg-language/tvg-country are actually seen.
  static final RegExp _attrRe = RegExp(
    r'''([a-zA-Z0-9\-_]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))''',
  );

  static Map<String, String> _parseAttributes(String block) {
    final Map<String, String> out = <String, String>{};
    for (final RegExpMatch m in _attrRe.allMatches(block)) {
      out[m.group(1)!.toLowerCase()] =
          m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
    }
    return out;
  }

  void _failToast(Object reason) {
    OsdController.instance.show(OsdTransportCard(
      mark: OsdMark.next,
      text: reason is String ? reason : 'Playlist failed to load',
    ));
  }
}

class _ParseDone {
  const _ParseDone();
}

class _ParseFailed {
  const _ParseFailed(this.reason);
  final String reason;
}
