import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../queue_item.dart';
import 'channel_mapper.dart';
import 'm3u_parser.dart';

/// Streams a channel directory into SALU (playlist_imp.md §10.10b, M-2).
///
/// The fetch (HTTP or file), the UTF-8 decode, the parse and the mapping
/// all run on a **worker isolate**; the UI isolate only ever receives
/// finished [QueueItem] batches. Raw bytes and source text never exist on
/// the UI side, and the worker's buffers die with it — on completion, on
/// failure and on cancellation alike (§10.0 RAM contract).
///
/// Events, in order: zero or more [ChannelBatch]es, then exactly one of
/// [ChannelListDone] · [ChannelListHls] · [ChannelListNotPlaylist] ·
/// [ChannelListFailed]. Cancelling the subscription kills the worker.
///
/// Limits: a **64 MB** byte ceiling on the source (§10.10d — past it the
/// load fails, the same as a dead provider), a connect timeout and an idle
/// timeout between chunks. No source URL is ever placed in an event or a
/// log line (§10.10e).
class ChannelListLoader {
  ChannelListLoader._();

  /// FINAL, point 10: ~5× the 12.9 MB measured at 50 000 channels.
  static const int byteCeiling = 64 * 1024 * 1024;

  /// Rows in the first batch — enough to fill any panel (§10.10b).
  static const int firstBatchRows = 200;

  /// After the first batch, flush at most this often (worker time).
  static const Duration batchInterval = Duration(milliseconds: 40);

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration idleTimeout = Duration(seconds: 30);

  /// Opens [source] — an `http(s)` URL, or a local path when [isFile] —
  /// and streams events. [base] overrides the URI relative entries and
  /// logos resolve against (defaults to the source itself).
  ///
  /// A file is a playlist by its extension, so only its HLS-ness is
  /// sniffed; a URL whose first line is not M3U text ends in
  /// [ChannelListNotPlaylist] (the caller hands it to mpv as a stream).
  static Stream<ChannelListEvent> open(
    String source, {
    required bool isFile,
    Uri? base,
  }) {
    final StreamController<ChannelListEvent> controller =
        StreamController<ChannelListEvent>();
    Isolate? isolate;
    ReceivePort? port;
    bool finished = false;

    void stop() {
      port?.close();
      port = null;
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
    }

    void finish(ChannelListEvent event) {
      if (finished) return;
      finished = true;
      controller.add(event);
      stop();
      unawaited(controller.close());
    }

    controller.onListen = () async {
      final ReceivePort rp = ReceivePort();
      port = rp;
      rp.listen((Object? message) {
        if (finished) return;
        if (message is List<QueueItem>) {
          controller.add(ChannelBatch(message));
        } else if (message is _Done) {
          finish(ChannelListDone(message.total));
        } else if (message is _Hls) {
          finish(const ChannelListHls());
        } else if (message is _NotPlaylist) {
          finish(const ChannelListNotPlaylist());
        } else if (message is _Failed) {
          finish(ChannelListFailed(message.reason));
        } else {
          // An uncaught worker error (delivered via `onError` as a
          // [message, stack] pair) — the load failed; never log it, the
          // text may quote the URL.
          finish(const ChannelListFailed(ChannelListFailure.io));
        }
      });
      final Uri? resolvedBase =
          base ?? (isFile ? _fileUri(source) : Uri.tryParse(source));
      try {
        isolate = await Isolate.spawn<_Job>(
          _work,
          _Job(rp.sendPort, source, isFile, resolvedBase, byteCeiling),
          debugName: 'salu-m3u',
          errorsAreFatal: true,
          onError: rp.sendPort,
        );
      } on Object {
        finish(const ChannelListFailed(ChannelListFailure.io));
        return;
      }
      if (finished) stop(); // cancelled while spawning
    };
    controller.onCancel = () {
      finished = true;
      stop();
    };
    return controller.stream;
  }

  static Uri? _fileUri(String path) {
    try {
      return Uri.file(path, windows: Platform.isWindows);
    } on ArgumentError {
      return null;
    }
  }

  // ── Worker side ──────────────────────────────────────────────────────

