import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_prefs.dart';
import 'language_utils.dart';
import 'media_utils.dart';
import 'natural_sort.dart';

/// One OpenSubtitles search hit, normalised for the SALU UI (Phase 7 · 3).
class SubtitleResult {
  const SubtitleResult({
    required this.fileId,
    required this.language,
    required this.release,
    required this.downloadCount,
    required this.ratings,
    required this.aiTranslated,
    required this.hashMatch,
  });

  /// Numeric `file_id` used by the /download endpoint.
  final int fileId;

  /// ISO code, e.g. `en`, `pt-br`.
  final String language;

  final String release;
  final int downloadCount;

  /// Community rating (0–10 on OpenSubtitles).
  final double ratings;
  final bool aiTranslated;

  /// True when this entry came back from the exact-file-hash query — i.e. it
  /// was made for *this very file*, which is the strongest possible match.
  final bool hashMatch;

  String get languageName => LanguageUtils.displayName(language);

  SubtitleResult copyWith({bool? hashMatch}) => SubtitleResult(
        fileId: fileId,
        language: language,
        release: release,
        downloadCount: downloadCount,
        ratings: ratings,
        aiTranslated: aiTranslated,
        hashMatch: hashMatch ?? this.hashMatch,
      );

  @override
  bool operator ==(Object other) =>
      other is SubtitleResult &&
      other.fileId == fileId &&
      other.language == language;

  @override
  int get hashCode => fileId.hashCode ^ language.hashCode;
}

/// Outcome of a search: the "Top 3 Best Matches" block + everything else.
class SubtitleSearchOutcome {
  const SubtitleSearchOutcome({
    this.bestMatches = const <SubtitleResult>[],
    this.results = const <SubtitleResult>[],
    this.error,
  });

  factory SubtitleSearchOutcome.failed(String message) =>
      SubtitleSearchOutcome(error: message);

  /// Exact file-hash hits, capped at [SubtitlesApi.maxTopMatches].
  final List<SubtitleResult> bestMatches;

  /// The remaining (filename-query) hits, duplicates removed.
  final List<SubtitleResult> results;

  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;

  bool get isEmpty => bestMatches.isEmpty && results.isEmpty;
}

/// Outcome of downloading + applying a subtitle file.
class SubtitleDownloadOutcome {
  const SubtitleDownloadOutcome({
    required this.success,
    required this.message,
    this.path,
    this.language,
  });

  final bool success;
  final String message;

  /// Where the subtitle ended up on disk (`movie.srt` next to `movie.mp4`).
  final String? path;

  final String? language;
}

/// Thin, dependency-free OpenSubtitles REST client (Phase 7 · Step 3).
///
/// Talks to `https://api.opensubtitles.com/api/v1` with the API key the user
/// pastes in Settings → Subtitles. Two search strategies are combined:
///  1. the classic OpenSubtitles **file hash** (size + 64-bit checksum of the
///     first/last 64 KB) — an exact match means the subtitle was made for
///     this precise video;
///  2. a **filename query** — the fallback for files too small to hash or
///     subtitles that were uploaded against the release name instead.
///
/// Downloads are written *next to the video* under the video's own base name
/// (`movie.srt`) so the Phase 5 sidecar loader picks them up forever after —
/// nothing is ever downloaded twice.
class SubtitlesApi {
  SubtitlesApi._();

  static final SubtitlesApi instance = SubtitlesApi._();

  static const String baseUrl = 'https://api.opensubtitles.com/api/v1';
  static const String userAgent = 'SALU-Player';

  /// "Top 3 Best Matches" per the spec.
  static const int maxTopMatches = 3;

  /// The hash reads 64 KB from the start and 64 KB from the end; files
  /// smaller than the combined 128 KB cannot be hashed.
  static const int _blockSize = 65536;
  static const int minHashableSize = _blockSize * 2;

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _downloadTimeout = Duration(seconds: 60);

  final http.Client _client = http.Client();

  bool get hasApiKey =>
      AppPrefs.instance.openSubtitlesApiKey.trim().isNotEmpty;

  Map<String, String> get _headers => <String, String>{
        'Api-Key': AppPrefs.instance.openSubtitlesApiKey.trim(),
        'User-Agent': userAgent,
        'Accept': 'application/json',
      };

  // ── Search ─────────────────────────────────────────────────────────────

