import 'package:flutter_test/flutter_test.dart';
import 'package:salu_remote/core/error_copy.dart';
import 'package:salu_remote/core/models.dart';
import 'package:salu_remote/core/reply.dart';
import 'package:salu_remote/protocol/remote_protocol.dart';

/// The phone's half of the contract, testable with `flutter test` and no phone.
///
/// These fixtures are copied from the PC's own builders (`remote_service.dart`
/// `_snapshot()`, `remote_command_handler.dart`'s result maps), so a field
/// rename on the PC fails here first instead of showing up as a blank row on a
/// phone in someone's hand.

Map<String, Object?> _snapshotJson() => <String, Object?>{
      'proto': 1,
      'rev': 42,
      'at': 1758326400123,
      'mode': 'player',
      'window': <String, Object?>{'mode': 'full', 'fullscreen': false},
      'playback': <String, Object?>{
        'state': 'playing',
        'hasMedia': true,
        'title': 'Big Buck Bunny',
        'kind': 'video',
        'position': 73450,
        'duration': 596000,
        'buffering': false,
        'seekable': true,
        'volume': 80,
        'muted': false,
        'shuffle': false,
        'repeat': 'off',
      },
      'queue': <String, Object?>{'kind': 'files', 'count': 12, 'index': 3},
      'control': <String, Object?>{'deviceId': 'a1b2c3', 'name': 'Pixel 7'},
      'devices': <Object?>[
        <String, Object?>{'id': 'a1b2c3', 'name': 'Pixel 7', 'online': true, 'control': true},
      ],
      'web': <String, Object?>{
        'title': 'Dune — YouTube',
        'url': 'https://example.com/watch?v=1',
        'canBack': true,
        'canForward': false,
        'loading': false,
        'tabs': 3,
        'fullscreen': false,
        'hasMedia': false,
      },
      'tracks': <String, Object?>{'audio': 3, 'subs': 5, 'subSelected': true},
      'tune': <String, Object?>{
        'kind': 'video',
        'preset': 'movie',
        'custom': false,
        'autoEq': true,
        'speed': 'x1',
      },
      'subs': <String, Object?>{
        'delay': 0.2,
        'lang': 'en',
        'autoDownload': true,
        'engine': <String, Object?>{'key': true, 'signedIn': false, 'quotaPaused': false},
      },
      'files': <String, Object?>{'enabled': true},
      'library': <String, Object?>{'count': 7},
    };