  static Future<void> _work(_Job job) async {
    final SendPort reply = job.reply;
    HttpClient? client;
    try {
      final Stream<List<int>> bytes;
      if (job.isFile) {
        bytes = File(job.source).openRead();
      } else {
        client = HttpClient()
          ..connectionTimeout = connectTimeout
          ..autoUncompress = true;
        final Uri uri = Uri.parse(job.source);
        final HttpClientRequest request = await client.getUrl(uri);
        request.followRedirects = true;
        request.maxRedirects = 5;
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        final HttpClientResponse response =
            await request.close().timeout(connectTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          reply.send(const _Failed(ChannelListFailure.network));
          return;
        }
        if (response.contentLength > job.byteCeiling) {
          reply.send(const _Failed(ChannelListFailure.tooLarge));
          return;
        }
        bytes = response;
      }

      final _Outcome outcome = await _parse(
        bytes,
        base: job.base,
        byteCeiling: job.byteCeiling,
        lenient: job.isFile,
        onBatch: (List<QueueItem> batch) => reply.send(batch),
      );
      switch (outcome.kind) {
        case _OutcomeKind.directory:
          reply.send(_Done(outcome.total));
        case _OutcomeKind.hls:
          reply.send(const _Hls());
        case _OutcomeKind.notPlaylist:
          reply.send(const _NotPlaylist());
      }
    } on _TooLarge {
      reply.send(const _Failed(ChannelListFailure.tooLarge));
    } on TimeoutException {
      reply.send(const _Failed(ChannelListFailure.network));
    } on FileSystemException {
      reply.send(const _Failed(ChannelListFailure.io));
    } on IOException {
      // SocketException, HttpException, HandshakeException, …
      reply.send(const _Failed(ChannelListFailure.network));
    } on Object {
      reply.send(const _Failed(ChannelListFailure.io));
    } finally {
      client?.close(force: true);
    }
  }

  /// The pure part — also what the tests drive directly: decode, sniff,
  /// parse, map, batch. Throws [_TooLarge] past [byteCeiling].
  static Future<_Outcome> _parse(
    Stream<List<int>> bytes, {
    required Uri? base,
    required int byteCeiling,
    required bool lenient,
    required void Function(List<QueueItem> batch) onBatch,
    Duration? idle,
  }) async {
    int received = 0;
    final Stream<List<int>> counted = bytes.map((List<int> chunk) {
      received += chunk.length;
      if (received > byteCeiling) throw const _TooLarge();
      return chunk;
    });
    final Stream<String> text = const Utf8Decoder(allowMalformed: true)
        .bind(counted)
        .timeout(idle ?? idleTimeout);

    final M3uDirectoryParser parser = M3uDirectoryParser();
    final ChannelMapper mapper = ChannelMapper(base: base);
    final List<QueueItem> pending = <QueueItem>[];
    int total = 0;
    bool firstSent = false;
    final Stopwatch since = Stopwatch()..start();

    // Sniff buffer: the first non-blank line decides whether a URL's body
    // is a playlist at all. Held only until that decision.
    final StringBuffer head = StringBuffer();
    bool decided = lenient;

    void flush() {
      if (pending.isEmpty) return;
      onBatch(List<QueueItem>.unmodifiable(pending));
      pending.clear();
      firstSent = true;
      since.reset();
    }

    void take(List<M3uEntry> entries) {
      for (final M3uEntry e in entries) {
        final QueueItem? item = mapper.map(e);
        if (item != null) {
          pending.add(item);
          total++;
        }
      }
      if (!firstSent) {
        if (pending.length >= firstBatchRows) flush();
      } else if (since.elapsed >= batchInterval) {
        flush();
      }
    }

    await for (final String chunk in text) {
      if (!decided) {
        head.write(chunk);
        final HeadSniff sniff = sniffHead(head.toString());
        if (sniff == HeadSniff.undecided) continue;
        decided = true;
        if (sniff == HeadSniff.notPlaylist) {
          return const _Outcome(_OutcomeKind.notPlaylist, 0);
        }
        take(parser.feed(head.toString()));
        head.clear();
      } else {
        take(parser.feed(chunk));
      }
      if (parser.isHls) return const _Outcome(_OutcomeKind.hls, 0);
    }
    if (!decided) {
      // The whole body was shorter than one line — judge what there is.
      final HeadSniff sniff = sniffHead(head.toString(), atEnd: true);
      if (sniff == HeadSniff.notPlaylist) {
        return const _Outcome(_OutcomeKind.notPlaylist, 0);
      }
      take(parser.feed(head.toString()));
      head.clear();
    }
    take(parser.finish());
    if (parser.isHls) return const _Outcome(_OutcomeKind.hls, 0);
    flush();
    return _Outcome(_OutcomeKind.directory, total);
  }

