import 'eq_memory.dart';
import 'tune_model.dart';
import 'tune_presets.dart';

/// The Auto EQ guess (eq_imp.md §5) — pure, in this order, first rule that
/// speaks wins:
///
///  1. music file with a genre label            → the matching preset
///  2. video with 5.1 / 7.1 sound               → Movie
///  3. short video + stereo (under ~20 min)     → Music Video
///  4. long video (over ~90 min)                → Movie, or Documentary when
///                                               the name says so
///  5. name words ("concert", "podcast", …)     → adjust the guess
///  6. nothing matches                          → Flat
///
/// SALU never listens to the audio (mpv does not hand out samples without a
/// new native dependency), so every fact here comes from the file's own
/// labels: its tag, its length, its sound layout, its name.
///
/// What the person KEPT outranks every rule above ([choose]) — §5's learning,
/// with §7c's full curves.
class AutoEqFacts {
  const AutoEqFacts({
    required this.kind,
    required this.fileName,
    this.genre,
    this.duration,
    this.channelCount,
  });

  final TuneFileKind kind;

  /// File name without extension (case is kept; matching lowercases).
  final String fileName;

  /// The `genre` tag inside the file, when it has one.
  final String? genre;

  /// `null` while unknown (a stream, a still-loading file).
  final Duration? duration;

  /// mpv's `audio-params/channel-count` (2 = stereo, 6 = 5.1, 8 = 7.1).
  final int? channelCount;

  bool get durationKnown => duration != null && duration! > Duration.zero;

  bool get isSurround => (channelCount ?? 0) >= 6;

  bool get isStereo => (channelCount ?? 0) == 2;

  static const Duration shortVideo = Duration(minutes: 20);
  static const Duration longVideo = Duration(minutes: 90);
}

/// Which rule answered — named so the indicator, the tests and the learning
/// map can all say *why* a preset was picked.
enum AutoEqRule {
  genreTag,
  surroundVideo,
  shortVideoStereo,
  longVideo,
  nameWords,
  learned,
  learnedCurve,
  none,
}

/// The pick: a preset key of the playing file's own set, plus its rule.
class AutoEqPick {
  const AutoEqPick(this.presetKey, this.rule);

  final String presetKey;
  final AutoEqRule rule;

  bool get isFlat => presetKey == 'flat';
}

/// What Auto should apply to a file: a named stop of the file's own set, or —
/// when the person kept a curve of their own for this kind of content (§7c) —
/// those exact 10 gains.
class AutoEqChoice {
  const AutoEqChoice({
    this.presetKey,
    this.gains,
    required this.rule,
  });

  /// A preset key, `null` when the choice is a kept curve. Always a key of
  /// the playing file's own set ([TunePresets.presetByKey] resolves it).
  final String? presetKey;

  /// The kept curve, `null` unless this came from the learning map.
  final List<double>? gains;

  final AutoEqRule rule;

  bool get isCustom => presetKey == null && gains != null;

  bool get isFlat => presetKey == 'flat';
}

/// The learning map's key for a file (eq_imp.md §5: "per file type +
/// genre/series"). Bounded by construction: dozens of genres and a few
/// hundred series, never one entry per file.
class AutoEq {
  AutoEq._();

  /// `video`/`audio` + genre (music) or series (video), or `untagged`.
  static String memoryKey(AutoEqFacts facts) {
    final String kind = facts.kind == TuneFileKind.audio ? 'audio' : 'video';
    if (facts.kind == TuneFileKind.audio) {
      final String? g = normalizeGenre(facts.genre);
      return '$kind|${g ?? 'untagged'}';
    }
    final String? series = seriesOf(facts.fileName);
    return '$kind|${series ?? 'untitled'}';
  }

  /// A genre tag's canonical spelling: lowercased, `;`/`,` split handled by
  /// the caller taking the first tag, non-alphanumerics collapsed to a space.
  ///
  /// Everything that matches a rule goes through here, so a rule word is
  /// written the way this produces it — `k pop`, `hip hop`, `lo fi` (never
  /// `k-pop`: the hyphen is gone by the time the table sees it).
  static String? normalizeGenre(String? raw) {
    if (raw == null) return null;
    String s = raw.trim();
    // Taggers love "Electronic / Dance" and "Rock, Pop" — the first tag wins.
    // Only a real word is allowed to win, so `R&B` never becomes `R`.
    for (final String sep in <String>['/', ',', ';', '&']) {
      final int i = s.indexOf(sep);
      if (i > 2) s = s.substring(0, i);
    }
    s = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.isEmpty ? null : s;
  }