  /// Full search flow for the video at [videoPath].
  ///
  /// [queryOverride] replaces the automatic "file name" query (typed by the
  /// user in the modal). [language] is an ISO code or `all` / `null` for no
  /// filter.
  Future<SubtitleSearchOutcome> searchForVideo(
    String videoPath, {
    String? queryOverride,
    String? language,
    bool hashOnly = false,
  }) async {
    if (!hasApiKey) {
      return SubtitleSearchOutcome.failed(
        'Add your OpenSubtitles API key in Settings → Subtitles first.',
      );
    }
    final File video = File(videoPath);
    if (!video.existsSync()) {
      return SubtitleSearchOutcome.failed('The video file is no longer there.');
    }

    final String? langs = _languageParam(language);
    String? hash;
    int size = 0;
    try {
      size = await video.length();
      if (size >= minHashableSize) {
        hash = await computeMovieHash(videoPath);
      }
    } catch (error) {
      debugPrint('[SALU] moviehash failed: $error');
    }

    final List<SubtitleResult> best = <SubtitleResult>[];
    String? lastError;

    if (hash != null) {
      final _SearchPage page = await _searchPage(<String, String>{
        'moviehash': hash,
        'moviebytesize': '$size',
        if (langs != null) 'languages': langs,
        'formats': 'srt',
        'page': '1',
      });
      if (page.error != null) lastError = page.error;
      // Everything the hash query returns was made for this exact file.
      best.addAll(
        page.results.map((SubtitleResult r) => r.copyWith(hashMatch: true)),
      );
    }

    List<SubtitleResult> all = const <SubtitleResult>[];
    if (!hashOnly) {
      final String query = (queryOverride ?? '').trim().isNotEmpty
          ? (queryOverride ?? '').trim()
          : MediaUtils.displayName(videoPath);
      final _SearchPage page = await _searchPage(<String, String>{
        'query': query,
        if (langs != null) 'languages': langs,
        'formats': 'srt',
        'page': '1',
      });
      if (page.error != null) lastError ??= page.error;
      all = page.results;
    }

    // De-duplicate: everything already shown in the "best" block disappears
    // from "all results".
    final Set<int> seen = best.map((SubtitleResult r) => r.fileId).toSet();
    all = all.where((SubtitleResult r) => !seen.contains(r.fileId)).toList();

    if (best.isEmpty && all.isEmpty) {
      if (lastError != null) return SubtitleSearchOutcome.failed(lastError);
      return const SubtitleSearchOutcome();
    }

    return SubtitleSearchOutcome(
      bestMatches: best.length > maxTopMatches
          ? best.sublist(0, maxTopMatches)
          : best,
      results: all,
    );
  }

  Future<_SearchPage> _searchPage(Map<String, String> params) async {
    try {
      final Uri uri = Uri.parse('$baseUrl/subtitles')
          .replace(queryParameters: params);
      final http.Response response =
          await _client.get(uri, headers: _headers).timeout(_requestTimeout);

      final Object? body = _tryJson(response.body);
      if (response.statusCode != 200) {
        return _SearchPage(
          const <SubtitleResult>[],
          _apiError(body, response.statusCode),
        );
      }
      if (body is! Map) {
        return const _SearchPage(
          <SubtitleResult>[],
          'OpenSubtitles returned an unexpected response.',
        );
      }
      final Object? data = body['data'];
      if (data is! List) {
        return const _SearchPage(<SubtitleResult>[], null);
      }
      final List<SubtitleResult> results = <SubtitleResult>[];
      for (final Object? item in data) {
        final SubtitleResult? parsed = _parseResult(item);
        if (parsed != null) results.add(parsed);
      }
      return _SearchPage(results, null);
    } on TimeoutException {
      return const _SearchPage(
        <SubtitleResult>[],
        'The OpenSubtitles API timed out. Check your connection.',
      );
    } on SocketException {
      return const _SearchPage(
        <SubtitleResult>[],
        'Could not reach OpenSubtitles (offline?).',
      );
    } catch (error) {
      debugPrint('[SALU] subtitles search failed: $error');
      return _SearchPage(const <SubtitleResult>[], 'Search failed: $error');
    }
  }

