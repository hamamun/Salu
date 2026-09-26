import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../ui/osd/osd_controller.dart';
import '../browser_service.dart';
import '../channel_grouping.dart';
import '../channel_load_service.dart';
import '../channel_view_service.dart';
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
import '../web/web_address.dart';
import '../web/web_favourites_service.dart';
import '../window_state_service.dart';
import 'remote_fs_service.dart';
import 'remote_input_service.dart';
import 'remote_power_service.dart';
import 'remote_protocol.dart';
import 'remote_web_focus_bridge.dart';
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
    RemoteWebFocusBridge? webFocus,
    RemoteWebFullscreen? webFullscreen,
    RemoteInputService? input,
    RemotePowerService? power,
    Future<void> Function(String action)? onPowerAction,
  })  : _ensurePlayerAndFocus = ensurePlayerAndFocus,
        _onControl = onControl,
        webMedia = webMedia ?? RemoteWebMediaBridge(),
        webFocus = webFocus ?? RemoteWebFocusBridge(),
        _injectedWebFullscreen = webFullscreen,
        input = input ?? RemoteInputService.instance,
        power = power ?? RemotePowerService.instance,
        _onPowerAction = onPowerAction;

  final Future<void> Function()? _ensurePlayerAndFocus;
  final void Function()? _onControl;
  final RemoteWebMediaBridge webMedia;
  final RemoteWebFocusBridge webFocus;

  /// The PC's own pointer (pc_part.md C3).
  final RemoteInputService input;

  /// Power management (pc_part.md Part D · remote.md §17.15).
  final RemotePowerService power;
  final Future<void> Function(String action)? _onPowerAction;
  bool _powerPending = false;

  final RemoteWebFullscreen? _injectedWebFullscreen;

  /// The one fullscreen seat (pc_part.md C1). Built on demand from the live
  /// services unless a test injected its own seams.
  RemoteWebFullscreen get webFullscreen =>
      _injectedWebFullscreen ??
      RemoteWebFullscreen(
        executeScript: BrowserService.instance.isWeb
            ? webMedia.executeScript
            : null,
        pageClick: BrowserService.instance.isWeb
            ? BrowserService.instance.remotePageClick
            : null,
        pageFullscreen: () => BrowserService.instance.pageFullscreen.value,
        exitPage: BrowserService.instance.remotePageExitFullscreen,
        windowFullscreen: () => WindowStateService.instance.isFullscreen.value,
        setWindowFullscreen: WindowStateService.instance.setFullscreen,
      );
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
        case 'queue_groups':
          return _queueGroups();
        case 'queue_group_set':
          return _queueGroupSet(a);
        case 'queue_clear':
          return await _queueClear();
        case 'restart':
          return await _restart();
        case 'fs_places':
          return await _fsPlaces();
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
          // `home` added 2026-09-24 (pc_part.md C2 · remote.md §17.14.2).
          // An unknown action keeps answering invalid_arguments — the phone
          // falls back to `browser_open` with the origin it computes.
          if (action == null || !BrowserService.navActions.contains(action)) {
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
          // Superseded by `web_fullscreen` (§17.14.1); kept for the phone's
          // older-PC fallback path.
          return await _webWrite(await webMedia.fullscreen());
        case 'web_fullscreen':
          return await _webFullscreen(a);
        case 'web_mouse_move':
          return _webMouseMove(a);
        case 'web_mouse_click':
          return _webMouseClick(a);
        case 'web_bookmark_add':
          return _webBookmarkAdd(a);
        case 'web_tabs_get':
          return _webTabsGet();
        case 'web_tab_activate':
          return await _webTabActivate(a);
        case 'web_tab_close':
          return await _webTabClose(a);
        case 'web_tab_new':
          return await _webTabNew(a);
        case 'web_bookmarks_get':
          return _webBookmarksGet();
        case 'web_key':
          return await _webKey(a);
        case 'web_focus_get':
          return await _webFocusGet();
        case 'pc_sleep':
          return await _handlePower('sleep', a);
        case 'pc_shutdown':
          return await _handlePower('shutdown', a);
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
    // pc_part.md §10 instrumentation (temporary — drop after the live
    // pill check passes): every phone-driven play/seek funnels through
    // here, so a pill that dies on a remote action names this line in
    // the log first.
    debugPrint('[SALU] remote: focus-for-playback');
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

  /// `queue_groups` — the phone's group chips (pc_part.md §11): the
  /// CURRENT mode's groups in exactly [ChannelGrouping]'s descriptor-head
  /// order, each with the stable accordion key, its display name, its row
  /// count and the absolute queue index of its first row — what the phone
  /// inserts its headers at and `queue_jump`s to. Empty in Flat, and off
  /// a channel list, where the chips row has nothing to offer at all.
  RemoteCommandResponse _queueGroups() {
    final List<QueueItem> items = queue.items.value;
    if (items.isEmpty || !queue.isChannelList) {
      return const RemoteCommandResponse.ok(<String, Object?>{
        'groups': <Object?>[],
      });
    }
    final ChannelGroupMode mode = ChannelViewService.instance.groupMode.value;
    if (mode == ChannelGroupMode.flat) {
      return const RemoteCommandResponse.ok(<String, Object?>{
        'groups': <Object?>[],
      });
    }
    final List<int> all = List<int>.generate(items.length, (int i) => i);
    final List<ChannelGroup> groups =
        ChannelGrouping.buildGroups(items, all, mode);
    return RemoteCommandResponse.ok(<String, Object?>{
      'groups': <Object?>[
        for (final ChannelGroup group in groups)
          <String, Object?>{
            'key': group.key,
            'name': group.label,
            'count': group.indexes.length,
            'start': group.indexes.first,
          },
      ],
    });
  }

  /// `queue_group_set {by}` — the phone's chip moving the PC panel's
  /// pill choice (pc_part.md §11). A pure view change mirroring the
  /// panel's own `_chooseMode` at service level: set the mode, and when a
  /// grouped mode is chosen also open the group holding the playing
  /// channel (the panel's §10.5 rule). The queue is never touched; the
  /// next snapshot carries the new `queue.grouping`.
  RemoteCommandResponse _queueGroupSet(Map<String, Object?> args) {
    final String? by = args['by'] as String?;
    final ChannelGroupMode? mode = switch (by) {
      'flat' => ChannelGroupMode.flat,
      'category' => ChannelGroupMode.category,
      'language' => ChannelGroupMode.language,
      'country' => ChannelGroupMode.country,
      _ => null,
    };
    if (mode == null) return _invalid();
    final ChannelViewService view = ChannelViewService.instance;
    view.groupMode.value = mode;
    view.openGroup.value = mode == ChannelGroupMode.flat
        ? null
        : ChannelGrouping.keyFor(queue.items.value, queue.index.value, mode);
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

  /// `fs_places` — now awaits (pc_part.md §4): the drive scan runs the
  /// label pass off the handler isolate with a 2 s budget, so the answer
  /// is millisecond-fast on a healthy machine and budget-fast on a
  /// sleeping disk — the 3-second `busy` guard simply never fires.
  Future<RemoteCommandResponse> _fsPlaces() async {
    if (!settings.remoteFileAccess.value) return _fileAccessOff();
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'fs_places_result',
      'places': (await RemoteFsService.instance
              .places(nowPlayingPath: player.currentPath.value)).toJson(),
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
    // pc_part.md A1.5 — log the raw args of every web_media_* call for one
    // build; `el` names the element the read picked (A2.5, one line ends
    // every argument about which element a site exposed).
    debugPrint(
      '[SALU] remote: web_media_get → position=${result.position} '
      'duration=${result.duration} volume=${result.volume} '
      'seekable=${result.seekable}',
    );
    // §17.14.1 — `fullscreen` is the element's state NOW: the document's
    // own reading, or the host's (a page element that owns the screen via
    // ContainsFullScreenElementChanged), whichever says yes.
    final RemoteWebMediaResult shown = result.fullscreen ||
            BrowserService.instance.pageFullscreen.value
        ? result.withFullscreen(true)
        : result;
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'web_media_result',
      ...shown.toJson(),
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

  // ── Web tab strip + bookmarks + D-pad (pc_part.md A3–A5) ───────────────

  /// The tab-strip mirror (pc_part.md A4 · §17.13.2): bounded at the edge so
  /// a strip can never overflow the 8 KB frame — at most 50 rows, `title`
  /// capped at 80 and `url` at 180 characters, the real total always in
  /// `count`.
  RemoteCommandResponse _webTabsGet() {
    if (!BrowserService.instance.isWeb) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebTabs,
        'Tab control needs the browser open on the PC.',
      );
    }
    final List<WebTabMirror> tabs = BrowserService.instance.webTabs.value;
    final List<Object?> rows = <Object?>[];
    for (int i = 0; i < tabs.length && i < 50; i++) {
      final WebTabMirror t = tabs[i];
      rows.add(<String, Object?>{
        'index': i,
        'title': _truncate(t.title, 80),
        'url': t.url == null ? null : _truncate(t.url, 180),
        'active': t.active,
        'loading': t.loading,
        'hasMedia': t.hasMedia,
      });
    }
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'web_tabs_result',
      'tabs': rows,
      'active': tabs.indexWhere((WebTabMirror t) => t.active),
      'count': tabs.length,
    });
  }

  Future<RemoteCommandResponse> _webTabActivate(Map<String, Object?> a) =>
      _webTabChange('activate', _tabIndex(a));

  Future<RemoteCommandResponse> _webTabClose(Map<String, Object?> a) =>
      _webTabChange('close', _tabIndex(a));

  Future<RemoteCommandResponse> _webTabNew(Map<String, Object?> a) async {
    if (!BrowserService.instance.isWeb) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebTabs,
        'Tab control needs the browser open on the PC.',
      );
    }
    final String? url = a['url'] as String?;
    if (url != null && !_looksLikeUrl(url)) return _invalid();
    final String? outcome = await BrowserService.instance
        .remoteTabAction('new', null, url: url?.trim());
    if (outcome == null) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebTabs,
        'Tab control needs an updated SALU on the PC.',
      );
    }
    if (outcome == 'invalid_url') {
      // pc_part.md C5 — an address the browser cannot load answers
      // invalid_arguments rather than leaving the user on a blank tab.
      return const RemoteCommandResponse.error(
        RemoteErrorCode.invalidArguments,
        "That address can't be opened.",
      );
    }
    if (outcome == 'invalid') {
      // Only the screen refuses a new tab — its own cap (the strip's `+`
      // goes quiet there). Not a malformed argument, so say it plainly
      // rather than blaming the request.
      return const RemoteCommandResponse.error(
        RemoteErrorCode.invalidArguments,
        'The tab strip is at its limit.',
      );
    }
    // The new tab is active — the mirror now answers the index the screen
    // owns. A cheap re-read keeps the ack's `index` honest without racing
    // the frame the screen's own setState is about to paint.
    final int index = BrowserService.instance.webTabs.value
        .indexWhere((WebTabMirror t) => t.active);
    return RemoteCommandResponse.ok(<String, Object?>{
      'index': index < 0 ? null : index,
    });
  }

  Future<RemoteCommandResponse> _webTabChange(
    String action,
    int index,
  ) async {
    if (!BrowserService.instance.isWeb) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebTabs,
        'Tab control needs the browser open on the PC.',
      );
    }
    if (index < 0) return _invalid();
    final String? outcome =
        await BrowserService.instance.remoteTabAction(action, index);
    if (outcome == null) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebTabs,
        'Tab control needs an updated SALU on the PC.',
      );
    }
    if (outcome == 'tab_not_found') {
      // pc_part.md A4: a stale index answers tab_not_found — never close the
      // wrong page silently. The phone re-reads after every change, so a
      // stale index self-heals in one round trip.
      return const RemoteCommandResponse.error(
        RemoteErrorCode.tabNotFound,
        'That tab is no longer open.',
      );
    }
    if (outcome == 'invalid') return _invalid();
    return const RemoteCommandResponse.ok();
  }

  /// A stale index answers `tab_not_found` rather than closing the wrong page
  /// (pc_part.md A4): the handler is the screen's own close, and only the
  /// screen knows what its strip holds *now*.
  int _tabIndex(Map<String, Object?> a) {
    final Object? raw = a['index'];
    if (raw is! num || raw.toInt() < 0) return -1;
    return raw.toInt();
  }

  /// The read-only bookmark mirror (pc_part.md A5 · §17.13.4). Every entry
  /// is the browser's own favourited page, never SALU's URL library — a phone
  /// that can silently rewrite the bookmark bar is a phone that can lose it.
  RemoteCommandResponse _webBookmarksGet() {
    final List<WebFavourite> entries =
        WebFavouritesService.instance.favourites.value;
    final List<Object?> rows = <Object?>[];
    for (int i = 0; i < entries.length && i < 200; i++) {
      final WebFavourite f = entries[i];
      rows.add(<String, Object?>{
        'name': _truncate(f.name, 80),
        'url': _truncate(f.url, 180),
        'folder': f.folder.isEmpty ? '' : _truncate(f.folder, 80),
      });
    }
    return RemoteCommandResponse.ok(<String, Object?>{
      'type': 'web_bookmarks_result',
      'entries': rows,
    });
  }

  String _truncate(String? value, int max) {
    if (value == null || value.length <= max) return value ?? '';
    return value.substring(0, max);
  }

  /// `web_key` (pc_part.md A3 · §17.13.5): walk the page's own tab order.
  /// The ack carries the focus payload — label/tag/index/count/editable —
  /// so the phone's card names what it is about to click. The focus ring is
  /// drawn page-side by the injected script (part of the package, not a
  /// follow-up): every key re-injects it onto the current element.
  Future<RemoteCommandResponse> _webKey(Map<String, Object?> a) async {
    final String? key = a['key'] as String?;
    if (key == null || !RemoteWebFocusBridge.supportedKeys.contains(key)) {
      // pc_part.md A3.8 — an unknown key is invalid_arguments, never a
      // silent ack that leaves the pad lying about what happened.
      return _invalid();
    }
    final RemoteWebFocusResult focus = await webFocus.key(key);
    return _focusAck(focus);
  }

  /// `web_focus_get` (pc_part.md A3.6): the current seat, reported without
  /// moving it — the same payload every `web_key` ack carries.
  Future<RemoteCommandResponse> _webFocusGet() async {
    final RemoteWebFocusResult focus = await webFocus.get();
    return _focusAck(focus);
  }

  /// No page reachable (no focus reported, or not in Web mode at all) is the
  /// honest "nothing focused" answer — the phone draws *Nothing focused yet*.
  /// A fake seat would be worse (pc_part.md A3's found:false honesty).
  RemoteCommandResponse _focusAck(RemoteWebFocusResult focus) {
    final Map<String, Object?> payload = focus.found
        ? focus.toJson()
        : <String, Object?>{
            'label': '',
            'tag': 'body',
            'index': 0,
            'count': 0,
            'editable': false,
          };
    return RemoteCommandResponse.ok(<String, Object?>{'focus': payload});
  }

  // ── One fullscreen seat · trackpad · add-only bookmarks (Part C) ──────

  /// `web_fullscreen {on?}` (pc_part.md C1 · remote.md §17.14.1): the PC
  /// picks the target — the page's own player first (injected request, then
  /// a real click on the player's own control), the SALU window only when
  /// the page has no reachable player — and says which one happened, so
  /// the phone's icon never lies.
  Future<RemoteCommandResponse> _webFullscreen(Map<String, Object?> a) async {
    final Object? rawOn = a['on'];
    if (rawOn != null && rawOn is! bool) return _invalid();
    final RemoteFullscreenOutcome outcome =
        await webFullscreen.run(on: rawOn as bool?);
    debugPrint('[SALU] remote: web_fullscreen on=$rawOn → '
        'fullscreen=${outcome.fullscreen} target=${outcome.target}');
    return RemoteCommandResponse.ok(outcome.toJson());
  }

  /// `web_mouse_move {dx, dy}` (pc_part.md C3): relative, CSS pixels, the
  /// phone's gain already applied. Synchronous — move, ack, next; never a
  /// page-side await (25 of these arrive a second).
  RemoteCommandResponse _webMouseMove(Map<String, Object?> a) {
    final Object? dx = a['dx'];
    final Object? dy = a['dy'];
    if (dx is! num || dy is! num || !dx.isFinite || !dy.isFinite) {
      return _invalid();
    }
    if (!input.available) return _noWebMouse();
    if (!input.moveBy(dx.toDouble(), dy.toDouble())) return _noWebMouse();
    return const RemoteCommandResponse.ok();
  }

  /// `web_mouse_click {button, count}` (pc_part.md C3): a real click at the
  /// pointer's current position. `button` defaults to left, `count` to 1.
  RemoteCommandResponse _webMouseClick(Map<String, Object?> a) {
    final Object? rawButton = a['button'];
    final Object? rawCount = a['count'];
    final String button = rawButton == null ? 'left' : '$rawButton';
    final int? count = rawCount == null
        ? 1
        : (rawCount is num && rawCount == rawCount.roundToDouble()
            ? rawCount.toInt()
            : null);
    if (!RemoteInputService.buttons.contains(button) ||
        count == null ||
        !RemoteInputService.clickCounts.contains(count)) {
      return _invalid();
    }
    if (!input.available) return _noWebMouse();
    if (!input.click(button, count)) return _noWebMouse();
    return const RemoteCommandResponse.ok();
  }

  RemoteCommandResponse _noWebMouse() => const RemoteCommandResponse.error(
        RemoteErrorCode.noWebMouse,
        "The PC's pointer can't be moved right now.",
      );

  /// `web_bookmark_add {url, name?}` (pc_part.md C4 · remote.md §17.14.4):
  /// **append only** into the browser's own bookmark store (the one
  /// `web_bookmarks_get` reads), top level. The same page twice is a no-op,
  /// never a duplicate; nothing else in the store can change — this verb
  /// has no way to rename, delete or reorder.
  RemoteCommandResponse _webBookmarkAdd(Map<String, Object?> a) {
    final Object? rawUrl = a['url'];
    final Object? rawName = a['name'];
    if (rawUrl is! String || (rawName != null && rawName is! String)) {
      return _invalid();
    }
    final String? url = WebAddress.urlFrom(rawUrl);
    if (url == null) return _invalid();
    final WebFavouritesService store = WebFavouritesService.instance;
    final WebFavourite? existing = store.findFor(url);
    if (existing != null) return _bookmarkAck(existing);
    final String? name = rawName is String && rawName.trim().isNotEmpty
        ? _truncate(rawName.trim(), 200)
        : null;
    if (!store.add(url: url, name: name)) {
      // The store has a fixed number of seats (WebFavouritesService
      // .maxEntries). A full store is honest `no_web_bookmarks`: the phone
      // then saves into SALU's own list and its snackbar says where it went.
      return const RemoteCommandResponse.error(
        RemoteErrorCode.noWebBookmarks,
        "The PC's bookmarks are full.",
      );
    }
    final WebFavourite? added = store.findFor(url);
    return added == null
        ? const RemoteCommandResponse.ok()
        : _bookmarkAck(added);
  }

  RemoteCommandResponse _bookmarkAck(WebFavourite f) =>
      RemoteCommandResponse.ok(<String, Object?>{
        'entry': <String, Object?>{
          'name': _truncate(f.name, 80),
          'url': _truncate(f.url, 180),
          'folder': f.folder.isEmpty ? '' : _truncate(f.folder, 80),
        },
      });

  /// `pc_sleep` and `pc_shutdown` (pc_part.md Part D · remote.md §17.15).
  /// Rejects arguments, duplicate pending requests, and unsupported systems.
  Future<RemoteCommandResponse> _handlePower(
    String action,
    Map<String, Object?> args,
  ) async {
    if (args.isNotEmpty) return _invalid();
    if (!power.available) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.invalidArguments,
        'Power operations are not supported on this PC.',
      );
    }
    if (_powerPending) {
      return const RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'A power command is already pending.',
      );
    }
    _powerPending = true;
    try {
      if (_onPowerAction != null) {
        await _onPowerAction(action);
      } else {
        // Dispatched after a short delay so ack leaves the socket before Windows acts.
        Future<void>.delayed(const Duration(milliseconds: 150), () async {
          if (action == 'sleep') {
            await power.sleep();
          } else {
            await power.shutdown();
          }
        });
      }
      return const RemoteCommandResponse.ok();
    } catch (e) {
      return RemoteCommandResponse.error(
        RemoteErrorCode.busy,
        'Failed to schedule power action: $e',
      );
    } finally {
      // If no external delegation, keep pending flag for a moment to prevent double trigger
      Future<void>.delayed(const Duration(seconds: 5), () {
        _powerPending = false;
      });
    }
  }

  Future<bool> _navigateBrowser(String action) async {
    if (!BrowserService.navActions.contains(action)) return false;
    // BrowserService's callback is installed by BrowserScreen. The bridge
    // lives there to keep the active WebTab private to that widget.
    return BrowserService.instance.remoteNavigate(action);
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0;

  /// The loose URL acceptance `web_tab_new` uses — the same family as
  /// `UrlLibraryService.looksLikeUrl` but permissive about schemes, because
  /// "youtube.com" is a legitimate new-tab target the address bar resolves.
  static bool _looksLikeUrl(String value) {
    final String v = value.trim();
    if (v.isEmpty || v.contains(' ')) return false;
    if (v.contains('://')) return true;
    return v.contains('.') && !v.startsWith('.') && !v.endsWith('.');
  }
  static List<double>? _numbers(Object? raw) => raw is List
      ? raw.whereType<num>().map((num n) => n.toDouble()).toList()
      : null;
}