void main() {
  group('SaluSnapshot', () {
    test('parses the PC\'s full snapshot', () {
      final SaluSnapshot snapshot = SaluSnapshot.from(_snapshotJson());

      expect(snapshot.rev, 42);
      expect(snapshot.mode, SaluMode.player);
      expect(snapshot.playback.state, TransportState.playing);
      expect(snapshot.playback.title, 'Big Buck Bunny');
      expect(snapshot.playback.position, const Duration(milliseconds: 73450));
      expect(snapshot.playback.duration, const Duration(milliseconds: 596000));
      expect(snapshot.playback.seekable, isTrue);
      expect(snapshot.queue.kind, QueueKind.files);
      expect(snapshot.queue.count, 12);
      expect(snapshot.queue.index, 3);
      expect(snapshot.control.name, 'Pixel 7');
      expect(snapshot.devices.single.online, isTrue);
      expect(snapshot.web.tabs, 3);
      expect(snapshot.tracks.subs, 5);
      expect(snapshot.tune.preset, 'movie');
      expect(snapshot.subs.delay, closeTo(0.2, 0.0001));
      expect(snapshot.filesEnabled, isTrue);
      expect(snapshot.libraryCount, 7);
    });

    test('survives the smallest snapshot the PC can send', () {
      // A fresh PC with nothing loaded: `playback.kind` is absent, `control` is
      // null, and the v1.1 blocks are absent entirely.
      final SaluSnapshot snapshot = SaluSnapshot.from(<String, Object?>{
        'rev': 1,
        'at': 1,
        'mode': 'player',
      });

      expect(snapshot.playback.hasMedia, isFalse);
      expect(snapshot.playback.kind, isNull);
      expect(snapshot.playback.volume, 100);
      expect(snapshot.queue.kind, QueueKind.empty);
      expect(snapshot.control.isEmpty, isTrue);
      expect(snapshot.devices, isEmpty);
      expect(snapshot.web.hasMedia, isFalse);
      expect(snapshot.nothingPlaying, isTrue);
    });

    test('ignores fields it has never heard of (forward compatibility)', () {
      final Map<String, Object?> raw = _snapshotJson()
        ..['something_new'] = <String, Object?>{'from': 'v2'}
        ..['playback'] = (<String, Object?>{
          ...(_snapshotJson()['playback']! as Map<String, Object?>),
          'chapters': 12,
        });
      expect(() => SaluSnapshot.from(raw), returnsNormally);
    });

    test('a channel list is never seekable, and is reported as such', () {
      final Map<String, Object?> raw = _snapshotJson();
      raw['playback'] = <String, Object?>{
        ...raw['playback']! as Map<String, Object?>,
        'kind': 'channel',
        'duration': 0,
        'seekable': false,
      };
      raw['queue'] = <String, Object?>{'kind': 'channels', 'count': 40, 'index': 0};
      final SaluSnapshot snapshot = SaluSnapshot.from(raw);
      expect(snapshot.playback.seekable, isFalse);
      expect(snapshot.queue.isChannels, isTrue);
    });
  });

  group('results', () {
    test('queue rows are titles, never paths', () {
      final QueuePage page = QueuePage.from(<String, Object?>{
        'from': 0,
        'count': 2,
        'total': 12,
        'rows': <Object?>[
          <String, Object?>{'index': 3, 'title': 'Episode 3.mkv', 'now': true},
          <String, Object?>{'index': 4, 'title': 'Episode 4.mkv', 'durationMs': null, 'now': false},
        ],
      });
      expect(page.rows.first.title, 'Episode 3.mkv');
      expect(page.rows.first.now, isTrue);
      expect(page.rows.last.durationMs, isNull);
      expect(page.total, 12);
    });

    test('a file page reports paging and truncation honestly', () {
      final FsPage page = FsPage.from(<String, Object?>{
        'path': r'D:\Movies',
        'from': 0,
        'count': 200,
        'total': 480,
        'truncated': true,
        'entries': <Object?>[
          <String, Object?>{
            'name': 'Action',
            'path': r'D:\Movies\Action',
            'directory': true,
          },
          <String, Object?>{
            'name': 'Dune.Part.One.2021.1080p.mkv',
            'path': r'D:\Movies\Dune.Part.One.2021.1080p.mkv',
            'directory': false,
            'size': 2362232012,
            'modified': 1758326400000,
            'ext': 'mkv',
          },
        ],
      });

      expect(page.hasMore, isTrue);
      expect(page.truncated, isTrue);
      expect(page.entries.first.directory, isTrue);
      expect(page.entries.first.isMedia, isFalse, reason: 'folders are not media');
      expect(page.entries.last.isMedia, isTrue);
      expect(page.entries.last.readableSize, '2.2 GB');
    });

    test('the subtitle engine\'s blockers become the phone\'s sentences', () {
      expect(const SubtitleEngine(key: false).blocker,
          'Add an OpenSubtitles key on the PC to search.');
      expect(const SubtitleEngine(signedIn: false).blocker,
          'Sign in to OpenSubtitles on the PC to download subtitles.');
      expect(const SubtitleEngine(signedIn: true, quotaPaused: true).blocker,
          'OpenSubtitles download limit reached. Try again tomorrow.');
      expect(const SubtitleEngine(signedIn: true).blocker, isNull);
    });

    test('tune carries the PC\'s own preset list and stop keys', () {
      final TuneInfo tune = TuneInfo.from(<String, Object?>{
        'kind': 'audio',
        'available': true,
        'eq': <Object?>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'eqStop': 'rock',
        'custom': false,
        'my': null,
        'autoPick': true,
        'autoEq': false,
        'presets': <Object?>[
          <String, Object?>{'key': 'flat', 'label': 'Flat', 'gains': <Object?>[]},
        ],
        'speed': 'x1_25',
        'speedValue': 1.25,
        'speedKeys': <Object?>[
          <String, Object?>{'key': 'x1', 'label': '1×'},
          <String, Object?>{'key': 'x1_25', 'label': '1.25×'},
        ],
      });

      expect(tune.bandCount, 10);
      expect(tune.curve.length, 10);
      expect(tune.presets.single.label, 'Flat');
      expect(tune.speed, 'x1_25');
      expect(tune.speedKeys.last.label, '1.25×');
    });

    test('a track row reads as one honest line', () {
      final TrackInfo track = TrackInfo.from(<String, Object?>{
        'id': '2',
        'title': 'English',
        'lang': 'en',
        'codec': 'ac3',
        'channels': '5.1',
        'external': false,
        'selected': true,
      });
      expect(track.detail, 'en · 5.1 · ac3');
    });

    test('web media positions arrive in seconds and become Durations', () {
      final WebMediaInfo media = WebMediaInfo.from(<String, Object?>{
        'found': true,
        'playing': true,
        'position': 12.5,
        'duration': 240.0,
        'volume': 0.8,
        'muted': false,
        'canFull': true,
      });
      expect(media.found, isTrue);
      expect(media.position, const Duration(milliseconds: 12500));
      expect(media.volume, 80);
      expect(media.canFullscreen, isTrue);
    });
  });

  group('errors', () {
    test('the PC\'s codes map to the spec\'s sentences', () {
      expect(RemoteErrorCopy.text('bad_code', null), 'That pairing code is not valid.');
      expect(RemoteErrorCopy.text('bad_token', null), 'This phone is no longer paired.');
      expect(RemoteErrorCopy.text('file_access_off', null),
          'File browsing is turned off on the PC.');
      expect(RemoteErrorCopy.text('no_web_media', null),
          "This site's player can't be controlled from outside.");
      expect(RemoteErrorCopy.text('quota', null),
          'OpenSubtitles download limit reached. Try again tomorrow.');
    });

    test('noise is marked silent, real failures are not', () {
      expect(RemoteErrorCopy.isSilent('too_fast'), isTrue);
      expect(RemoteErrorCopy.isSilent('unknown_command'), isTrue);
      expect(RemoteErrorCopy.isSilent('nothing_playing'), isFalse);
    });

    test('an unknown code still says something usable', () {
      expect(RemoteErrorCopy.text('brand_new_code', 'The PC said this.'), 'The PC said this.');
      expect(RemoteErrorCopy.text('brand_new_code', null), 'Something went wrong.');
      expect(RemoteErrorCopy.of(RemoteReply.offline()), 'Not connected to your PC.');
    });
  });

  group('the wire protocol (shared with the PC)', () {
    test('auth frames match the server\'s parser exactly', () {
      final Map<String, Object?> auth = RemoteProtocol.authByPairingCode(
        id: 1,
        pair: '7K4MQP2X',
        deviceId: 'phone01',
        deviceName: 'Pixel 7',
        platform: 'android',
      );
      expect(auth['type'], 'auth');
      expect(auth['proto'], protocolVersion);
      expect(auth['pair'], '7K4MQP2X');
      expect(auth['token'], isNull);
      final Map<String, Object?> device = auth['device']! as Map<String, Object?>;
      expect(device['id'], 'phone01');
      expect(device['platform'], 'android');
    });

    test('a command frame round-trips through the PC\'s decoder', () {
      final String encoded = RemoteProtocol.encode(<String, Object?>{
        'type': 'cmd',
        'id': 7,
        'proto': protocolVersion,
        'verb': 'seek_to',
        'args': <String, Object?>{'position': 123456},
      });
      final Map<String, Object?> decoded = RemoteProtocol.decode(encoded);
      final RemoteCommand? command = RemoteCommand.tryParse(decoded);
      expect(command, isNotNull);
      expect(command!.id, 7);
      expect(command.verb, 'seek_to');
      expect(command.args['position'], 123456);
      expect(RemoteProtocol.isVersion(decoded['proto']), isTrue);
    });

    test('a non-command frame is not mistaken for one', () {
      expect(RemoteCommand.tryParse(<String, Object?>{'type': 'auth'}), isNull);
      expect(RemoteCommand.tryParse(<String, Object?>{'type': 'cmd', 'id': 'x', 'verb': 'y'}),
          isNull);
    });

    test('oversized messages are refused before they reach the socket', () {
      final String huge = 'x' * (maxRemoteMessageBytes + 1);
      expect(
        () => RemoteProtocol.encode(<String, Object?>{'type': 'cmd', 'note': huge}),
        throwsA(isA<RemoteProtocolException>()),
      );
    });
  });

  group('the reply envelope', () {
    test('a success and a failure both collapse into one type', () {
      const RemoteReply ok = RemoteReply(ok: true, type: 'queue_result');
      const RemoteReply bad = RemoteReply(
        ok: false,
        type: 'error',
        code: 'nothing_playing',
        message: 'Nothing is playing on the PC.',
      );
      expect(ok.ok, isTrue);
      expect(RemoteErrorCopy.of(bad), 'Nothing is playing on the PC.');
    });
  });
}
