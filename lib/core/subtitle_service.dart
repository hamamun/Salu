import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../ui/osd/osd_controller.dart';
import 'language_names.dart';
import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'settings_service.dart';

/// One subtitle-file row from OpenSubtitles (cc.md §6.5 — "rows are
/// subtitle files"): what the viewer picks from in the Search window.
class SubtitleResult {
  const SubtitleResult({
    required this.fileId,
    required this.language,
    required this.title,
    required this.release,
    required this.downloads,
    required this.ext,
  });

  /// The `/download` payload id.
  final int fileId;

  /// ISO 639-1 language code as the API reports it.
  final String language;

  /// The movie/episode's feature title (the row's main line).
  final String title;

  /// The release-name line (the row's sub-line).
  final String release;

  /// Provider download count (sub-line's trailing number).
  final int downloads;

  /// Subtitle extension (`srt`, `ass`, …) — the D8 name's last part.
  final String ext;

  /// Row sub-line: `release · 584k` (mock's exact shape).
  String get subLine {
    final String d = _formatDownloads(downloads);
    return release.isEmpty ? d : '$release · $d';
  }

  static String _formatDownloads(int n) {
    if (n < 1000) return '$n';
    final double k = n / 1000;
    if (k < 100) {
      final String s = k.toStringAsFixed(1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
    }
    return '${k.round()}k';
  }
}

/// The outcome of a manual Save / Save & Load (§6.5): nothing is
/// downloaded when the D8 name is already there (quota is never burned
/// twice) — and [path] says where the bytes actually live so Save & Load
/// can apply them immediately.
enum SubtitleSaveStatus { saved, alreadySaved, failed }

class SubtitleSaveOutcome {
  const SubtitleSaveOutcome({
    required this.status,
    required this.fileName,
    required this.path,
  });

  final SubtitleSaveStatus status;

  /// The D8 display name (`movie.en.srt`) — for the OSD card.
  final String fileName;

  /// Where the file exists on disk after the call (the video's folder,
  /// or the temp fallback). `null` on [SubtitleSaveStatus.failed].
  final String? path;
}

/// SALU's v1 subtitle engine (cc.md §3 · §6.5) — silent background work.
///
/// AUTO (§3): every local-video landing is answered from
/// [onMediaLanded] — the D5 chain is **moviehash hits only**, preferred
/// language → English. MANUAL (§6.5): [search] runs the query search the
/// auto path never touches, and [save] / [saveAndLoad] write the picked
/// file with D8 naming.
///
/// Session state per the contract:
///   · the Bearer token lives in [_token], in memory ONLY (D13) — plus
///     the password, which also never touches disk (see
///     [sessionPassword]); restart = re-login.
///   · `_authorized=false` after a 401 → the engine pauses until a
///     credential changes (§3.5 — settings-change listeners below);
///   · `_quotaPaused=true` after a 429/402 → paused until relaunch;
///   · [_failedThisSession] — each bare file tries at most once;
///   · the three cards each speak at most once per session (D10).
class SubtitleService {
  SubtitleService._() {
    // A credential edit releases the 401 pause (§3.5).
    final SettingsService s = SettingsService.instance;
    s.subtitleApiKey.addListener(_onCredentialChange);
    s.subtitleUsername.addListener(_onCredentialChange);
    sessionPassword.addListener(_onCredentialChange);
  }

  /// The one engine for the app.
  static final SubtitleService instance = SubtitleService._();

  // ── API facts (cc.md §4) ─────────────────────────────────────────────
  static const String _base = 'https://api.opensubtitles.com/api/v1';
  static const String _userAgent = 'SALU/0.1.0';
  static const Duration _timeout = Duration(seconds: 10);

  static final http.Client _client = http.Client();

  // ── Session state ────────────────────────────────────────────────────

  /// The account password — **memory only, never persisted** (D13).
  /// Written straight from the settings field onto this notifier.
  final ValueNotifier<String> sessionPassword = ValueNotifier<String>('');

  /// The Bearer token — memory only, re-login per session (D13).
  String? _token;

  /// 401 seen → pause until a credential changes (§3.5).
  bool _authPaused = false;

