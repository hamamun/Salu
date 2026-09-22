import 'dart:io';

import '../../ui/osd/osd_controller.dart';
import '../browser_service.dart';
import '../channel_load_service.dart';
import '../media_utils.dart';
import '../open_media_service.dart';
import '../player_service.dart';
import '../queue_service.dart';
import '../settings_service.dart';
import '../subtitle_service.dart';
import '../transport_actions.dart';
import '../tune/tune_model.dart';
import '../tune/tune_presets.dart';
import '../tune_service.dart';
import '../url_library_service.dart';
import '../window_state_service.dart';
import 'remote_fs_service.dart';
import 'remote_protocol.dart';
import 'remote_web_media_bridge.dart';

class RemoteCommandResponse {
  const RemoteCommandResponse.ok([this.result = const <String, Object?>{}])
      : code = null,
        message = null;
  const RemoteCommandResponse.error(this.code, this.message) : result = null;

  final Map<String, Object?>? result;
  final String? code;
  final String? message;

  bool get ok => code == null;
}

/// Maps the wire verbs onto SALU's existing service facades. It contains no
/// socket code; that split keeps command semantics testable and prevents a
/// second transport implementation from appearing in the remote layer.
class RemoteCommandHandler {
  RemoteCommandHandler({
    Future<void> Function()? ensurePlayerAndFocus,
    void Function()? onControl,
    RemoteWebMediaBridge? webMedia,
  })  : _ensurePlayerAndFocus = ensurePlayerAndFocus,
        _onControl = onControl,
        webMedia = webMedia ?? RemoteWebMediaBridge();

  final Future<void> Function()? _ensurePlayerAndFocus;
  final void Function()? _onControl;
  final RemoteWebMediaBridge webMedia;
  final Map<int, SubtitleResult> _subtitleResults = <int, SubtitleResult>{};
  DateTime? _lastFsList;

  PlayerService get player => PlayerService.instance;
  QueueService get queue => QueueService.instance;
  TransportActions get transport => TransportActions.instance;
  SettingsService get settings => SettingsService.instance;