  /// Classifies the head of a body by its first non-blank line:
  /// `#EXTM3U` / `#EXTINF` / `#EXTGRP` / `#EXT-X-` → a playlist (HLS is
  /// told apart by the parser as lines flow); anything else → not one
  /// (a stream body, an HTML error page). Undecided until a full line is
  /// available — or 4 KB have passed without one, which no playlist does.
  static HeadSniff sniffHead(String head, {bool atEnd = false}) {
    final int n = head.length;
    int i = (n > 0 && head.codeUnitAt(0) == 0xFEFF) ? 1 : 0;
    while (i < n) {
      final int eol = head.indexOf('\n', i);
      if (eol < 0 && !atEnd) {
        return n - i > 4096 ? HeadSniff.notPlaylist : HeadSniff.undecided;
      }
      final String line =
          (eol < 0 ? head.substring(i) : head.substring(i, eol)).trim();
      if (line.isEmpty) {
        if (eol < 0) break;
        i = eol + 1;
        continue;
      }
      return _isPlaylistLine(line) ? HeadSniff.playlist : HeadSniff.notPlaylist;
    }
    return atEnd ? HeadSniff.notPlaylist : HeadSniff.undecided;
  }

  static bool _isPlaylistLine(String line) {
    if (line.length < 7 || line.codeUnitAt(0) != 0x23) return false;
    final String upper = line.substring(0, 7).toUpperCase();
    return upper == '#EXTM3U' ||
        upper == '#EXTINF' ||
        upper == '#EXTGRP' ||
        upper == '#EXT-X-';
  }

  /// Test seam: runs the decode → parse → map → batch pipeline in the
  /// calling isolate over [bytes] and returns the terminal event.
  static Future<ChannelListEvent> parseForTest(
    Stream<List<int>> bytes, {
    Uri? base,
    int byteCeiling = byteCeiling,
    bool lenient = false,
    Duration idle = const Duration(seconds: 5),
    required void Function(List<QueueItem> batch) onBatch,
  }) async {
    try {
      final _Outcome o = await _parse(
        bytes,
        base: base,
        byteCeiling: byteCeiling,
        lenient: lenient,
        onBatch: onBatch,
        idle: idle,
      );
      switch (o.kind) {
        case _OutcomeKind.directory:
          return ChannelListDone(o.total);
        case _OutcomeKind.hls:
          return const ChannelListHls();
        case _OutcomeKind.notPlaylist:
          return const ChannelListNotPlaylist();
      }
    } on _TooLarge {
      return const ChannelListFailed(ChannelListFailure.tooLarge);
    } on TimeoutException {
      return const ChannelListFailed(ChannelListFailure.network);
    }
  }
}

// ── Events ─────────────────────────────────────────────────────────────

sealed class ChannelListEvent {
  const ChannelListEvent();
}

/// A batch of parsed channels, in playlist order. Unmodifiable.
class ChannelBatch extends ChannelListEvent {
  const ChannelBatch(this.items);
  final List<QueueItem> items;
}

/// The directory finished; [total] channels were delivered in batches.
class ChannelListDone extends ChannelListEvent {
  const ChannelListDone(this.total);
  final int total;
}

/// The source is an HLS segment/variant manifest — mpv's job (§10.0).
class ChannelListHls extends ChannelListEvent {
  const ChannelListHls();
}

/// The source is not M3U text at all (a stream body, an error page).
class ChannelListNotPlaylist extends ChannelListEvent {
  const ChannelListNotPlaylist();
}

/// The load failed before or during parsing (§10.10b: "Failed to load" +
/// the playlist's *name*; never a channel failure, never a skip).
class ChannelListFailed extends ChannelListEvent {
  const ChannelListFailed(this.reason);
  final ChannelListFailure reason;
}

enum ChannelListFailure { network, tooLarge, io }

/// What the first non-blank line of a body says (see
/// [ChannelListLoader.sniffHead]).
enum HeadSniff { undecided, playlist, notPlaylist }

// ── Worker protocol ────────────────────────────────────────────────────

class _Job {
  const _Job(this.reply, this.source, this.isFile, this.base, this.byteCeiling);
  final SendPort reply;
  final String source;
  final bool isFile;
  final Uri? base;
  final int byteCeiling;
}

class _Done {
  const _Done(this.total);
  final int total;
}

class _Hls {
  const _Hls();
}

class _NotPlaylist {
  const _NotPlaylist();
}

class _Failed {
  const _Failed(this.reason);
  final ChannelListFailure reason;
}

class _TooLarge implements Exception {
  const _TooLarge();
}

enum _OutcomeKind { directory, hls, notPlaylist }

class _Outcome {
  const _Outcome(this.kind, this.total);
  final _OutcomeKind kind;
  final int total;
}