  /// 429/402 seen → pause until relaunch (§3.5; quota context §3.5).
  bool _quotaPaused = false;

  /// Canonical paths that already failed / came back empty this session
  /// (guard 4) — a 12-episode binge never fires 12 doomed retries.
  final Set<String> _failedThisSession = <String>{};

  /// Per-path in-flight guard so two triggers of the same file can't
  /// double-download (the session-failed set only arms later).
  final Set<String> _inFlight = <String>{};

  /// Once-per-session notice flags (D10).
  bool _noticeCcShown = false;
  bool _noticeKeyShown = false;
  bool _noticeLimitShown = false;

  /// The path currently being considered by the auto chain — a fast
  /// zapper invalidates the compare (§3.1 guard 5).
  String? _autoWantedPath;

  void _onCredentialChange() {
    _authPaused = false;
  }

  // ────────────────────────────────────────────────────────────────────
  //  AUTO path (cc.md §3)
  // ────────────────────────────────────────────────────────────────────

  /// The §3.1 trigger — called by [PlayerService] when the playlist
  /// lands on an item. Every guard lives here, so the player side stays
  /// a single dumb line. Fire-and-forget.
  void onMediaLanded(String uri, {required bool channelMode}) {
    if (channelMode) return; // D6 — never channel/live mode.
    if (uri.contains('://')) return; // D6 — never remote streams.
    if (!MediaUtils.isVideo(uri)) return; // D6 — never audio.
    final String path = MediaUtils.canonicalPath(uri);
    if (QueueService.instance.isChannelList) return;
    _autoWantedPath = path;
    unawaited(_maybeAutoFetch(path));
  }

  Future<void> _maybeAutoFetch(String path) async {
    // Guard 1a — the toggle. OFF = fully silent stop (D12).
    if (!SettingsService.instance.subtitleAutoDownload.value) return;

    // Guard 4 — one try per file per session; and never two concurrent.
    if (_failedThisSession.contains(path) || !_inFlight.add(path)) return;

    try {
      // The mpv track report settles right after start-file — and on a
      // zap it fires more than once (the outgoing file's tracks torn
      // down, then the new file's opened). A one-beat read can catch
      // the DEPLETED list and false-fetch a video that has embedded
      // subs (D7): wait for the report to go quiet (bounded), then
      // read the settled state.
      await _awaitSettledTracks();
      if (_autoWantedPath != path) return; // zapped mid-settle

      // Guard 3 — D7 "no usable subtitle": mpv reports zero subtitle
      // tracks for the item (numeric ids — media_kit prepends
      // 'auto'/'no' pseudo-rows, skipped here; TEXT AND BITMAP both
      // count: D16's proof is a PGS .mkv showing its subs through
      // mpv, so an image track is a usable track, not a gap), AND no
      // basename-matching sibling on disk.
      final List<SubtitleTrack> subRows =
          PlayerService.instance.player.state.tracks.subtitle;
      final bool hasSub =
          subRows.any((SubtitleTrack t) => int.tryParse(t.id) != null);
      if (hasSub) return;
      if (_hasMatchingSibling(path)) return;

      // Guard 1b — the key. Everything else would fetch: this is the
      // one honest `cc not configured` moment (D11). Still tries
      // afterwards (the key may arrive mid-session) — NOT marked failed.
      final SettingsService settings = SettingsService.instance;
      if (settings.subtitleApiKey.value.isEmpty) {
        _noticeCc();
        return;
      }
      // Engine pauses — silent (their cards already spoke).
      if (_quotaPaused || _authPaused) return;

      // One more wanted-check before quota is spent: a fast zapper
      // never makes SALU buy the previous episode's subs.
      if (_autoWantedPath != path) return;

      // §3.2 — moviehash, preferred → English. No query step (D9).
      final String? hash = await _movieHash(path);
      if (hash == null) {
        _failedThisSession.add(path);
        return;
      }
      final String pref = LanguageNames.normalize(
          SettingsService.instance.subtitleLanguage.value);
      List<SubtitleResult>? hits = await _search(
        <String, String>{'moviehash': hash, 'languages': pref},
      );
      bool gaveUp = false;
      if (hits == null) return; // notice already spoken (or silent pause)
      if (hits.isEmpty && pref != 'en') {
        hits = await _search(
          <String, String>{'moviehash': hash, 'languages': 'en'},
        );
        if (hits == null) return;
      }
      if (hits.isEmpty) {
        // Music videos & home movies are free hits to nothing (§3.2) —
        // silence, marked for the session.
        gaveUp = true;
      }
      if (gaveUp) {
        _failedThisSession.add(path);
        return;
      }

      final SubtitleResult hit = hits.first;
      await _fetchSaveApply(hit, path);
    } finally {
      _inFlight.remove(path);
    }
  }

