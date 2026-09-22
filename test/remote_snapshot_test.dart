import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/player_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/remote/remote_service.dart';
import 'package:salu/ui/osd/osd_controller.dart';

/// The snapshot's **resume offer** (remote.md §17.5) — the PC's Resume toast
/// mirrored for the phone's Play tab.
///
/// The contract these tests pin down: the offer exists exactly while the PC's
/// toast is on screen, carries the resumed-at clock the toast shows, and is
/// `null` at every other moment — the toast's own 4 s TTL, Esc, a
/// click-outside and any transport action all close it, and the phone's seat
/// must follow within one snapshot. Presence is the offer; there is no second
/// flag that could disagree with the card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlayerService.installNotifierOnlyForTesting();

  group('remoteResumeOffer — presence is the offer', () {
    test('the Resume toast becomes the offer, in ms', () {
      expect(
        remoteResumeOffer(
            const OsdResumeCard(position: Duration(minutes: 12, seconds: 34))),
        <String, Object?>{'position': 754000},
      );
    });

    test('a zero-position offer is still an offer, not an empty one', () {
      // The mapping is presence-based, never a truthiness test on the clock:
      // `position: 0` must not read as "no toast" to anything downstream.
      expect(remoteResumeOffer(const OsdResumeCard(position: Duration.zero)),
          <String, Object?>{'position': 0});
    });

    test('any other card on the slot means no offer', () {
      // The deck is ONE slot: a volume card, a transport flash or an undo
      // toast taking it over closes the resume toast — so the seat goes too.
      expect(remoteResumeOffer(null), isNull);
      expect(remoteResumeOffer(const OsdVolumeCard(muted: true)), isNull);
      expect(
        remoteResumeOffer(const OsdTransportCard(mark: OsdMark.play)),
        isNull,
      );
      expect(
        remoteResumeOffer(OsdUndoCard(label: 'Playlist cleared', onUndo: () {})),
        isNull,
      );
    });
  });

  group('RemoteSnapshot — the block survives the shape rules', () {
    test('a playback map carries its resume offer through', () {
      final RemoteSnapshot snapshot = RemoteSnapshot.fromValues(
        <String, Object?>{
          'playback': <String, Object?>{
            'state': 'playing',
            'hasMedia': true,
            'resume': <String, Object?>{'position': 754000},
          },
        },
      );
      final Map<String, Object?> playback =
          snapshot.toJson()['playback']! as Map<String, Object?>;
      expect(playback['resume'], <String, Object?>{'position': 754000});
    });

    test('the default playback block declares the offer as null', () {
      // A snapshot built with no playback values is still the same shape, so
      // the phone's parser never has to guess whether the key exists.
      final Map<String, Object?> playback =
          RemoteSnapshot.fromValues(const <String, Object?>{}).toJson()
              ['playback']! as Map<String, Object?>;
      expect(playback.containsKey('resume'), isTrue);
      expect(playback['resume'], isNull);
    });

    test('the offer travels on the wire, encoded like every other block', () {
      final String wire = RemoteSnapshot.fromValues(<String, Object?>{
        'playback': <String, Object?>{
          'hasMedia': true,
          'resume': <String, Object?>{'position': 754000},
        },
      }).encode();
      expect(wire.contains('"resume":{"position":754000}'), isTrue);
    });
  });

  group('restart — the phone\'s Start over seat', () {
    final RemoteCommandHandler handler = RemoteCommandHandler();

    setUp(() {
      PlayerService.instance.hasMedia.value = false;
      OsdController.instance.dismiss();
    });

    test('nothing loaded → nothing_playing, exactly like the transport verbs',
        () async {
      final RemoteCommandResponse reply = await handler.handle(
        const RemoteCommand(id: 3, verb: 'restart'),
      );

      expect(reply.ok, isFalse);
      expect(reply.code, RemoteErrorCode.nothingPlaying);
    });

    test('an unknown verb is still unknown — the case list is exhaustive',
        () async {
      final RemoteCommandResponse reply = await handler.handle(
        const RemoteCommand(id: 4, verb: 'start_over'),
      );

      expect(reply.code, RemoteErrorCode.unknownCommand);
    });
  });
}
