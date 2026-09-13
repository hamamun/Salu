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
///
/// [notSignedIn] is the one the owner hit on the first real run
/// (2026-09-13): search needs only the API key, but `/download` needs a
/// Bearer token that only `/login` can mint (cc.md §4). D13 originally kept
/// the password in memory, so EVERY restart landed here until the viewer
/// signed in again — and the AUTO engine's one trigger (§3.1) always fired
/// before that could happen, which read as "download just doesn't work,
/// nothing said". D13 is amended (owner 2026-09-13): the password is
/// persisted scrambled, so this is now only the first run, or a field the
/// viewer deliberately cleared.
enum SubtitleSaveStatus { saved, alreadySaved, failed, notSignedIn }

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
  /// or the temp fallback). `null` on [SubtitleSaveStatus.failed] and on
  /// [SubtitleSaveStatus.notSignedIn] (nothing was written).
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
///   · the Bearer token lives in [_token], in memory ONLY (D13). The
///     password is now PERSISTED scrambled (D13 amended, owner
///     2026-09-13 — see `SettingsService.subtitlePassword`), so a restart
///     re-logins silently instead of losing the download path entirely.
///   · `_authPaused=true` after a 401 → the engine pauses until a
///     credential changes (§3.5 — settings-change listeners below);
///   · `_quotaPaused=true` after a 429/402 → paused until relaunch;
///   · [_failedThisSession] — each bare file tries at most once;
///   · the cards each speak at most once per session (D10).
class SubtitleService {
  SubtitleService._() {
    // A credential edit releases the 401 pause (§3.5) AND re-opens the
    // door for the video that is already on screen (§3.1's one trigger
    // may well have fired while the credentials were still missing).
    final SettingsService s = SettingsService.instance;
    s.subtitleApiKey.addListener(_onCredentialChange);
    s.subtitleUsername.addListener(_onCredentialChange);
    s.subtitlePassword.addListener(_onCredentialChange);
  }

  /// The one engine for the app.
  static final SubtitleService instance = SubtitleService._();

  // ── API facts (cc.md §4) ─────────────────────────────────────────────
  static const String _base = 'https://api.opensubtitles.com/api/v1';
  static const String _userAgent = 'SALU/0.1.0';
  static const Duration _timeout = Duration(seconds: 10);

  static final http.Client _client = http.Client();

  // ── Session state ────────────────────────────────────────────────────

  /// The Bearer token — memory only, re-login per session (D13). Never
  /// persisted, and thrown away the moment any credential changes.
  String? _token;

  /// 401 seen → pause until a credential changes (§3.5).
  bool _authPaused = false;

  /// Which half the 401 came from (§3.5): `/login` rejecting the
  /// username+password is a DIFFERENT repair than `/subtitles` rejecting
  /// the API key, and the deck used to name the key for both — sending the
  /// viewer to check the one field that was fine (owner's report,
  /// 2026-09-13: everything filled, nothing happened, nothing said).
  bool _loginRejected = false;

  /// Debounce for [_retryCurrent] — a credential field fires its notifier
  /// on EVERY keystroke, and one keystroke must never buy one download.
  /// 1.5 s of quiet is longer than a typing pause inside a word and still
  /// short enough that the subs arrive while the viewer is watching; it
  /// also keeps two logins more than a second apart, which is `/login`'s
  /// own rate limit (§4).
  Timer? _retryTimer;

  /// `true` while a [_retryCurrent] fetch is in flight. Such a fetch
  /// answers a KEYSTROKE, not a viewer request, so it stays mute (D10's
  /// AUTO silence): a password half typed when the debounce expired must
  /// not spend the session's one `check login` card, and the wall it hits
  /// is still on the record — the next deliberate act speaks it (a manual
  /// Save answers every tap, §6.5).
  bool _backgroundRetry = false;

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
  bool _noticeLoginShown = false;
  bool _noticeLimitShown = false;

