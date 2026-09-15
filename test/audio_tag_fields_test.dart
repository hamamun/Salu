import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/audio_tag_fields.dart';

/// Mode C's field contract (lrc.md L29–L35): the tag map mpv reports is kept
/// whole, and what the canvas renders is the standard set — decided by rule,
/// never by whatever a ripper happened to write into a frame.
///
/// The first case is a real SALU report: an MP3 whose tags included a
/// `Comment`, an `Encoder`, an unsynced lyrics blob and two binary
/// `Id3v2 PRIV` replaygain frames — all of which used to be printed as
/// centered rows under the art, long enough to push the artwork up the
/// screen.
void main() {
  group('the four rows (L29, L32)', () {
    test('standard fields in, junk out', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{
          'title': 'Faith',
          'artist': 'Aaradhna',
          'album': 'Third Person Singular Number',
          'genre': 'Dance',
          'album_artist': '3rd Person Bangla Singer',
          'comment': 'H A MAMUN',
          'lyrics-xxx': 'I can feel it\nI can feel myself moving',
          'Id3v2 PRIV:peak value': 'lw\x00\x00',
          'Id3v2 PRIV:average level': '{\x12\x00\x00',
          'encoder': 'LAME3.98',
        },
        fallbackTitle: 'faith',
      );

      expect(info.minimal, isFalse);
      expect(info.title, 'Faith');
      expect(info.artist, 'Aaradhna');
      expect(info.album, 'Third Person Singular Number');
      // Genre · Year · Track — the one context line, and it stays short.
      expect(info.contextParts, <String>['Dance']);
      // Everything else is collected, not shown (info.md's reserve).
      expect(info.rawTags, hasLength(10));
      expect(info.rawTags['encoder'], 'LAME3.98');
    });

    test('a file name never counts as metadata (L33)', () {
      // Mode C lands here while the tags are still unread, and for a file
      // that genuinely has none: the logo + the name, nothing else.
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{},
        fallbackTitle: 'track 07',
      );
      expect(info.minimal, isTrue);
      expect(info.title, 'track 07');
      expect(info.artist, isNull);
      expect(info.album, isNull);
      expect(info.contextParts, isEmpty);
    });

    test('a file whose only tags are junk is still the minimal state', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{
          'comment': 'Ripped by someone',
          'encoder': 'LAME3.98',
          'Id3v2 PRIV:peak value': 'lw\x00\x00',
        },
        fallbackTitle: 'unknown',
      );
      expect(info.minimal, isTrue);
      expect(info.title, 'unknown');
      expect(info.rawTags, hasLength(3));
    });
  });

  group('one field, every spelling', () {
    test('the canonical name wins over a legacy alias', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'title': 'Real', 'inam': 'Legacy'},
          fallbackTitle: 'f',
        ).title,
        'Real',
      );
    });

    test('case does not matter: ID3v2 lowercases, Vorbis uppercases', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{
          'TITLE': 'A Million Tiny Things',
          'ARTIST': 'The Wails',
          'ALBUM': 'Field Recordings',
          'GENRE': 'Indie',
          'DATE': '2019',
          'TRACKNUMBER': '4',
        },
        fallbackTitle: 'f',
      );
      expect(info.title, 'A Million Tiny Things');
      expect(info.artist, 'The Wails');
      expect(info.album, 'Field Recordings');
      expect(info.contextParts, <String>['Indie', '2019', '4']);
    });

    test('one field alone is enough to leave the minimal state', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{'album': 'Only an album'},
        fallbackTitle: 'file one',
      );
      expect(info.album, 'Only an album');
      expect(info.minimal, isFalse);
      expect(info.title, 'file one');
    });
  });

  group('one line per row, whatever the tag holds (L31)', () {
    test('a multi-line value collapses to its first line', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'title': 'Faith\nSecond verse here'},
          fallbackTitle: 'f',
        ).title,
        'Faith',
      );
    });

    test('binary payloads are dropped, not drawn as boxes', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{
          'title': 'lw\x00\x00',
          'artist': 'Fine',
        },
        fallbackTitle: 'f',
      );
      expect(info.title, 'f');
      expect(info.artist, 'Fine');
    });

    test('a value repeating a row above it is not shown twice', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{
          'title': 'Faith',
          'album': 'Faith',
          'artist': 'Aaradhna',
          'date': '2013',
        },
        fallbackTitle: 'f',
      );
      expect(info.album, isNull);
      expect(info.artist, 'Aaradhna');
      expect(info.contextParts, <String>['2013']);
    });
  });

  group('the context line, normalized (L32)', () {
    test('an ID3v2 parenthesised genre index keeps its name', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'genre': '(17)Dance', 'title': 't'},
          fallbackTitle: 'f',
        ).contextParts,
        <String>['Dance'],
      );
    });

    test('a bare genre index is dropped rather than shown as a number', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{'genre': '17', 'title': 't'},
        fallbackTitle: 'f',
      );
      expect(info.genre, isNull);
      // Still collected — the 0–191 name table is a later call (info.md).
      expect(info.rawTags['genre'], '17');
    });

    test('a multi-value genre shows its first value', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'genre': 'Dance; Pop; DancePop', 'title': 't'},
          fallbackTitle: 'f',
        ).genre,
        'Dance',
      );
    });

    test('a full ISO date reads as a year on the canvas', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'date': '2013-05-17', 'title': 't'},
          fallbackTitle: 'f',
        ).year,
        '2013',
      );
    });

    test('digits glued to a longer number are not a year', () {
      expect(
        buildAudioTrackInfo(
          <String, String>{'date': 'CATALOGUE 20135', 'title': 't'},
          fallbackTitle: 'f',
        ).year,
        isNull,
      );
    });

    test('every track-number spelling, and a zero total is no total', () {
      AudioTrackInfo withTrack(String track, {String? total}) {
        return buildAudioTrackInfo(
          <String, String>{
            'title': 't',
            'track': track,
            if (total != null) 'totaltracks': total,
          },
          fallbackTitle: 'f',
        );
      }

      expect(withTrack('3/12').track, '3/12');
      expect(withTrack('3 of 12').track, '3/12');
      expect(withTrack('3/0').track, '3');
      expect(withTrack('3').track, '3');
      expect(withTrack('3/0', total: '12').track, '3/12');
      expect(withTrack('3', total: '12').track, '3/12');
      expect(withTrack('not a number').track, isNull);
    });

    test('order is genre, year, track — and only what exists', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{'title': 't', 'track': '9/14', 'date': '2013'},
        fallbackTitle: 'f',
      );
      expect(info.contextParts, <String>['2013', '9/14']);
    });
  });

  group('the parked set stays whole (L29, L34)', () {
    test('every tag survives, including the ones the canvas rejects', () {
      final Map<String, String> raw = <String, String>{
        'title': 'Faith',
        'lyrics-xxx': 'I can feel it',
        'Id3v2 PRIV:peak value': 'lw\x00\x00',
        'comment': 'H A MAMUN',
      };
      final AudioTrackInfo info =
          buildAudioTrackInfo(raw, fallbackTitle: 'f');
      expect(info.rawTags.keys, raw.keys);
      expect(info.rawTags['lyrics-xxx'], 'I can feel it');
      expect(info.rawTags['comment'], 'H A MAMUN');
    });

    test('the parked map cannot be edited by a widget', () {
      final AudioTrackInfo info = buildAudioTrackInfo(
        <String, String>{'title': 't'},
        fallbackTitle: 'f',
      );
      expect(
        () => info.rawTags['sneaky'] = 'value',
        throwsUnsupportedError,
      );
    });
  });
}
