import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/auto_eq.dart';
import 'package:salu/core/tune/eq_memory.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';

/// Auto EQ's guess (eq_imp.md §5) — six rules in a fixed order, run from the
/// file's own labels because SALU cannot listen to the audio. What is checked
/// here is the *order* and the honesty of the fallback: a wrong guess is
/// forgiven by one tap, but a guess that throws, or one that fires on a file
/// with no facts, is not.
///
/// The learning map's side of §5 (only a kept choice teaches, the key space
/// stays small) is [EqMemory]'s own test plus the service test.
void main() {
  group('normalizeGenre — one tag, canonically spelled', () {
    test('the first tag wins, in the taggers\' many styles', () {
      expect(AutoEq.normalizeGenre('Rock, Pop'), 'rock');
      expect(AutoEq.normalizeGenre('Electronic / Dance'), 'electronic');
      expect(AutoEq.normalizeGenre('Jazz; Blues'), 'jazz');
      expect(AutoEq.normalizeGenre('Folk & Country'), 'folk');
    });

    test('punctuation collapses to spaces, case goes away', () {
      expect(AutoEq.normalizeGenre('  HEAVY  METAL  '), 'heavy metal');
      // The hyphen is GONE by the time a rule sees the tag — which is why
      // every rule word is written in this spelling (`hip hop`, `lo fi`).
      expect(AutoEq.normalizeGenre('Hip-Hop'), 'hip hop');
      expect(AutoEq.normalizeGenre('K-Pop'), 'k pop');
      expect(AutoEq.normalizeGenre('Lo-Fi'), 'lo fi');
      expect(AutoEq.normalizeGenre('R&B'), 'r b');
      expect(AutoEq.normalizeGenre('   '), isNull);
      expect(AutoEq.normalizeGenre(null), isNull);
      expect(AutoEq.normalizeGenre('!!!'), isNull);
    });
  });

  group('genre → preset', () {
    test('the direct ones', () {
      expect(AutoEq.presetForGenre('Jazz'), 'jazz');
      expect(AutoEq.presetForGenre('rock'), 'rock');
      expect(AutoEq.presetForGenre('Heavy Metal'), 'rock');
      expect(AutoEq.presetForGenre('90s Hip Hop'), 'bass');
      expect(AutoEq.presetForGenre('R&B'), 'bass');
      expect(AutoEq.presetForGenre('Synthpop'), 'pop');
      expect(AutoEq.presetForGenre('Bossa Nova'), 'jazz');
      expect(AutoEq.presetForGenre('lo-fi'), 'lounge');
      expect(AutoEq.presetForGenre('choir'), 'vocal');
    });

    test('a hyphenated tag still lands — the rules are spelled the '
        'normalised way', () {
      expect(AutoEq.presetForGenre('Hip-Hop'), 'bass');
      expect(AutoEq.presetForGenre('K-Pop'), 'pop');
      expect(AutoEq.presetForGenre('Drum & Bass'), 'bass');
      expect(AutoEq.presetForGenre('A Cappella'), 'vocal');
    });

    test('an unknown genre has no opinion at all', () {
      expect(AutoEq.presetForGenre('Polka'), isNull);
      expect(AutoEq.presetForGenre(null), isNull);
      // A word inside a longer name is not the genre (`"Rocky"` is a film).
      expect(AutoEq.presetForGenre('rocky'), isNull);
    });

    test('the audio line has no Folk stop, so Folk asks for Lounge', () {
      expect(AutoEq.presetForGenre('folk'), 'folk');
      expect(AutoEq.presetForGenreInAudioSet('folk'), 'lounge');
      expect(AutoEq.presetForGenreInAudioSet('country'), 'lounge');
      expect(AutoEq.presetForGenreInAudioSet('jazz'), 'jazz');
      expect(AutoEq.presetForGenreInAudioSet('Polka'), isNull);
    });
  });

  group('a name word is a word, never a fragment (§5 rule 5)', () {
    test('`recording` is not a record player, and a `tapestry` is not a tape',
        () {
      expect(AutoEq.hasWord('vinyl rips', 'vinyl'), isTrue);
      expect(AutoEq.hasWord('vinyl rips', 'record'), isFalse);
      expect(AutoEq.hasWord('field recording 12', 'record'), isFalse);
      expect(AutoEq.hasWord('the tapestry', 'tape'), isFalse);
      expect(AutoEq.hasWord('tape 3', 'tape'), isTrue);
      // Digits are word characters too, so a marker like `s01e02` is not an
      // `s0`.
      expect(AutoEq.hasWord('show s01e02', 's0'), isFalse);
    });

    test('the whole name-word path agrees', () {
      // A field recording is not a record: nothing matches, so Auto stays
      // honestly silent instead of guessing Lounge.
      expect(
        AutoEq.pick(const AutoEqFacts(
          kind: TuneFileKind.audio,
          fileName: 'Field Recording 12',
        )).presetKey,
        'flat',
      );
      expect(AutoEq.presetForName('Vinyl Rips', TuneFileKind.audio), 'lounge');
      expect(AutoEq.presetForName('Tape 5', TuneFileKind.audio), 'lounge');
    });

    test('an episode marker makes a video an episode', () {
      expect(AutoEq.hasEpisodeMarker('The News S01E02'), isTrue);
      expect(AutoEq.hasEpisodeMarker('Great Cities - 3x07 - Rome'), isTrue);
      expect(AutoEq.hasEpisodeMarker('Show Ep 12'), isTrue);
      // `Part 3` is deliberately not an episode marker: it is as often a
      // film, and rule 4 (length) owns long films.
      expect(AutoEq.hasEpisodeMarker('The Godfather Part 2'), isFalse);
      expect(AutoEq.hasEpisodeMarker('Blade Runner 1982 2160p'), isFalse);
      expect(
        AutoEq.presetForName('The News S01E02', TuneFileKind.video),
        'documentary',
      );
      // …but a long film's own length still wins (rule 4).
      expect(
        AutoEq.presetForName('The News S01E02', TuneFileKind.video,
            longVideo: true),
        isNull,
      );
    });
  });

  group('name words', () {
    test('on a video', () {
      expect(AutoEq.presetForName('Lecture on Rome', TuneFileKind.video),
          'documentary');
      expect(AutoEq.presetForName('Tool CONCERT 2019', TuneFileKind.video),
          'musicvideo');
      expect(AutoEq.presetForName('The Podcast Ep 4', TuneFileKind.video),
          'documentary');
      // A long film's own words do not outvote its length (rule 4).
      expect(
        AutoEq.presetForName('Some Episode', TuneFileKind.video,
            longVideo: true),
        isNull,
      );
      expect(AutoEq.presetForName('Holidays', TuneFileKind.video), isNull);
    });

    test('on music', () {
      expect(
          AutoEq.presetForName('Artist — Live at Wembley', TuneFileKind.audio),
          'live');
      expect(AutoEq.presetForName('Interview 2024', TuneFileKind.audio),
          'vocal');
      expect(AutoEq.presetForName('Vinyl Rips', TuneFileKind.audio), 'lounge');
      expect(AutoEq.presetForName('Album', TuneFileKind.audio), isNull);
    });
  });

  group('seriesOf — the key that keeps the map small', () {
    test('the words before an episode marker', () {
      expect(AutoEq.seriesOf('Show.S01E02.1080p.mkv'), 'show');
      expect(AutoEq.seriesOf('The News S02E11.mp4'), 'the news');
      expect(AutoEq.seriesOf('Great Cities - 3x07 - Rome.mp4'),
          'great cities');
      expect(AutoEq.seriesOf('Lecture Part 12.mkv'), 'lecture');
    });

    test('a one-off file is not a series', () {
      expect(AutoEq.seriesOf('Blade Runner 1982 2160p.mkv'), isNull);
      expect(AutoEq.seriesOf('holiday clip.mp4'), isNull);
    });

    test('a head longer than three words is cut, so keys cannot fork', () {
      expect(
        AutoEq.seriesOf('The Very Best Of Our Town S01E01.mkv'),
        'the very best',
      );
    });
  });

  group('memoryKey — file type + genre/series, nothing else', () {
    test('music keys on the genre, video on the series', () {
      expect(
        AutoEq.memoryKey(const AutoEqFacts(
          kind: TuneFileKind.audio,
          fileName: 'Anything',
          genre: 'Jazz',
        )),
        'audio|jazz',
      );
      expect(
        AutoEq.memoryKey(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'The News S03E04',
        )),
        'video|the news',
      );
      expect(
        AutoEq.memoryKey(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'One off film',
        )),
        'video|untitled',
      );
      expect(
        AutoEq.memoryKey(const AutoEqFacts(
          kind: TuneFileKind.audio,
          fileName: 'No tag here',
        )),
        'audio|untagged',
      );
      // The same kind + tag is the same key, whatever the file.
      final AutoEqFacts a = const AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'A.mp3',
        genre: 'Pop',
      );
      final AutoEqFacts b = const AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'B.flac',
        genre: 'pop',
      );
      expect(AutoEq.memoryKey(a), AutoEq.memoryKey(b));
    });
  });

  group('choose — the memory outranks the rules (§5 · §7c)', () {
    const AutoEqFacts jazzFile = AutoEqFacts(
      kind: TuneFileKind.audio,
      fileName: 'Kind of Blue',
      genre: 'Jazz',
    );
    const List<double> ownCurve =
        <double>[7, 5, 3, 1, 0, 1, 2, 4, 5, 3];

    test('nothing remembered: the rules answer, with their own rule', () {
      final AutoEqChoice c = AutoEq.choose(jazzFile, EqMemory.empty());
      expect(c.presetKey, 'jazz');
      expect(c.rule, AutoEqRule.genreTag);
      expect(c.isCustom, isFalse);
      expect(c.gains, isNull);
    });

    test('a remembered name beats the file\'s own tag', () {
      final EqMemory m = EqMemory.empty()..teach('audio|jazz', 'rock');
      final AutoEqChoice c = AutoEq.choose(jazzFile, m);
      expect(c.presetKey, 'rock');
      expect(c.rule, AutoEqRule.learned);
    });

    test('a remembered curve comes back as itself (§7c)', () {
      final EqMemory m = EqMemory.empty()..teach('audio|jazz', '', gains: ownCurve);
      final AutoEqChoice c = AutoEq.choose(jazzFile, m);
      expect(c.isCustom, isTrue);
      expect(c.gains, ownCurve);
      expect(c.rule, AutoEqRule.learnedCurve);
    });

    test('a remembered name this line does not have falls back to the rules',
        () {
      // A video line has no `rock`: a stale entry must not silence Auto.
      final EqMemory m = EqMemory.empty()..teach('video|the news', 'rock');
      const AutoEqFacts episode = AutoEqFacts(
        kind: TuneFileKind.video,
        fileName: 'The News S01E02',
        channelCount: 6,
      );
      final AutoEqChoice c = AutoEq.choose(episode, m);
      expect(c.presetKey, 'documentary');
      expect(c.rule, AutoEqRule.nameWords);
    });

    test('the key is file type + genre/series, never the file', () {
      const AutoEqFacts other = AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'Some Other Album',
        genre: 'jazz',
      );
      final EqMemory m = EqMemory.empty()..teach('audio|jazz', 'lounge');
      expect(AutoEq.memoryKey(other), 'audio|jazz');
      expect(AutoEq.choose(other, m).presetKey, 'lounge');
    });
  });

  group('pick — §5\'s six rules, in order', () {
    test('1. a music file with a genre tag answers on the spot', () {
      const AutoEqFacts facts = AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'Kind of Blue',
        genre: 'Jazz',
        channelCount: 2,
      );
      const AutoEqFacts other = AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'Live at Wembley',
        genre: 'Rock',
      );
      expect(AutoEq.pick(facts).presetKey, 'jazz');
      expect(AutoEq.pick(facts).rule, AutoEqRule.genreTag);
      // A tag outranks the name, even when the name is louder.
      expect(AutoEq.pick(other).presetKey, 'rock');
    });

    test('2. a surround video is a movie', () {
      const AutoEqFacts facts = AutoEqFacts(
        kind: TuneFileKind.video,
        fileName: 'Big Action Film',
        duration: Duration(minutes: 40),
        channelCount: 6,
      );
      expect(AutoEq.pick(facts).presetKey, 'movie');
      expect(AutoEq.pick(facts).rule, AutoEqRule.surroundVideo);
      // 7.1 counts the same way, and stereo does not.
      expect(
        AutoEq.pick(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'Big Action Film',
          channelCount: 8,
        )).presetKey,
        'movie',
      );
      expect(
        AutoEq.pick(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'Big Action Film',
          channelCount: 2,
          duration: Duration(minutes: 40),
        )).rule !=
            AutoEqRule.surroundVideo,
        isTrue,
      );
    });

    test('3. a short stereo clip is a music video', () {
      const AutoEqFacts facts = AutoEqFacts(
        kind: TuneFileKind.video,
        fileName: 'Clip',
        duration: Duration(minutes: 4),
        channelCount: 2,
      );
      expect(AutoEq.pick(facts).presetKey, 'musicvideo');
      expect(AutoEq.pick(facts).rule, AutoEqRule.shortVideoStereo);
      // An unknown channel layout still counts as "not surround" here.
      expect(
        AutoEq.pick(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'Clip',
          duration: Duration(minutes: 4),
        )).presetKey,
        'musicvideo',
      );
    });

    test('4. a long video is a movie, unless its name says otherwise', () {
      const AutoEqFacts long = AutoEqFacts(
        kind: TuneFileKind.video,
        fileName: 'Some Film',
        duration: Duration(minutes: 132),
        channelCount: 2,
      );
      expect(AutoEq.pick(long).presetKey, 'movie');
      expect(AutoEq.pick(long).rule, AutoEqRule.longVideo);
      const AutoEqFacts named = AutoEqFacts(
        kind: TuneFileKind.video,
        fileName: 'Documentary — The Reef',
        duration: Duration(minutes: 132),
        channelCount: 2,
      );
      expect(AutoEq.pick(named).presetKey, 'documentary');
      expect(AutoEq.pick(named).rule, AutoEqRule.nameWords);
    });

    test('5. the name adjusts the guess when nothing else answered', () {
      const AutoEqFacts facts = AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'Orchestra — Concert Recording',
      );
      // `concert` is not a genre here, so the name answers with `live`.
      expect(AutoEq.pick(facts).presetKey, 'live');
      expect(AutoEq.pick(facts).rule, AutoEqRule.nameWords);
    });

    test('6. nothing matches — Flat, and the rule says so', () {
      const AutoEqFacts facts = AutoEqFacts(
        kind: TuneFileKind.audio,
        fileName: 'Field Recording 12',
      );
      final AutoEqPick pick = AutoEq.pick(facts);
      expect(pick.presetKey, 'flat');
      expect(pick.rule, AutoEqRule.none);
      expect(pick.isFlat, isTrue);
      // An unknown duration on a video is the same honest silence.
      expect(
        AutoEq.pick(const AutoEqFacts(
          kind: TuneFileKind.video,
          fileName: 'Mystery',
        )).presetKey,
        'flat',
      );
    });

    test('every pick names a stop that exists on that kind of line', () {
      for (final TuneFileKind kind in TuneFileKind.values) {
        for (final String name in <String>[
          'The News S01E02',
          'Live at Wembley',
          'Documentary — The Reef',
          'Big Film',
          'Clip',
          'No tag',
        ]) {
          for (final int? ch in <int?>[null, 2, 6]) {
            for (final Duration? d in <Duration?>[
              null,
              const Duration(minutes: 5),
              const Duration(minutes: 140),
            ]) {
              final AutoEqPick pick = AutoEq.pick(AutoEqFacts(
                kind: kind,
                fileName: name,
                genre: 'Jazz',
                channelCount: ch,
                duration: d,
              ));
              // The guard the service leans on: a pick that is not on the
              // line would park the knob on nothing.
              expect(
                TunePresets.presetByKey(pick.presetKey, kind),
                isNotNull,
                reason: '$kind/$name/$ch/$d',
              );
            }
          }
        }
      }
    });
  });

  test('the indicator line is one short sentence', () {
    expect(AutoEq.describe('Rock'), 'Auto EQ · Rock');
  });
}