  /// The preset a genre label asks for, in the AUDIO set's keys (eq_imp.md
  /// §1.6: an audio file gets the 13-preset line). `null` = no opinion.
  static String? presetForGenre(String? genre) {
    final String? g = normalizeGenre(genre);
    if (g == null || g.isEmpty) return null;
    for (final MapEntry<String, List<String>> rule in _genreRulesMap.entries) {
      for (final String word in rule.value) {
        if (g == word || g.startsWith('$word ') || g.endsWith(' $word') ||
            g.contains(' $word ')) {
          return rule.key;
        }
      }
    }
    return null;
  }

  /// Rule words are written in [normalizeGenre]'s spelling — the space form.
  /// A hyphenated spelling here could never match: `Lo-Fi` normalises to
  /// `lo fi`, so `lo-fi` would be a dead entry.
  static const Map<String, List<String>> _genreRulesMap = <String, List<String>>{
    'rock': <String>['rock', 'metal', 'punk', 'grunge', 'alternative', 'hardcore'],
    'pop': <String>['pop', 'synthpop', 'indie', 'k pop', 'j pop'],
    'jazz': <String>['jazz', 'blues', 'swing', 'bebop', 'bossa nova', 'big band'],
    'classical': <String>[
      'classical', 'orchestral', 'symphony', 'chamber', 'opera', 'concerto',
      'soundtrack',
    ],
    'bass': <String>[
      'hip hop', 'rap', 'trap', 'r b', 'rnb', 'soul', 'funk', 'gospel',
      'drum and bass', 'drum',
    ],
    'dance': <String>['dance', 'edm', 'house', 'techno', 'trance', 'electro', 'dubstep', 'disco'],
    'vocal': <String>['vocal', 'a cappella', 'acappella', 'choir', 'karaoke'],
    'lounge': <String>[
      'lounge', 'ambient', 'new age', 'easy listening', 'lo fi', 'lofi',
      'chillout',
    ],
    'live': <String>['live', 'concert'],
    'folk': <String>['folk', 'country', 'bluegrass', 'reggae', 'ska'],
  };

  /// Genre → preset for the AUDIO set only — every key the table answers
  /// must exist as a stop on that file type's line, so `folk` (which has no
  /// band of its own) lands on Lounge: soft and mid-forward, the nearest
  /// thing the 13-stop line offers.
  static String? presetForGenreInAudioSet(String? genre) {
    final String? key = presetForGenre(genre);
    if (key == null) return null;
    return key == 'folk' ? 'lounge' : key;
  }

  /// Name words that override a guess (spec rule 5).
  static String? presetForName(
    String fileName,
    TuneFileKind kind, {
    bool longVideo = false,
  }) {
    bool has(List<String> words) => words.any((String w) => hasWord(fileName, w));
    if (kind == TuneFileKind.video) {
      if (has(<String>['documentary', 'interview', 'lecture', 'talk', 'seminar'])) {
        return 'documentary';
      }
      if (has(<String>['concert', 'live at', 'live in', 'tour', 'festival', 'unplugged'])) {
        return 'musicvideo';
      }
      if (has(<String>['podcast', 'episode']) || hasEpisodeMarker(fileName)) {
        // A spoken-word episode is a dialogue track, not a cinema mix — but
        // only when it is not a long film (rule 4 owns those).
        if (!longVideo) return 'documentary';
      }
      return null;
    }
    if (has(<String>['concert', 'live', 'unplugged', 'tour'])) return 'live';
    if (has(<String>['podcast', 'interview', 'talk', 'audiobook'])) return 'vocal';
    if (has(<String>['karaoke', 'a cappella', 'acappella'])) return 'vocal';
    if (has(<String>['vinyl', 'record', 'tape'])) return 'lounge';
    return null;
  }