  static SubtitleResult? _parseResult(Object? item) {
    if (item is! Map) return null;
    final Object? attributes = item['attributes'];
    if (attributes is! Map) return null;

    // The downloadable file id lives in attributes.files[].file_id.
    final Object? files = attributes['files'];
    int? fileId;
    String fileName = '';
    if (files is List && files.isNotEmpty && files.first is Map) {
      final Map<Object?, Object?> first = files.first as Map;
      fileId = _asInt(first['file_id']);
      fileName = (first['file_name'] as String?)?.trim() ?? '';
    }
    if (fileId == null) return null; // Nothing downloadable — skip.

    final String language = (attributes['language'] as String?) ?? '';
    return SubtitleResult(
      fileId: fileId,
      language: language,
      release: ((attributes['release'] as String?)?.trim().isNotEmpty ?? false)
          ? (attributes['release'] as String).trim()
          : fileName,
      downloadCount: _asInt(attributes['download_count']) ?? 0,
      ratings: (attributes['ratings'] as num?)?.toDouble() ?? 0,
      aiTranslated: _asBool(attributes['ai_translated']),
      hashMatch: false, // Filled in by the caller for the hash block.
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static Object? _tryJson(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      return null;
    }
  }

  static String _apiError(Object? body, int statusCode) {
    if (body is Map) {
      final Object? messages = body['messages'];
      if (messages is List && messages.isNotEmpty && messages.first is Map) {
        final Map<Object?, Object?> first = messages.first as Map;
        final Object? message = first['message'];
        if (message is String && message.isNotEmpty) {
          if (statusCode == 401 || statusCode == 403) {
            return 'OpenSubtitles rejected your API key. Re-check it in Settings.';
          }
          return 'OpenSubtitles: $message';
        }
      }
    }
    return switch (statusCode) {
      401 || 403 => 'OpenSubtitles rejected your API key (HTTP $statusCode).',
      429 => 'OpenSubtitles rate limit reached — try again in a minute.',
      _ => 'OpenSubtitles returned HTTP $statusCode.',
    };
  }

  String? _languageParam(String? language) {
    final String value = (language == null || language.isEmpty || language == 'all')
        ? AppPrefs.instance.defaultSubtitleLanguage
        : language;
    if (value.isEmpty || value == 'all') return null;
    return value;
  }

  // ── Download & apply ───────────────────────────────────────────────────

  /// Downloads [result] and saves it next to [videoPath] using the video's
  /// own base name (`movie.mp4` → `movie.srt`), so the Phase 5 sidecar logic
  /// auto-loads it for good. Returns the absolute saved path on success.
  Future<SubtitleDownloadOutcome> downloadToVideoFolder(
    SubtitleResult result,
    String videoPath,
  ) async {
    if (!hasApiKey) {
      return const SubtitleDownloadOutcome(
        success: false,
        message: 'Add your OpenSubtitles API key in Settings → Subtitles first.',
      );
    }
    final File video = File(videoPath);
    if (!video.existsSync()) {
      return const SubtitleDownloadOutcome(
        success: false,
        message: 'The video file is no longer there.',
      );
    }

    try {
      final http.Response request = await _client
          .post(
            Uri.parse('$baseUrl/download'),
            headers: <String, String>{
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'file_id': result.fileId,
              'sub_format': 'srt',
            }),
          )
          .timeout(_requestTimeout);

      if (request.statusCode != 200) {
        return SubtitleDownloadOutcome(
          success: false,
          message: _apiError(_tryJson(request.body), request.statusCode),
        );
      }
      final Object? body = _tryJson(request.body);
      if (body is! Map || body['link'] is! String) {
        return const SubtitleDownloadOutcome(
          success: false,
          message: 'OpenSubtitles did not hand out a download link.',
        );
      }

      final String link = body['link']! as String;
      final String? token = body['token'] as String?;

      final http.Response file = await _client
          .get(
            Uri.parse(link),
            headers: <String, String>{
              'User-Agent': userAgent,
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(_downloadTimeout);

      if (file.statusCode != 200) {
        return SubtitleDownloadOutcome(
          success: false,
          message: 'CDN returned HTTP ${file.statusCode}.',
        );
      }
      final Uint8List bytes = file.bodyBytes;
      if (bytes.lengthInBytes < 16) {
        return const SubtitleDownloadOutcome(
          success: false,
          message: 'The downloaded subtitle file looks empty.',
        );
      }

      final String folder = p.dirname(videoPath);
      final String baseName = p.basenameWithoutExtension(videoPath);
      final String savedPath = _isZip(bytes)
          ? await _unzipSubtitleInto(bytes, folder, baseName)
          : await _writeSubtitle(bytes, folder, baseName);

      return SubtitleDownloadOutcome(
        success: true,
        message: 'Subtitle saved next to the video.',
        path: savedPath,
        language: result.language,
      );
    } on TimeoutException {
      return const SubtitleDownloadOutcome(
        success: false,
        message: 'The download timed out.',
      );
    } on SocketException {
      return const SubtitleDownloadOutcome(
        success: false,
        message: 'Could not reach OpenSubtitles (offline?).',
      );
    } catch (error) {
      debugPrint('[SALU] subtitle download failed: $error');
      return SubtitleDownloadOutcome(success: false, message: 'Download failed: $error');
    }
  }

  Future<String> _writeSubtitle(Uint8List bytes, String folder, String base) async {
    final File target = File(p.join(folder, '$base.srt'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static bool _isZip(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  /// A handful of uploads come back zipped — unpack with the PowerShell that
  /// ships with Windows (same zero-dependency trick as the updater service),
  /// keep the first real subtitle file, and name it after the video.
  Future<String> _unzipSubtitleInto(Uint8List bytes, String folder, String base) async {
    final Directory temp = await Directory.systemTemp.createTemp('salu_subs');
    try {
      final String zipPath = p.join(temp.path, 'sub.zip');
      await File(zipPath).writeAsBytes(bytes, flush: true);
      final String outDir = p.join(temp.path, 'out');
      final ProcessResult unzip = await Process.run('powershell', <String>[
        '-NoProfile',
        '-Command',
        "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$outDir' -Force",
      ]);
      if (unzip.exitCode != 0) {
        throw const FormatException('Could not unpack the zipped subtitle.');
      }

      final List<File> candidates = Directory(outDir)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => MediaUtils.isSubtitle(f.path))
          .toList()
        ..sort((File a, File b) =>
            NaturalSort.compare(p.basename(a.path), p.basename(b.path)));
      if (candidates.isEmpty) {
        throw const FormatException('The archive held no subtitle file.');
      }

      final File picked = candidates.firstWhere(
        (File f) => p.extension(f.path).toLowerCase() == '.srt',
        orElse: () => candidates.first,
      );
      final String ext = MediaUtils.isSubtitle(picked.path)
          ? p.extension(picked.path).toLowerCase()
          : '.srt';
      final File target = File(p.join(folder, '$base$ext'));
      await picked.copy(target.path);
      return target.path;
    } finally {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  // ── Smart auto-download (Phase 7 · Step 5) ────────────────────────────

  /// Silent background fetch used on video open: hash-only search in the
  /// user's default language; downloads strictly when the file hash matches.
  /// Returns `null` when nothing perfect was found (no error noise — this is
  /// meant to fail quietly).
  Future<SubtitleDownloadOutcome?> autoFetchBest(String videoPath) async {
    if (!hasApiKey) return null;
    final SubtitleSearchOutcome outcome = await searchForVideo(
      videoPath,
      language: AppPrefs.instance.defaultSubtitleLanguage,
      hashOnly: true,
    );
    if (outcome.bestMatches.isEmpty) return null;
    final SubtitleResult best = outcome.bestMatches.first;
    return downloadToVideoFolder(best, videoPath);
  }

  // ── File hash (classic OpenSubtitles 64-bit "Hash64") ─────────────────

  /// size + 64-bit little-endian checksum of the first 64 KB and the last
  /// 64 KB of the file, wrapped to unsigned 64 bits and printed as 16 hex
  /// digits. Reads at most 128 KB no matter how huge the video is.
  Future<String?> computeMovieHash(String path) async {
    RandomAccessFile? raf;
    try {
      final File file = File(path);
      final int size = await file.length();
      if (size < minHashableSize) return null;

      raf = await file.open();
      int hash = size; // The size itself seeds the sum.
      hash = await _accumulate(raf, 0, hash);
      hash = await _accumulate(raf, size - _blockSize, hash);
      return _hex64(hash);
    } catch (error) {
      debugPrint('[SALU] moviehash failed: $error');
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<int> _accumulate(RandomAccessFile raf, int start, int hash) async {
    await raf.setPosition(start);
    final Uint8List buffer = Uint8List(_blockSize);
    final int read = await raf.readInto(buffer);
    final int usable = read - read % 8;
    final ByteData view = ByteData.sublistView(buffer, 0, usable);
    for (int offset = 0; offset < usable; offset += 8) {
      // Dart ints wrap at 2^64 exactly like the reference C implementation.
      hash += view.getUint64(offset, Endian.little);
    }
    return hash;
  }

  /// Unsigned 64-bit hex — [int.toRadixString] would print a minus sign for
  /// values whose top bit is set, so both halves are formatted separately.
  static String _hex64(int value) {
    final String high = (value >>> 32).toRadixString(16).padLeft(8, '0');
    final String low = (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$high$low';
  }

  /// Quick connectivity + key validation probe for the Settings screen.
  Future<String?> testConnection() async {
    if (!hasApiKey) {
      return 'No API key configured yet.';
    }
    try {
      final http.Response response = await _client
          .get(Uri.parse('$baseUrl/languages'), headers: _headers)
          .timeout(_requestTimeout);
      if (response.statusCode == 200) return null; // All good.
      return _apiError(_tryJson(response.body), response.statusCode);
    } catch (error) {
      return 'Could not reach OpenSubtitles: $error';
    }
  }
}

class _SearchPage {
  const _SearchPage(this.results, this.error);

  final List<SubtitleResult> results;
  final String? error;
}