  /// Bounded wait for mpv's track report to settle: [quiet] of
  /// silence after the last emission, or [cap] overall — whichever
  /// comes first. The auto fetch is silent background work (D10), so
  /// the settle costs nothing the viewer can see; a too-early read
  /// costs quota (a false "no embedded subs" → a download the video
  /// never needed).
  Future<void> _awaitSettledTracks() async {
    const Duration quiet = Duration(milliseconds: 500);
    const Duration cap = Duration(milliseconds: 1500);
    final Completer<void> settled = Completer<void>();
    Timer? silence;
    StreamSubscription<Tracks>? sub;
    try {
      sub = PlayerService.instance.player.stream.tracks.listen(
        (Tracks _) {
          silence?.cancel();
          silence = Timer(quiet, () {
            if (!settled.isCompleted) settled.complete();
          });
        },
      );
      try {
        await settled.future.timeout(cap);
      } catch (_) {
        // Cap reached — the current state is our best answer.
      }
    } finally {
      silence?.cancel();
      await sub?.cancel();
    }
  }

  /// Downloads, saves beside the movie, applies iff still current
  /// (§3.3). The auto flow speaks NO cards on success (D10) — the subs
  /// simply appear.
  Future<void> _fetchSaveApply(SubtitleResult result, String path) async {
    final SubtitleSaveOutcome? outcome = await _saveCore(result, path);
    if (outcome == null ||
        (outcome.status == SubtitleSaveStatus.failed &&
            !_quotaPaused &&
            !_authPaused)) {
      // A silent network blip marks this file for the session; quota and
      // auth walls already paused the engine with their one card, so a
      // wall trip is NOT a per-file failure.
      if (outcome == null || !_quotaPaused && !_authPaused) {
        _failedThisSession.add(path);
      }
      return;
    }
    // The target check on arrival (§3.1 guard 5): the file is saved
    // either way — it belongs to that video — but only applies when the
    // fetched file's video is still the loaded one.
    if (outcome.path != null &&
        (PlayerService.instance.currentPath.value == path ||
            _autoWantedPath == path)) {
      unawaited(PlayerService.instance.loadExternalSubtitle(outcome.path!));
    }
  }

  // ────────────────────────────────────────────────────────────────────
  //  MANUAL path (cc.md §6.5) — the Search window
  // ────────────────────────────────────────────────────────────────────

  /// The query/filename search (D9: manual-Fetch-only). One request,
  /// all languages; the window groups it locally. Returns rows on
  /// success; an EMPTY list when there is nothing to show — including
  /// the not-configured / paused / failed cases, which already spoke
  /// their once-per-session card (§6.5 "no new dialog").
  Future<List<SubtitleResult>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return const <SubtitleResult>[];
    if (SettingsService.instance.subtitleApiKey.value.isEmpty) {
      _noticeCc();
      return const <SubtitleResult>[];
    }
    if (_quotaPaused || _authPaused) {
      // Each pause already spoke its card; don't spam (§3.5).
      return const <SubtitleResult>[];
    }
    final List<SubtitleResult>? rows =
        await _search(<String, String>{'query': q});
    if (rows == null) return const <SubtitleResult>[];
    return rows;
  }