  Future<RemoteCommandResponse> handle(RemoteCommand command) async {
    final Map<String, Object?> a = command.args;
    try {
      switch (command.verb) {
        case 'play_pause':
          if (!_hasQueuedMedia) return _nothingPlaying();
          await _focusForPlayback();
          transport.playOrPause(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'stop':
          if (!_hasQueuedMedia) return _nothingPlaying();
          transport.stop(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'next':
          if (!_hasQueuedMedia || !player.hasNextItem) return _nothingPlaying();
          await _focusForPlayback();
          transport.next(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'previous':
          if (!_hasQueuedMedia || !player.hasPreviousItem) return _nothingPlaying();
          await _focusForPlayback();
          transport.previous(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'seek_by':
          final double delta = _number(a['delta']);
          if (!_seekable) return _notSeekable();
          await _focusForPlayback();
          transport.resetSeekRamps();
          transport.seekBy(
            Duration(milliseconds: delta.round()),
            mark: delta < 0 ? OsdMark.seekBack : OsdMark.seekForward,
            fromRemote: true,
          );
          return const RemoteCommandResponse.ok();
        case 'seek_to':
          if (!_seekable) return _notSeekable();
          final double position = _number(a['position']);
          await _focusForPlayback();
          await transport.seekTo(Duration(milliseconds: position.round()), fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'set_volume':
          await transport.setVolume(_number(a['value']), fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'volume_step':
          final int delta = _number(a['delta']).round();
          if (delta >= 0) {
            transport.volumeUp(fromRemote: true);
          } else {
            transport.volumeDown(fromRemote: true);
          }
          return const RemoteCommandResponse.ok();
        case 'mute_toggle':
          transport.toggleMute(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'shuffle_toggle':
          await transport.toggleShuffle(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'repeat_cycle':
          await transport.cycleRepeat(fromRemote: true);
          return const RemoteCommandResponse.ok();
        case 'take_control':
          _onControl?.call();
          return const RemoteCommandResponse.ok();
        case 'ping':
          return RemoteCommandResponse.ok(<String, Object?>{
            'type': 'pong',
            'at': a['at'],
            'serverAt': DateTime.now().millisecondsSinceEpoch,
          });
        case 'state_get':
          return const RemoteCommandResponse.ok(<String, Object?>{'state': true});
        case 'queue_get':
          return _queueGet(a);
        case 'queue_jump':
          return await _queueJump(a);
        case 'queue_clear':
          return await _queueClear();
        case 'restart':
          return await _restart();
        case 'fs_places':
          return _fsPlaces();
        case 'fs_list':
          return _fsList(a);
        case 'fs_open':
          return await _fsOpen(a);
        case 'fs_load_sub':
          return await _fsLoadSubtitle(a);
        case 'library_get':
          return _libraryGet();
        case 'library_play':
          return await _libraryPlay(a);
        case 'library_add':
          return await _libraryAdd(a);
        case 'library_remove':
          return _libraryRemove(a);
        case 'open_url':
          return await _openUrl(a);
        case 'tune_get':
          return _tuneGet();
        case 'eq_gesture':
          if (a['phase'] == 'begin') {
            TuneService.instance.beginGesture();
          } else if (a['phase'] == 'end') {
            await TuneService.instance.endGesture();
          } else {
            return const RemoteCommandResponse.error(
              RemoteErrorCode.invalidArguments,
              'Unknown EQ gesture phase.',
            );
          }
          return const RemoteCommandResponse.ok();
        case 'eq_band':
          final int index = _number(a['index']).round();
          TuneService.instance.setBandGain(index, _number(a['db']));
          return const RemoteCommandResponse.ok();
        case 'eq_set':
          final List<double>? gains = _numbers(a['gains']);
          if (gains == null || gains.isEmpty) return _invalid();
          final TuneService tune = TuneService.instance;
          for (int i = 0; i < gains.length && i < 10; i++) {
            tune.setBandGain(i, gains[i], commit: false);
          }
          await tune.endGesture();
          return const RemoteCommandResponse.ok();
        case 'eq_preset':
          final String? key = a['key'] as String?;
          if (key == 'my') {
            TuneService.instance.applyMy();
          } else if (key != null && TunePresets.presetByKey(
                  key, TuneService.instance.fileKind.value) !=
              null) {
            TuneService.instance.selectStop(TunePart.eq, key);
          } else {
            return const RemoteCommandResponse.error(
              RemoteErrorCode.noPreset,
              'Unknown equalizer preset.',
            );
          }
          return const RemoteCommandResponse.ok();
        case 'eq_reset':
          TuneService.instance.resetBands();
          return const RemoteCommandResponse.ok();
        case 'eq_save_my':
          TuneService.instance.saveMy();
          return const RemoteCommandResponse.ok();
        case 'auto_eq':
          await settings.setAutoEq(a['on'] == true);
          return const RemoteCommandResponse.ok();
        case 'speed_set':
          final String? key = a['key'] as String?;
          if (key == null || !TunePresets.speedStops.any((s) => s.key == key)) {
            return const RemoteCommandResponse.error(
              RemoteErrorCode.noPreset,
              'Unknown playback speed.',
            );
          }
          TuneService.instance.selectStop(TunePart.speed, key);
          return const RemoteCommandResponse.ok();
        case 'subs_get':
          return _subsGet();
        case 'sub_select':
          return await _subSelect(a);
        case 'sub_delay':
          await player.setSubDelay(_number(a['seconds']));
          return const RemoteCommandResponse.ok();
        case 'sub_delay_step':
          await player.setSubDelay(
              player.subDelay.value + _number(a['delta']));
          return const RemoteCommandResponse.ok();
        case 'sub_delay_reset':
          await player.resetSubDelay();
          return const RemoteCommandResponse.ok();
        case 'subs_search':
          return await _subsSearch(a);
        case 'subs_download':
          return await _subsDownload(a);
        case 'subs_auto':
          await settings.setSubtitleAutoDownload(a['on'] == true);
          return const RemoteCommandResponse.ok();
        case 'subs_lang':
          final String? code = a['code'] as String?;
          if (code == null || code.trim().isEmpty) return _invalid();
          await settings.setSubtitleLanguage(code.trim());
          return const RemoteCommandResponse.ok();
        case 'mode_set':
          final String? mode = a['mode'] as String?;
          if (mode == 'player') {
            await BrowserService.instance.setMode(SaluMode.player);
          } else if (mode == 'web') {
            await BrowserService.instance.setMode(SaluMode.web);
          } else {
            return _invalid();
          }
          return const RemoteCommandResponse.ok();
        case 'fullscreen_toggle':
          await WindowStateService.instance.toggleFullscreen();
          return const RemoteCommandResponse.ok();
        case 'fullscreen_set':
          await WindowStateService.instance.setFullscreen(a['on'] == true);
          return const RemoteCommandResponse.ok();
        case 'browser_nav':
          final String? action = a['action'] as String?;
          if (action == null ||
              !const <String>{'back', 'forward', 'reload', 'stop'}.contains(action)) {
            return _invalid();
          }
          if (!await _navigateBrowser(action)) return _busy();
          return const RemoteCommandResponse.ok();
        case 'browser_open':
          final String? url = a['url'] as String?;
          if (url == null || url.trim().isEmpty) return _invalid();
          await BrowserService.instance.openInBrowser(url.trim());
          return const RemoteCommandResponse.ok();
        case 'web_media_get':
          return await _webMediaGet();
        case 'web_media_toggle':
          return await _webWrite(await webMedia.toggle());
        case 'web_media_seek':
          return await _webWrite(await webMedia.seek(
              to: a['to'] is num ? _number(a['to']) : null,
              delta: a['delta'] is num ? _number(a['delta']) : null));
        case 'web_media_volume':
          return await _webWrite(await webMedia.volume(_number(a['percent'])));
        case 'web_media_mute':
          return await _webWrite(await webMedia.mute(a['on'] == true));
        case 'web_media_fullscreen':
          return await _webWrite(await webMedia.fullscreen());
        default:
          return const RemoteCommandResponse.error(
            RemoteErrorCode.unknownCommand,
            'Unknown remote command.',
          );
      }
    } on RemoteFsException catch (error) {
      return RemoteCommandResponse.error(error.code, error.message);
    } catch (_) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'The PC is busy — try again in a moment.',
      );
    }
  }

  bool get _hasQueuedMedia => player.hasMedia.value || queue.hasQueue;
  bool get _seekable => player.hasMedia.value &&
      !queue.isChannelList && player.duration.value > Duration.zero;

  Future<void> _focusForPlayback() async {
    await _ensurePlayerAndFocus?.call();
  }

  RemoteCommandResponse _nothingPlaying() => const RemoteCommandResponse.error(
        RemoteErrorCode.nothingPlaying,
        'Nothing is playing on the PC.',
      );
  RemoteCommandResponse _notSeekable() => const RemoteCommandResponse.error(
        RemoteErrorCode.notSeekable,
        'This media cannot be seeked.',
      );
  RemoteCommandResponse _invalid() => const RemoteCommandResponse.error(
        RemoteErrorCode.invalidArguments,
        'The remote command arguments are not valid.',
      );
  RemoteCommandResponse _busy() => const RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'The PC is busy — try again in a moment.',
      );

  RemoteCommandResponse _queueGet(Map<String, Object?> args) {
    final int from = _number(args['from']).round().clamp(0, queue.length).toInt();
    final int count = _number(args['count'] ?? 20).round().clamp(1, 100).toInt();
    final List<Object?> rows = <Object?>[];
    for (int i = from; i < queue.length && rows.length < count; i++) {
      final item = queue.itemAt(i);
      if (item == null) continue;
      rows.add(<String, Object?>{
        'index': i,
        'title': item.label,
        if (!queue.isChannelList) 'durationMs': null,
        'now': i == queue.index.value,
      });
    }
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'queue_result',
      'from': from,
      'count': rows.length,
      'total': queue.length,
      'rows': rows,
    });
  }

  Future<RemoteCommandResponse> _queueJump(Map<String, Object?> args) async {
    if (!queue.hasQueue) return _nothingPlaying();
    final int index = _number(args['index']).round().clamp(0, queue.length - 1).toInt();
    await _focusForPlayback();
    await player.playIndex(index);
    return const RemoteCommandResponse.ok();
  }

  /// `queue_clear` — the phone's Queue-card ✕ (remote.md §17.4).
  ///
  /// The phone has already asked "Clear the playlist?"; the PC then does
  /// exactly what its own bin does — stop and empty, with the same Undo card
  /// on screen ([TransportActions.clearQueue], the single definition of the
  /// action). Deliberately idempotent: an already-empty queue answers `ok`,
  /// because "the playlist is empty" is the state the phone asked for, not a
  /// failure — a double tap, or a phone that never saw the first ack, must
  /// not produce an error line.
  ///
  /// No window focus here: clearing never starts playback (§7.5/D8), and
  /// stealing focus to show an empty canvas would be rude.
  Future<RemoteCommandResponse> _queueClear() async {
    await transport.clearQueue();
    return const RemoteCommandResponse.ok();
  }

  /// `restart` — the phone's **Start over** seat, the mirror of the PC's
  /// Resume toast (remote.md §17.4).
  ///
  /// The same door as the toast's own Restart word-action
  /// ([TransportActions.restart]: jump to 0:00 and play), which also closes
  /// the toast — so the phone's seat disappears on the very next snapshot,
  /// exactly as it does when the PC closes the toast itself.
  ///
  /// The verb is deliberately *not* gated on the offer still being up: the
  /// seat's life is driven by the toast, and a tap that races the close (the
  /// 120 ms snapshot window) must do the obvious thing — start the loaded
  /// item over — rather than fail. All it needs is something loaded; with an
  /// empty engine it is `nothing_playing`, like every other transport verb.
  Future<RemoteCommandResponse> _restart() async {
    if (!player.hasMedia.value) return _nothingPlaying();
    await _focusForPlayback();
    transport.restart();
    return const RemoteCommandResponse.ok();
  }

  RemoteCommandResponse _fsPlaces() {
    if (!settings.remoteFileAccess.value) return _fileAccessOff();
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'fs_places_result',
      'places': RemoteFsService.instance.places(nowPlayingPath: player.currentPath.value).toJson(),
    });
  }

  RemoteCommandResponse _fsList(Map<String, Object?> args) {
    if (!settings.remoteFileAccess.value) return _fileAccessOff();
    final DateTime now = DateTime.now();
    if (_lastFsList != null && now.difference(_lastFsList!) < const Duration(milliseconds: 200)) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.tooFast,
        'File listing is being rate limited.',
      );
    }
    _lastFsList = now;
    final String? path = args['path'] as String?;
    if (path == null) return _invalid();
    final result = RemoteFsService.instance.list(
      path,
      from: _number(args['from']).round(),
      count: _number(args['count'] ?? 200).round(),
      filter: args['filter'] as String? ?? 'media',
      showSystem: args['showSystem'] == true,
    );
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'fs_result',
      ...result.toJson(),
    });
  }

  RemoteCommandResponse _fileAccessOff() => const RemoteCommandResponse.error(
        RemoteErrorCode.fileAccessOff,
        'File browsing is turned off on the PC.',
      );

  Future<RemoteCommandResponse> _fsOpen(Map<String, Object?> args) async {
    if (!settings.remoteFileAccess.value) return _fileAccessOff();
    final Object? rawPaths = args['paths'];
    if (rawPaths is! List || rawPaths.isEmpty || rawPaths.length > 500) return _invalid();
    final List<String> paths = <String>[];
    for (final Object? raw in rawPaths) {
      if (raw is! String) return _invalid();
      final String value = raw.trim();
      if (Directory(value).existsSync()) {
        paths.addAll(RemoteFsService.instance.collectMediaInFolder(value));
      } else {
        paths.add(RemoteFsService.instance.validateFile(value));
      }
    }
    final List<String> playable = paths
        .where((String value) => MediaUtils.isMedia(value) || MediaUtils.isPlaylist(value))
        .toList(growable: false);
    if (playable.isEmpty) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.pathNotFound,
        'That folder or file is no longer there.',
      );
    }
    final String mode = args['mode'] as String? ?? 'play';
    if (playable.any(MediaUtils.isPlaylist)) {
      await ChannelLoadService.instance.openSource(playable.first);
    } else if (mode == 'append') {
      await player.appendToQueue(playable);
    } else if (mode == 'queue') {
      if (player.hasMedia.value) {
        await player.appendToQueue(playable);
      } else {
        await player.openPaths(playable);
      }
    } else {
      await player.openPaths(playable);
    }
    return const RemoteCommandResponse.ok();
  }

  Future<RemoteCommandResponse> _fsLoadSubtitle(Map<String, Object?> args) async {
    if (!settings.remoteFileAccess.value) return _fileAccessOff();
    final String? raw = args['path'] as String?;
    if (raw == null) return _invalid();
    final String path = RemoteFsService.instance.validateFile(raw, subtitles: true);
    if (!player.hasMedia.value) return _nothingPlaying();
    await player.loadExternalSubtitle(path);
    return const RemoteCommandResponse.ok();
  }

  RemoteCommandResponse _libraryGet() {
    final entries = UrlLibraryService.instance.entries.value;
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'library_result',
      'maxEntries': UrlLibraryService.maxEntries,
      'entries': entries.map((e) => <String, Object?>{
        'name': e.name,
        'url': e.url,
        'health': e.health.name,
      }).toList(),
    });
  }

  Future<RemoteCommandResponse> _libraryPlay(Map<String, Object?> args) async {
    final String? url = args['url'] as String?;
    if (url == null || url.trim().isEmpty) return _invalid();
    await _focusForPlayback();
    await OpenMediaService.playUrl(url);
    return const RemoteCommandResponse.ok();
  }

  Future<RemoteCommandResponse> _libraryAdd(Map<String, Object?> args) async {
    final String? url = args['url'] as String?;
    if (url == null || !UrlLibraryService.looksLikeUrl(url)) return _invalid();
    final service = UrlLibraryService.instance;
    final int index = service.entries.value.indexWhere((e) => e.url == url.trim());
    if (index >= 0) {
      service.update(index, name: args['name'] as String?, url: url);
    } else if (!service.add(url, name: args['name'] as String?)) {
      return const RemoteCommandResponse.error('library_full', 'The saved stream list is full.');
    }
    return const RemoteCommandResponse.ok();
  }

  RemoteCommandResponse _libraryRemove(Map<String, Object?> args) {
    final String? url = args['url'] as String?;
    if (url == null) return _invalid();
    final int index = UrlLibraryService.instance.entries.value.indexWhere((e) => e.url == url);
    if (index >= 0) UrlLibraryService.instance.removeAt(index);
    return const RemoteCommandResponse.ok();
  }

  Future<RemoteCommandResponse> _openUrl(Map<String, Object?> args) async {
    final String? url = args['url'] as String?;
    if (url == null || url.trim().isEmpty) return _invalid();
    if (BrowserService.instance.isWeb) {
      await BrowserService.instance.openInBrowser(url.trim());
    } else {
      await _focusForPlayback();
      await OpenMediaService.playUrl(url.trim());
    }
    return const RemoteCommandResponse.ok();
  }

  RemoteCommandResponse _tuneGet() {
    final TuneService tune = TuneService.instance;
    final List<EqPreset> presets = TunePresets.forKind(tune.fileKind.value);
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'tune_result',
      'kind': tune.fileKind.value.name,
      'available': tune.available.value,
      'eq': tune.eq.value.gains,
      'eqStop': tune.eqStop.value,
      'custom': tune.eqCustom.value,
      'my': tune.mySlot.value?.gains,
      'autoPick': tune.autoPick.value,
      'autoEq': settings.autoEq.value,
      'presets': presets.map((p) => <String, Object?>{
        'key': p.key,
        'label': p.label,
        'gains': p.gains,
      }).toList(),
      'speed': tune.speedStop.value ?? 'x1',
      'speedValue': tune.speed.value,
      'speedKeys': TunePresets.speedStops.map((s) => <String, Object?>{
        'key': s.key,
        'label': s.label,
      }).toList(),
    });
  }

  RemoteCommandResponse _subsGet() {
    final PlayerService p = player;
    final SubtitleService subs = SubtitleService.instance;
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'subs_result',
      'delay': p.subDelay.value,
      'lang': settings.subtitleLanguage.value,
      'autoDownload': settings.subtitleAutoDownload.value,
      'engine': <String, Object?>{
        'key': subs.keyConfigured,
        'signedIn': subs.signedIn,
        'quotaPaused': subs.quotaPaused,
      },
      'tracks': <String, Object?>{
        'audio': p.trackSurface.value.audio.map(_track).toList(),
        'subs': <Object?>[
          ...p.trackSurface.value.embeddedSubs.map(_track),
          ...p.trackSurface.value.localSubs.map(_track),
        ],
      },
    });
  }

  Map<String, Object?> _track(dynamic track) => <String, Object?>{
        'id': track.id,
        'title': track.title,
        'lang': track.lang,
        'codec': track.codec,
        'channels': track.channels,
        'external': track.external,
        'selected': track.selected,
      };

  Future<RemoteCommandResponse> _subSelect(Map<String, Object?> args) async {
    final String? kind = args['kind'] as String?;
    final String? id = args['id'] as String?;
    if (kind == null || id == null) return _invalid();
    if (kind == 'sub') {
      if (id == 'no') {
        await player.selectSubOff();
      } else {
        final List<MpvTrack> tracks = <MpvTrack>[
          ...player.trackSurface.value.embeddedSubs,
          ...player.trackSurface.value.localSubs,
        ];
        MpvTrack? track;
        for (final MpvTrack candidate in tracks) {
          if (candidate.id == id) {
            track = candidate;
            break;
          }
        }
        if (track == null) return _invalid();
        await player.selectSubTrack(track);
      }
    } else if (kind == 'audio') {
      MpvTrack? track;
      for (final MpvTrack candidate in player.trackSurface.value.audio) {
        if (candidate.id == id) {
          track = candidate;
          break;
        }
      }
      if (track == null) return _invalid();
      await player.selectAudioTrack(track);
    } else {
      return _invalid();
    }
    return const RemoteCommandResponse.ok();
  }

  Future<RemoteCommandResponse> _subsSearch(Map<String, Object?> args) async {
    final String? query = args['query'] as String?;
    if (query == null || query.trim().isEmpty) return _invalid();
    final List<SubtitleResult> rows = await SubtitleService.instance.search(
      query,
      language: args['language'] as String?,
    );
    _subtitleResults
      ..clear()
      ..addEntries(rows.map((r) => MapEntry<int, SubtitleResult>(r.fileId, r)));
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'subs_results',
      'rows': rows.map((r) => <String, Object?>{
        'fileId': r.fileId,
        'language': r.language,
        'title': r.title,
        'release': r.release,
        'downloads': r.downloads,
        'ext': r.ext,
        'subLine': r.subLine,
      }).toList(),
    });
  }

  Future<RemoteCommandResponse> _subsDownload(Map<String, Object?> args) async {
    final int id = _number(args['fileId']).round();
    final SubtitleResult? result = _subtitleResults[id];
    if (result == null) return _invalid();
    if (!player.hasMedia.value || player.currentPath.value == null) return _nothingPlaying();
    final SubtitleService subs = SubtitleService.instance;
    if (!subs.keyConfigured) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noKey,
        'Add an OpenSubtitles key on the PC to search.',
      );
    }
    if (!subs.signedIn && !subs.loginConfigured) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.signedOut,
        'Sign in to OpenSubtitles on the PC to download.',
      );
    }
    if (subs.quotaPaused) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.quota,
        'OpenSubtitles download limit reached — try again tomorrow.',
      );
    }
    final SubtitleSaveOutcome? outcome =
        await subs.saveAndLoad(result, player.currentPath.value!);
    if (outcome == null || outcome.status == SubtitleSaveStatus.failed) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'The PC is busy — try again in a moment.',
      );
    }
    return RemoteCommandResponse.ok(<String, Object?>{
      'loaded': outcome.path != null,
      'fileName': outcome.fileName,
    });
  }

  Future<RemoteCommandResponse> _webMediaGet() async {
    final RemoteWebMediaResult result = await webMedia.get();
    if (!result.found) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebMedia,
        "This site's player can't be controlled from outside.",
      );
    }
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'web_media_result',
      ...result.toJson(),
    });
  }

  Future<RemoteCommandResponse> _webWrite(bool success) async {
    if (!success) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebMedia,
        "This site's player can't be controlled from outside.",
      );
    }
    return const RemoteCommandResponse.ok();
  }

  Future<bool> _navigateBrowser(String action) async {
    if (!<String>{'back', 'forward', 'reload', 'stop'}.contains(action)) return false;
    // BrowserService's callback is installed by BrowserScreen. The bridge
    // lives there to keep the active WebTab private to that widget.
    return BrowserService.instance.remoteNavigate(action);
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0;
  static List<double>? _numbers(Object? raw) => raw is List
      ? raw.whereType<num>().map((num n) => n.toDouble()).toList()
      : null;
}