  /// Whether [word] appears in [haystack] as a WORD — not buried inside a
  /// longer one. `Field Recording 12` must not read as a record player, and
  /// a `tapestry` must not read as a tape. Both are lowercased already, so a
  /// word character is a letter or a digit.
  static bool hasWord(String haystack, String word) {
    if (word.isEmpty) return false;
    int from = 0;
    while (from <= haystack.length - word.length) {
      final int i = haystack.indexOf(word, from);
      if (i < 0) return false;
      final int end = i + word.length;
      final bool leftOk = i == 0 || !_isWordChar(haystack.codeUnitAt(i - 1));
      final bool rightOk =
          end >= haystack.length || !_isWordChar(haystack.codeUnitAt(end));
      if (leftOk && rightOk) return true;
      from = i + 1;
    }
    return false;
  }

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);

  /// The season/episode markers that make a name *an episode*: `S01E02`,
  /// `1x02`, `Ep 12`. `Part 3` is deliberately not one of them — it is as
  /// often a film as an episode, and `seriesOf` (which only needs a stable
  /// map key) is free to be more generous.
  static final RegExp _episodeMarker = RegExp(
    r'(\bs\d{1,2}[\s._-]?e\d{1,3}\b)|(\b\d{1,2}x\d{1,3}\b)|(\b(?:ep|episode)\D{0,3}\d{1,4}\b)',
    caseSensitive: false,
  );

  static bool hasEpisodeMarker(String fileName) =>
      _episodeMarker.hasMatch(fileName);

  /// A series handle from a file name: the leading words before an episode
  /// marker (`S01E02`, `1x02`, `Ep 12`, `Part 3`).
  ///
  /// `null` when the name carries no such marker — a one-off film then shares
  /// the `untitled` key with every other one-off, which is what keeps the
  /// map's key space small (§5: it grows with *kinds* of content, never with
  /// files).
  static String? seriesOf(String fileName) {
    String s = fileName;
    // Cut at the first episode marker — the only thing that proves this name
    // belongs to a series.
    final RegExp cut = RegExp(
        r'[\[\(._ \-]((s\d{1,2}[\s._-]?e\d{1,3})|(\d{1,2}x\d{1,3})|(ep|episode|part|ch)\D{0,3}\d{1,4})',
        caseSensitive: false);
    final Match? m = cut.firstMatch(s);
    if (m == null) return null;
    s = s.substring(0, m.start);
    // A year or a quality token glued to the name belongs to the release,
    // not the show: `The News 2019 1080p S01E02`.
    final RegExp tail = RegExp(
        r'[\[\(](\d{4})[\]\)]|[\s._-](1080p|720p|2160p|4k|x264|x265|hevc|avc)',
        caseSensitive: false);
    final Match? m2 = tail.firstMatch(s);
    if (m2 != null) s = s.substring(0, m2.start);

    // Keep letters/digits only, and the first three words — enough to
    // identify a show, short enough that a stray suffix never forks the key.
    s = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) return null;
    final List<String> words = s.split(' ');
    final List<String> head = words.take(3).toList(growable: false);
    final String key = head.join(' ');
    return key.length < 3 ? null : key;
  }

  /// The guess for a file, following §5's order. Always answers — the
  /// fallback is [AutoEqPick] with `flat`.
  static AutoEqPick pick(AutoEqFacts facts) {
    if (facts.kind == TuneFileKind.audio) {
      final String? byGenre = presetForGenreInAudioSet(facts.genre);
      if (byGenre != null) return AutoEqPick(byGenre, AutoEqRule.genreTag);
      final String? byName = presetForName(facts.fileName, facts.kind);
      if (byName != null) return AutoEqPick(byName, AutoEqRule.nameWords);
      return const AutoEqPick('flat', AutoEqRule.none);
    }
    // Video: the 4-stop line (Flat · Movie · Music Video · Documentary).
    final bool longVideo =
        facts.durationKnown && facts.duration! > AutoEqFacts.longVideo;
    final String? byName =
        presetForName(facts.fileName, facts.kind, longVideo: longVideo);
    if (byName == 'documentary') {
      return const AutoEqPick('documentary', AutoEqRule.nameWords);
    }
    if (facts.isSurround) {
      return const AutoEqPick('movie', AutoEqRule.surroundVideo);
    }
    if (byName != null) return AutoEqPick(byName, AutoEqRule.nameWords);
    if (facts.durationKnown &&
        facts.duration! < AutoEqFacts.shortVideo &&
        (facts.channelCount == null || facts.isStereo)) {
      return const AutoEqPick('musicvideo', AutoEqRule.shortVideoStereo);
    }
    if (longVideo) return const AutoEqPick('movie', AutoEqRule.longVideo);
    return const AutoEqPick('flat', AutoEqRule.none);
  }

  /// What Auto applies to [facts], the memory first: the thing this person
  /// kept for this kind of content — their own curve (§7c) or a named stop —
  /// then §5's six rules. Read-only (the caller touches the entry it used).
  static AutoEqChoice choose(AutoEqFacts facts, EqMemory memory) {
    final EqMemoryEntry? kept = memory.entryFor(memoryKey(facts));
    if (kept != null) {
      final String key = kept.presetKey;
      if (key.isNotEmpty &&
          TunePresets.presetByKey(key, facts.kind) != null) {
        return AutoEqChoice(presetKey: key, rule: AutoEqRule.learned);
      }
      if (kept.hasCurve) {
        return AutoEqChoice(gains: kept.gains, rule: AutoEqRule.learnedCurve);
      }
    }
    final AutoEqPick guess = pick(facts);
    return AutoEqChoice(presetKey: guess.presetKey, rule: guess.rule);
  }

  /// A short, honest tooltip line for the indicator dot: "Auto EQ · Rock".
  static String describe(String choiceLabel) => 'Auto EQ · $choiceLabel';
}