  /// The shared Save core (§6.5): D8 naming, dedupe, temp fallback.
  /// Returns `null` when nothing could be written (engine cards already
  /// spoken where the rules ask for one).
  Future<SubtitleSaveOutcome?> _saveCore(
    SubtitleResult result,
    String videoPath,
  ) async {
    final String name = _targetName(videoPath, result.language, result.ext);
    // Already-saved target — spend no quota (§6.5; quota is never
    // burned twice for one file). Beside the video first; a copy in
    // the temp fallback (§3.3's unwritable-folder save) is the same
    // bought D8 name, so it counts too.
    final String sibling = p.join(p.dirname(videoPath), name);
    if (await File(sibling).exists()) {
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.alreadySaved,
          fileName: name,
          path: sibling);
    }
    final String tempCopy =
        p.join(Directory.systemTemp.path, 'salu_subs', name);
    if (await File(tempCopy).exists()) {
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.alreadySaved,
          fileName: name,
          path: tempCopy);
    }
    if (SettingsService.instance.subtitleApiKey.value.isEmpty) {
      _noticeCc();
      return null;
    }
    if (_quotaPaused || _authPaused) return null;

    final Uint8List? bytes = await _download(result.fileId);
    if (bytes == null) {
      return const SubtitleSaveOutcome(
          status: SubtitleSaveStatus.failed, fileName: '', path: null);
    }

    // Beside the movie; unwritable → temp, same name (D8).
    try {
      await File(sibling).writeAsBytes(bytes, flush: true);
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.saved, fileName: name, path: sibling);
    } catch (_) {
      // Fall through to the temp fallback.
    }
    try {
      final Directory dir =
          Directory(p.join(Directory.systemTemp.path, 'salu_subs'));
      await dir.create(recursive: true);
      final String temp = p.join(dir.path, name);
      await File(temp).writeAsBytes(bytes, flush: true);
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.saved, fileName: name, path: temp);
    } catch (_) {
      return const SubtitleSaveOutcome(
          status: SubtitleSaveStatus.failed, fileName: '', path: null);
    }
  }

  /// §6.5 **Save** — download + write next to the video (D8), window
  /// closes, ONE transient card: `Saved · <filename>` — or
  /// `Already saved · <filename>` when the D8 name was already there and
  /// no download was spent (honest words, quota never burned twice).
  /// Never applied to playback: mpv autoloads it on the next open (§3.4).
  Future<SubtitleSaveOutcome?> save(
      SubtitleResult result, String videoPath) async {
    final String canonical = MediaUtils.canonicalPath(videoPath);
    final SubtitleSaveOutcome? outcome = await _saveCore(result, canonical);
    if (outcome != null && outcome.status != SubtitleSaveStatus.failed) {
      OsdController.instance.show(OsdSubtitleCard.saved(
        name: outcome.fileName,
        already: outcome.status == SubtitleSaveStatus.alreadySaved,
      ));
    }
    return outcome;
  }

  /// §6.5 **Save & Load** — the same write + apply NOW via
  /// [PlayerService.loadExternalSubtitle]; the already-saved target
  /// applies its existing local copy (§6.5: ONE download, the second
  /// tap applies the file). NO card here: Save & Load's feedback is the
  /// subs on screen + the marked panel row (§6.6, D10).
  Future<SubtitleSaveOutcome?> saveAndLoad(
      SubtitleResult result, String videoPath) async {
    final String canonical = MediaUtils.canonicalPath(videoPath);
    final SubtitleSaveOutcome? outcome = await _saveCore(result, canonical);
    if (outcome != null &&
        outcome.status != SubtitleSaveStatus.failed &&
        outcome.path != null &&
        PlayerService.instance.currentPath.value == canonical) {
      unawaited(PlayerService.instance.loadExternalSubtitle(outcome.path!));
    }
    return outcome;
  }

  // ────────────────────────────────────────────────────────────────────
  //  API plumbing (cc.md §4)
  // ────────────────────────────────────────────────────────────────────

  /// `/subtitles` — returns rows, or `null` when the call itself failed
  /// (401/429/402 handled with their once-per-session cards + pauses;
  /// network trouble is silent per §3.5).
  Future<List<SubtitleResult>?> _search(Map<String, String> params) async {
    final Uri url = Uri.parse('$_base/subtitles')
        .replace(queryParameters: params);
    try {
      final http.Response r = await _client
          .get(url, headers: <String, String>{
        'Api-Key': SettingsService.instance.subtitleApiKey.value,
        'User-Agent': _userAgent,
        'Content-Type': 'application/json',
      }).timeout(_timeout);
      if (r.statusCode == 401) {
        _authPaused = true;
        _noticeKey();
        return null;
      }
      if (r.statusCode == 429 || r.statusCode == 402) {
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode != 200) return null;
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic> data = (body['data'] as List?) ?? const [];
      return data
          .map(_resultFrom)
          .whereType<SubtitleResult>()
          .toList(growable: false);
    } catch (_) {
      return null; // network down / timeout — silent (§3.5).
    }
  }

  SubtitleResult? _resultFrom(dynamic raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> attrs =
        (raw['attributes'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final List<dynamic> files = (attrs['files'] as List?) ?? const [];
    if (files.isEmpty || files.first is! Map) return null;
    final Map<String, dynamic> file =
        (files.first as Map).cast<String, dynamic>();
    final int? fileId = (file['file_id'] as num?)?.toInt();
    if (fileId == null) return null;
    final Map<String, dynamic> feature =
        (attrs['feature_details'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final String lang = '${attrs['language'] ?? ''}';
    final String fileName = '${file['file_name'] ?? ''}';
    final String ext = _subExt(fileName);
    final String release = '${attrs['release'] ?? ''}'.trim();
    final String featureTitle = '${feature['title'] ?? ''}'.trim();
    if (lang.isEmpty) return null;
    return SubtitleResult(
      fileId: fileId,
      language: lang,
      title: featureTitle.isNotEmpty
          ? featureTitle
          : (release.isNotEmpty ? release : fileName),
      release: release,
      downloads: (attrs['download_count'] as num?)?.toInt() ?? 0,
      ext: ext,
    );
  }

  /// Bearer token for `/download` — silent login per session (D13).
  /// Returns `null` on any failure: 401 already spoke + paused.
  Future<String?> _ensureToken() async {
    if (_token != null) return _token;
    final SettingsService s = SettingsService.instance;
    if (s.subtitleUsername.value.isEmpty || sessionPassword.value.isEmpty) {
      // Credentials are the user's problem statement; with a key but no
      // login, download is simply unavailable (§2.1 — key-only = search
      // without download). Nothing to surface: the fields exist in
      // settings; silence keeps D10.
      return null;
    }
    try {
      final http.Response r = await _client
          .post(
            Uri.parse('$_base/login'),
            headers: <String, String>{
              // /login needs the Api-Key too (§4 — the API's own docs
              // list it as a required header here, alongside
              // User-Agent and Content-Type; keyless logins 401).
              'Api-Key': s.subtitleApiKey.value,
              'User-Agent': _userAgent,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'username': s.subtitleUsername.value,
              'password': sessionPassword.value,
            }),
          )
          .timeout(_timeout);
      if (r.statusCode == 401) {
        _authPaused = true;
        _noticeKey();
        return null;
      }
      if (r.statusCode == 429) {
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final String token = '${body['token'] ?? ''}';
      if (token.isEmpty) return null;
      _token = token; // memory only (D13 — never persisted).
      return token;
    } catch (_) {
      return null;
    }
  }

  /// `/download` → follow the single-use link immediately (§3.3-1),
  /// decompressing gzip (§3.3-2). `null` = silent failure path.
  Future<Uint8List?> _download(int fileId) async {
    if (_quotaPaused || _authPaused) return null;
    final String? token = await _ensureToken();
    if (token == null) return null;
    try {
      final http.Response r = await _client
          .post(
            Uri.parse('$_base/download'),
            headers: <String, String>{
              'Api-Key': SettingsService.instance.subtitleApiKey.value,
              'Authorization': 'Bearer $token',
              'User-Agent': _userAgent,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, int>{'file_id': fileId}),
          )
          .timeout(_timeout);
      if (r.statusCode == 401) {
        // Token expired mid-session → throw it away; next call re-logins.
        _token = null;
        _authPaused = true;
        _noticeKey();
        return null;
      }
      if (r.statusCode == 429 || r.statusCode == 402 || r.statusCode == 403) {
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode != 200) return null;
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final String link = '${body['link'] ?? ''}';
      if (link.isEmpty) return null;
      final http.Response file =
          await _client.get(Uri.parse(link)).timeout(_timeout);
      if (file.statusCode != 200) return null;
      Uint8List bytes = file.bodyBytes;
      // The API serves gzipped bodies unless asked otherwise (§3.3-2).
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        bytes = Uint8List.fromList(const GZipCodec().decode(bytes));
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────
  //  Files on disk (§3.4 · D8)
  // ────────────────────────────────────────────────────────────────────

  /// D8: `<basename>.<lang>.<ext>` — named after the MOVIE, never the
  /// provider's filename.
  String _targetName(String videoPath, String lang, String ext) {
    final String base = p.basenameWithoutExtension(videoPath);
    return '$base.$lang.$ext';
  }

  /// D7 sibling check: next to `movie.mkv`, is there `movie.srt` or
  /// `movie.<lang>.srt` in any supported extension (mp^v's autoload set,
  /// §3.4)? Segments like `movie.en.hi.srt` or `movie commentary.srt`
  /// are correctly NOT matches.
  bool _hasMatchingSibling(String videoPath) {
    final String base = p.basenameWithoutExtension(videoPath);
    final RegExp name = RegExp(
      '^${RegExp.escape(base)}(\\.[a-zA-Z]{2,3})?\\.(${MediaUtils.subtitleExtensions.map((String e) => e.substring(1)).join('|')})\$',
      caseSensitive: false,
    );
    try {
      final Directory dir = Directory(p.dirname(videoPath));
      if (!dir.existsSync()) return false;
      for (final FileSystemEntity e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        if (name.hasMatch(p.basename(e.path))) return true;
      }
    } catch (_) {
      // Unreadable folder → there can't be a sibling we can trust;
      // fetch anyway (write will fall back to temp if needed).
    }
    return false;
  }

  /// The OpenSubtitles 64-bit moviehash (§3.2-1): file size + the 8-byte
  /// little-endian word sum of the first and last 64 KB. `dart:io` only,
  /// no native deps. Files under 64 KB can't be hashed → `null`.
  Future<String?> _movieHash(String path) async {
    const int chunk = 64 * 1024;
    final BigInt mask = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
    final File file = File(path);
    RandomAccessFile? raw;
    try {
      raw = await file.open();
      final int length = await raw.length();
      if (length < chunk) return null;
      Uint8List first = await raw.read(chunk);
      await raw.setPosition(length - chunk);
      Uint8List last = await raw.read(chunk);
      BigInt hash = BigInt.from(length);
      for (final Uint8List bytes in <Uint8List>[first, last]) {
        for (int i = 0; i + 8 <= bytes.length; i += 8) {
          BigInt word = BigInt.zero;
          for (int j = 7; j >= 0; j--) {
            word = (word << 8) | BigInt.from(bytes[i + j]);
          }
          hash = (hash + word) & mask;
        }
      }
      return hash.toRadixString(16).padLeft(16, '0');
    } catch (_) {
      return null;
    } finally {
      await raw?.close();
    }
  }

  /// The provider's subtitle extension for the D8 name — from the
  /// negotiated file's own name, defaulting to `srt`.
  String _subExt(String fileName) {
    final String ext = p.extension(fileName).toLowerCase();
    if (MediaUtils.subtitleExtensions.contains(ext)) {
      return ext.substring(1);
    }
    return 'srt';
  }

  // ────────────────────────────────────────────────────────────────────
  //  Once-per-session cards (D10 · §3.5)
  // ────────────────────────────────────────────────────────────────────

  /// D11 literal — owner's text, one card per session.
  void _noticeCc() {
    if (_noticeCcShown) return;
    _noticeCcShown = true;
    OsdController.instance.show(const OsdSubtitleCard.cc());
  }

  void _noticeKey() {
    if (_noticeKeyShown) return;
    _noticeKeyShown = true;
    OsdController.instance.show(const OsdSubtitleCard.checkKey());
  }

  void _noticeLimit() {
    if (_noticeLimitShown) return;
    _noticeLimitShown = true;
    OsdController.instance.show(const OsdSubtitleCard.limit());
  }
}