  /// The path currently being considered by the auto chain — a fast
  /// zapper invalidates the compare (§3.1 guard 5).
  String? _autoWantedPath;

  void _onCredentialChange() {
    _authPaused = false;
    _loginRejected = false;
    // A changed credential invalidates whatever token the old one minted —
    // without this, fixing a typo'd password keeps replaying the dead token.
    _token = null;
    _retryCurrent();
  }

  /// A usable login for `/download`: both halves present. Persisted since
  /// D13's amendment (owner 2026-09-13), so it now survives a restart.
  bool get _hasLogin =>
      SettingsService.instance.subtitleUsername.value.isNotEmpty &&
      SettingsService.instance.subtitlePassword.value.isNotEmpty;

  /// Re-answers the video that is ALREADY on screen after a credential
  /// edit (owner's report 2026-09-13: everything filled in, nothing
  /// happened, nothing said).
  ///
  /// §3.1's trigger fires ONCE, at the landing — which is exactly the
  /// moment a first run (or a cleared field) has no login yet, so the fetch
  /// was refused and nothing would ever ask again for that video until it
  /// was closed and reopened. Typing the credential now retries the loaded
  /// file, debounced so a password typed one character at a time costs one
  /// attempt, not twenty.
  ///
  /// Every existing guard still stands (D12's toggle, the quota wall, the
  /// in-flight lock, D7's "already has subs") — this only re-asks the
  /// question, it never widens when SALU may spend quota.
  void _retryCurrent() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 1500), () {
      final String? path = _autoWantedPath;
      if (path == null) return;
      if (PlayerService.instance.currentPath.value != path) return;
      final SettingsService s = SettingsService.instance;
      if (!s.subtitleAutoDownload.value) return; // D12 — OFF means OFF
      if (s.subtitleApiKey.value.isEmpty || !_hasLogin) return;
      if (_quotaPaused) return; // a quota wall still waits for a relaunch
      _log('credentials changed — retrying the loaded video "$path"');
      // The earlier refusal may be what marked this file for the session;
      // a credential edit is a new fact, so the file gets its try back.
      _failedThisSession.remove(path);
      _backgroundRetry = true;
      unawaited(_maybeAutoFetch(path)
          .whenComplete(() => _backgroundRetry = false));
    });
  }

  // ────────────────────────────────────────────────────────────────────
  //  AUTO path (cc.md §3)
  // ────────────────────────────────────────────────────────────────────

  /// The §3.1 trigger — called by [PlayerService] when the playlist
  /// lands on an item. Every guard lives here, so the player side stays
  /// a single dumb line. Fire-and-forget.
  void onMediaLanded(String uri, {required bool channelMode}) {
    if (channelMode) {
      _log('skip (D6 channel mode): $uri');
      return; // D6 — never channel/live mode.
    }
    if (uri.contains('://')) {
      _log('skip (D6 remote stream): $uri');
      return; // D6 — never remote streams.
    }
    if (!MediaUtils.isVideo(uri)) {
      _log('skip (D6 not a video): $uri');
      return; // D6 — never audio.
    }
    final String path = MediaUtils.canonicalPath(uri);
    if (QueueService.instance.isChannelList) {
      _log('skip (channel list loaded): $path');
      return;
    }
    _autoWantedPath = path;
    // A fresh landing is a real viewer-caused event, so its cards speak
    // even if a keystroke-triggered retry is still winding down.
    _backgroundRetry = false;
    unawaited(_maybeAutoFetch(path));
  }

  /// The console half of the engine. The DECK stays silent by design
  /// (D10), but silence in the UI must not mean silence in the log — the
  /// owner's 2026-09-13 report was "nothing at all, no message", and
  /// without this there is no way to tell which of a dozen guards refused.
  /// Dev console only; no UI, no instruction text (follow.md rule 1).
  static void _log(String message) => debugPrint('[SALU/subs] $message');

  Future<void> _maybeAutoFetch(String path) async {
    // Guard 1a — the toggle. OFF = fully silent stop (D12).
    if (!SettingsService.instance.subtitleAutoDownload.value) {
      _log('auto OFF (D12) — not fetching "$path"');
      return;
    }

    // Guard 4 — one try per file per session; and never two concurrent.
    if (_failedThisSession.contains(path)) {
      _log('already failed/empty this session — not retrying "$path" '
          '(a credential edit gives it back)');
      return;
    }
    if (!_inFlight.add(path)) return;

    try {
      // The mpv track report settles right after start-file — and on a
      // zap it fires more than once (the outgoing file's tracks torn
      // down, then the new file's opened). A one-beat read can catch
      // the DEPLETED list and false-fetch a video that has embedded
      // subs (D7): wait for the report to go quiet (bounded), then
      // read the settled state.
      await _awaitSettledTracks();
      if (_autoWantedPath != path) {
        _log('zapped mid-settle — dropping "$path"');
        return;
      }

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
      if (hasSub) {
        _log('D7: mpv already reports ${subRows.length} subtitle row(s) '
            'for "$path" — nothing to fetch');
        return;
      }
      if (_hasMatchingSibling(path)) {
        _log('D7: a matching sibling subtitle already sits next to '
            '"$path" — nothing to fetch');
        return;
      }

      // Guard 1b — the key. Everything else would fetch: this is the
      // one honest `cc not configured` moment (D11). Still tries
      // afterwards (the key may arrive mid-session) — NOT marked failed.
      final SettingsService settings = SettingsService.instance;
      if (settings.subtitleApiKey.value.isEmpty) {
        _log('no API key — `cc not configured` (D11)');
        _noticeCc();
        return;
      }
      // Engine pauses — silent (their cards already spoke).
      if (_quotaPaused) {
        _log('quota-paused (429/402 earlier) — silent until relaunch');
        return;
      }
      if (_authPaused) {
        _log('auth-paused (401 earlier) — silent until a credential '
            'changes');
        return;
      }

      // One more wanted-check before quota is spent: a fast zapper
      // never makes SALU buy the previous episode's subs.
      if (_autoWantedPath != path) {
        _log('zapped before the hash — dropping "$path"');
        return;
      }

      // §3.2 — moviehash, preferred → English. No query step (D9).
      final String? hash = await _movieHash(path);
      if (hash == null) {
        _log('moviehash failed (file under 64 KB, or unreadable) — '
            '"$path" marked for the session');
        _failedThisSession.add(path);
        return;
      }
      _log('moviehash $hash for "$path"');
      final String pref = LanguageNames.normalize(
          SettingsService.instance.subtitleLanguage.value);
      List<SubtitleResult>? hits = await _search(
        <String, String>{'moviehash': hash, 'languages': pref},
      );
      bool gaveUp = false;
      if (hits == null) {
        _log('hash search ($pref) failed — notice already spoken or a '
            'wall paused the engine');
        return; // notice already spoken (or silent pause)
      }
      _log('hash search ($pref): ${hits.length} hit(s)');
      if (hits.isEmpty && pref != 'en') {
        hits = await _search(
          <String, String>{'moviehash': hash, 'languages': 'en'},
        );
        if (hits == null) return;
        _log('hash search fallback (en): ${hits.length} hit(s)');
      }
      if (hits.isEmpty) {
        // Music videos & home movies are free hits to nothing (§3.2) —
        // silence, marked for the session.
        gaveUp = true;
      }
      if (gaveUp) {
        _log('no hits for this hash — silence, "$path" marked for the '
            'session (§3.2)');
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
    // A missing login is not this FILE's fault - the viewer may still
    // sign in later in the session, so it stays silent and unmarked
    // (D10: the auto engine never speaks). Signing in now retries it —
    // see [_retryCurrent].
    if (outcome?.status == SubtitleSaveStatus.notSignedIn) {
      _log('no login yet (username or password empty) — AUTO stays '
          'silent and unmarked; typing it retries this file');
      return;
    }
    if (outcome == null ||
        (outcome.status == SubtitleSaveStatus.failed &&
            !_quotaPaused &&
            !_authPaused)) {
      // A silent network blip marks this file for the session; quota and
      // auth walls already paused the engine with their one card, so a
      // wall trip is NOT a per-file failure.
      if (outcome == null || !_quotaPaused && !_authPaused) {
        _log('save failed — "$path" marked for the session');
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
      _log('applying "${outcome.fileName}" to the loaded video');
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
      _log('manual search refused — engine paused '
          '(${_quotaPaused ? 'quota' : 'auth'} wall)');
      return const <SubtitleResult>[];
    }
    final List<SubtitleResult>? rows =
        await _search(<String, String>{'query': q});
    if (rows == null) return const <SubtitleResult>[];
    _log('manual search "$q" → ${rows.length} row(s)');
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
      _log('D8 name already beside the video — no quota spent: $sibling');
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.alreadySaved,
          fileName: name,
          path: sibling);
    }
    final String tempCopy =
        p.join(Directory.systemTemp.path, 'salu_subs', name);
    if (await File(tempCopy).exists()) {
      _log('D8 name already in the temp fallback — no quota spent: '
          '$tempCopy');
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.alreadySaved,
          fileName: name,
          path: tempCopy);
    }
    if (SettingsService.instance.subtitleApiKey.value.isEmpty) {
      _log('no API key — `cc not configured` (D11)');
      _noticeCc();
      return null;
    }
    if (_quotaPaused) {
      _log('quota-paused (429/402 earlier) — refusing "$name" until '
          'relaunch');
      return null;
    }
    if (_authPaused) {
      _log('auth-paused (401 earlier) — refusing "$name" until a '
          'credential changes');
      return null;
    }
    // §4: `/download` is key **and** Bearer. With no login there is no
    // token, so no request is spent and nothing is written — the reason
    // is handed back instead (the manual Save speaks it, D10 keeps the
    // AUTO engine quiet).
    if (!_hasLogin) {
      final SettingsService s = SettingsService.instance;
      final String have = <String>[
        if (s.subtitleUsername.value.isEmpty) 'username EMPTY',
        if (s.subtitlePassword.value.isEmpty) 'password EMPTY',
      ].join(', ');
      _log('no login ($have) — /download needs a Bearer token only '
          '/login can mint (§4)');
      return const SubtitleSaveOutcome(
          status: SubtitleSaveStatus.notSignedIn, fileName: '', path: null);
    }

    final Uint8List? bytes = await _download(result.fileId);
    if (bytes == null) {
      return const SubtitleSaveOutcome(
          status: SubtitleSaveStatus.failed, fileName: '', path: null);
    }

    // Beside the movie; unwritable → temp, same name (D8).
    try {
      await File(sibling).writeAsBytes(bytes, flush: true);
      _log('saved ${bytes.length} byte(s) beside the video: $sibling');
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.saved, fileName: name, path: sibling);
    } catch (error) {
      _log('write beside the video failed ($error) — trying the temp '
          'fallback');
      // Fall through to the temp fallback.
    }
    try {
      final Directory dir =
          Directory(p.join(Directory.systemTemp.path, 'salu_subs'));
      await dir.create(recursive: true);
      final String temp = p.join(dir.path, name);
      await File(temp).writeAsBytes(bytes, flush: true);
      _log('saved ${bytes.length} byte(s) in the temp fallback: $temp');
      return SubtitleSaveOutcome(
          status: SubtitleSaveStatus.saved, fileName: name, path: temp);
    } catch (error) {
      _log('temp fallback write failed too ($error) — nothing saved');
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
    if (outcome == null) {
      _speakSaveFailure(null);
      return null;
    }
    final SubtitleSaveStatus status = outcome.status;
    if (status == SubtitleSaveStatus.saved ||
        status == SubtitleSaveStatus.alreadySaved) {
      OsdController.instance.show(OsdSubtitleCard.saved(
        name: outcome.fileName,
        already: status == SubtitleSaveStatus.alreadySaved,
      ));
    } else {
      _speakSaveFailure(outcome);
    }
    return outcome;
  }

  /// §6.5 **Save & Load** — the same write + apply NOW via
  /// [PlayerService.loadExternalSubtitle]; the already-saved target
  /// applies its existing local copy (§6.5: ONE download, the second
  /// tap applies the file). No card while it works: Save & Load's
  /// feedback is the subs on screen + the marked panel row (§6.6, D10).
  /// A failure does speak — a tap is never answered with silence
  /// (owner, 2026-09-13).
  Future<SubtitleSaveOutcome?> saveAndLoad(
      SubtitleResult result, String videoPath) async {
    final String canonical = MediaUtils.canonicalPath(videoPath);
    final SubtitleSaveOutcome? outcome = await _saveCore(result, canonical);
    if (outcome == null) {
      _speakSaveFailure(null);
      return null;
    }
    final SubtitleSaveStatus status = outcome.status;
    if (status != SubtitleSaveStatus.saved &&
        status != SubtitleSaveStatus.alreadySaved) {
      _speakSaveFailure(outcome);
      return outcome;
    }
    if (outcome.path != null &&
        PlayerService.instance.currentPath.value == canonical) {
      unawaited(PlayerService.instance.loadExternalSubtitle(outcome.path!));
    }
    return outcome;
  }

  /// A Save tap is a deliberate human act — it must never fail in
  /// silence (owner's call, 2026-09-13). The AUTO engine keeps D10's
  /// silence; only the two manual entry points speak, and they speak on
  /// every tap: the once-per-session flags are the background engine's
  /// own business (§3.5), not a reason to go mute when a human asked
  /// twice.
  void _speakSaveFailure(SubtitleSaveOutcome? outcome) {
    final SubtitleSaveStatus? status = outcome?.status;
    if (status == SubtitleSaveStatus.notSignedIn) {
      OsdController.instance.show(const OsdSubtitleCard.signIn());
      return;
    }
    if (status == SubtitleSaveStatus.failed) {
      OsdController.instance.show(const OsdSubtitleCard.downloadFailed());
      return;
    }
    // `null` — nothing was attempted at all: no key, or a wall that
    // already paused the engine (§3.5). Name the wall; the words are
    // the ones the deck already owns. A 401 names the half that was
    // actually rejected — `/login` refusing the username+password is a
    // different repair than `/subtitles` refusing the key, and pointing
    // at the key for both sent the viewer to the one field that was fine.
    if (_authPaused) {
      OsdController.instance.show(_loginRejected
          ? const OsdSubtitleCard.checkLogin()
          : const OsdSubtitleCard.checkKey());
    } else if (_quotaPaused) {
      OsdController.instance.show(const OsdSubtitleCard.limit());
    } else {
      OsdController.instance.show(const OsdSubtitleCard.cc());
    }
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
        _log('GET /subtitles → 401 (API key rejected) — pausing until a '
            'credential changes');
        _authPaused = true;
        _noticeKey();
        return null;
      }
      if (r.statusCode == 429 || r.statusCode == 402) {
        _log('GET /subtitles → ${r.statusCode} (rate/quota wall) — '
            'pausing until relaunch');
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode != 200) {
        _log('GET /subtitles → ${r.statusCode}: ${_bodyPeek(r)}');
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic> data = (body['data'] as List?) ?? const [];
      return data
          .map(_resultFrom)
          .whereType<SubtitleResult>()
          .toList(growable: false);
    } catch (error) {
      _log('GET /subtitles threw ($error) — network down or timed out, '
          'silent (§3.5)');
      return null; // network down / timeout — silent (§3.5).
    }
  }

  /// The server's own words, trimmed to one console line — the reason a
  /// request died is in the body (`403 {"message":"Quota exceeded"}`),
  /// and throwing it away is what made every failure look identical.
  /// Never logged from the UI: this is the dev console only.
  static String _bodyPeek(http.Response r) {
    final String text = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    return text.length <= 240 ? text : '${text.substring(0, 240)}…';
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

  /// Bearer token for `/download` — one silent login per session (D13).
  /// The password is persisted scrambled now (D13 amended 2026-09-13), so
  /// this fires on the first download of a session with no UI involved;
  /// the TOKEN itself is still memory-only. Returns `null` on any failure:
  /// 401 already spoke + paused.
  Future<String?> _ensureToken() async {
    if (_token != null) return _token;
    final SettingsService s = SettingsService.instance;
    if (s.subtitleUsername.value.isEmpty ||
        s.subtitlePassword.value.isEmpty) {
      // Credentials are the user's problem statement; with a key but no
      // login, download is simply unavailable (§2.1 — key-only = search
      // without download). Nothing to surface: the fields exist in
      // settings; silence keeps D10.
      _log('/login skipped — username or password is empty (the API key '
          'alone can search, never download: §4)');
      return null;
    }
    // The password is NEVER logged — not here, not anywhere. The username
    // already sits in prefs unscrambled, so naming it costs nothing and
    // catches the classic .org-vs-.com account mix-up in one glance.
    _log('POST /login as "${s.subtitleUsername.value}"');
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
              'password': s.subtitlePassword.value,
            }),
          )
          .timeout(_timeout);
      if (r.statusCode == 401) {
        // A 401 HERE is the username/password pair being refused — not the
        // API key (the key just passed `/subtitles` to get this far).
        // Naming the key sent the viewer to the one field that was fine.
        _log('POST /login → 401: the username/password pair was refused '
            '(opensubtitles.com accounts are separate from opensubtitles.'
            'org ones). ${_bodyPeek(r)}');
        _authPaused = true;
        _loginRejected = true;
        _noticeLogin();
        return null;
      }
      if (r.statusCode == 429) {
        _log('POST /login → 429 (login rate limit: 1/s) — pausing until '
            'relaunch');
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        _log('POST /login → ${r.statusCode}: ${_bodyPeek(r)}');
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final String token = '${body['token'] ?? ''}';
      if (token.isEmpty) {
        _log('POST /login → 200 but no token in the body: ${_bodyPeek(r)}');
        return null;
      }
      _log('POST /login → 200, Bearer token minted (${token.length} chars)');
      _token = token; // memory only (D13 — never persisted).
      return token;
    } catch (error) {
      _log('POST /login threw ($error) — network down or timed out');
      return null;
    }
  }

  /// `/download` → follow the single-use link immediately (§3.3-1),
  /// decompressing gzip (§3.3-2). `null` = the failure path; every branch
  /// says why in the dev console ([_log]) even where the deck must stay
  /// quiet (D10).
  Future<Uint8List?> _download(int fileId) async {
    if (_quotaPaused || _authPaused) return null;
    final String? token = await _ensureToken();
    if (token == null) return null;
    _log('POST /download {file_id: $fileId}');
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
        _log('POST /download → 401 (token refused) — dropping it, '
            'pausing until a credential changes. ${_bodyPeek(r)}');
        _token = null;
        _authPaused = true;
        _noticeKey();
        return null;
      }
      if (r.statusCode == 429 || r.statusCode == 402 || r.statusCode == 403) {
        // 403 is the quota wall's usual face on a free account (§3.5's
        // ~10 downloads/day) — the API also uses it for a bad file_id,
        // which is why the body is in the log.
        _log('POST /download → ${r.statusCode} (quota/rate wall) — '
            'pausing until relaunch. ${_bodyPeek(r)}');
        _quotaPaused = true;
        _noticeLimit();
        return null;
      }
      if (r.statusCode != 200) {
        _log('POST /download → ${r.statusCode}: ${_bodyPeek(r)}');
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final String link = '${body['link'] ?? ''}';
      if (link.isEmpty) {
        _log('POST /download → 200 but no link in the body: '
            '${_bodyPeek(r)}');
        return null;
      }
      _log('following the download link');
      final http.Response file =
          await _client.get(Uri.parse(link)).timeout(_timeout);
      if (file.statusCode != 200) {
        _log('GET link → ${file.statusCode}: ${_bodyPeek(file)}');
        return null;
      }
      Uint8List bytes = file.bodyBytes;
      // The API serves gzipped bodies unless asked otherwise (§3.3-2).
      // (GZipCodec's constructor is not const — dart:io's ZLibCodec
      // family takes mutable option fields.)
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        bytes = Uint8List.fromList(GZipCodec().decode(bytes));
        _log('gunzipped → ${bytes.length} byte(s)');
      }
      // Never write junk under the D8 name: the already-saved check would
      // then treat that broken file as the bought subtitle FOREVER (both
      // here and in the temp fallback), and every later Save would answer
      // `Already saved` while nothing ever showed on screen.
      if (bytes.isEmpty) {
        _log('GET link → 200 with an EMPTY body — refusing to save it');
        return null;
      }
      if (_looksLikeHtml(bytes)) {
        _log('GET link → 200 but the body is an HTML page, not a '
            'subtitle — refusing to save it. ${_bodyPeek(file)}');
        return null;
      }
      _log('downloaded ${bytes.length} byte(s)');
      return bytes;
    } catch (error) {
      _log('POST /download threw ($error) — network down or timed out');
      return null;
    }
  }

  /// An HTML document wearing a 200 — the shape a CDN/interstitial/error
  /// page arrives in when the download link has expired or was refused.
  /// Saving it as `movie.en.srt` is worse than saving nothing: mpv shows
  /// garbage, and the D8 name is then permanently "already saved".
  static bool _looksLikeHtml(Uint8List bytes) {
    final String head =
        utf8.decode(bytes.take(512).toList(), allowMalformed: true)
            .trimLeft()
            .toLowerCase();
    return head.startsWith('<!doctype html') ||
        head.startsWith('<html') ||
        head.startsWith('<head');
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

  /// Every card below is gated the same way: once per session (D10), and
  /// never from a [_retryCurrent] fetch — that one answers a keystroke, so
  /// it stays mute and leaves the session's card unspent for a moment the
  /// viewer actually caused. The flag is checked BEFORE the shown-flag is
  /// set, so a suppressed card is deferred, not consumed.

  /// D11 literal — owner's text, one card per session.
  void _noticeCc() {
    if (_backgroundRetry || _noticeCcShown) return;
    _noticeCcShown = true;
    OsdController.instance.show(const OsdSubtitleCard.cc());
  }

  void _noticeKey() {
    if (_backgroundRetry || _noticeKeyShown) return;
    _noticeKeyShown = true;
    OsdController.instance.show(const OsdSubtitleCard.checkKey());
  }

  /// The 401 that came from `/login` — the username/password pair, not the
  /// API key (§3.5). One card per session like the rest (D10); the manual
  /// Save path repeats it on every tap through [_speakSaveFailure].
  void _noticeLogin() {
    if (_backgroundRetry || _noticeLoginShown) return;
    _noticeLoginShown = true;
    OsdController.instance.show(const OsdSubtitleCard.checkLogin());
  }

  void _noticeLimit() {
    if (_backgroundRetry || _noticeLimitShown) return;
    _noticeLimitShown = true;
    OsdController.instance.show(const OsdSubtitleCard.limit());
  }
}
