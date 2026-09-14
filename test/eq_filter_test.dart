import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/eq_filter.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';

/// The `--af` string SALU hands mpv (eq_imp.md §6's named unit test: "the
/// filter-string builder"). This is the one place where a typo becomes a
/// silent audio failure, so the shape is pinned here rather than discovered
/// by ear:
///
///   · `Flat` builds NOTHING — the filter leaves the chain entirely (§2);
///   · bands with no gain are skipped, so the string stays short;
///   · numbers are bare (`g=6`, `g=-2.5`) — FFmpeg parses no `+`, and a
///     trailing `.0` is noise;
///   · ONLY the single-band `equalizer` is used — it is the one equalizer
///     compiled into media_kit's libmpv (`anequalizer`, `superequalizer` and
///     `firequalizer` are not, and asking for them kills the audio track);
///   · the graph is preceded by `format=floatp`, because that libmpv has no
///     `aresample` for libavfilter to convert packed FLAC/WAV/Opus samples
///     with — mpv's own converter has to do it before the graph;
///   · the whole graph is ONE lavfi entry quoted in `[ … ]`, so mpv's own
///     `,`-split of `--af` never cuts inside it.
void main() {
  EqCurve curveWith(List<double> gains) => EqCurve(gains);

  group('Flat means no filter', () {
    test('the empty string, and no band entries', () {
      const EqCurve flat = EqCurve.flat();
      expect(EqFilter.build(flat), '');
      expect(EqFilter.bandEntries(flat), isEmpty);
    });

    test('a curve under the zero tolerance is Flat too', () {
      expect(
        EqFilter.build(const EqCurve(<double>[
          0.005, -0.005, 0, 0, 0, 0, 0, 0, 0, 0,
        ])),
        '',
      );
    });
  });

  group('the chain', () {
    final String s =
        EqFilter.build(curveWith(<double>[6, 0, 0, 0, 0, 0, 0, 0, 0, 0]));

    test('format conversion first, then one lavfi graph in [ ] quotes', () {
      expect(s, 'format=floatp,lavfi=[equalizer=f=31:t=q:w=1.1:g=6]');
      expect(s, startsWith('${EqFilter.formatEntry},lavfi=['));
      expect(s, endsWith(']'));
    });

    test('only the peaking equalizer is ever named', () {
      final String rock = EqFilter.build(
        TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve,
      );
      expect(rock, isNot(contains('anequalizer')));
      expect(rock, isNot(contains('superequalizer')));
      expect(rock, isNot(contains('firequalizer')));
      expect(rock, contains(EqFilter.marker));
    });

    test('one band element per live band, chained inside the graph', () {
      final String two = EqFilter.build(curveWith(<double>[
        6, 0, 0, 0, 0, 0, 0, 0, 0, -3,
      ]));
      final String body = two.substring(
        two.indexOf('[') + 1,
        two.length - 1,
      );
      final List<String> bands = body.split(',');
      expect(bands.length, 2);
      // Pinned literally: the Q of the bell is tuned by ear, so a change to
      // it should have to say so here.
      expect(bands[0], 'equalizer=f=31:t=q:w=1.1:g=6');
      expect(bands[1], 'equalizer=f=16000:t=q:w=1.1:g=-3');
      expect(two.contains('f=62'), isFalse);
    });

    test('the graph never splits on mpv\'s own comma — commas only inside [ ]',
        () {
      final String s = EqFilter.build(
        TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve,
      );
      final int open = s.indexOf('[');
      // The only comma before the quote is the one between the two entries.
      expect(s.substring(0, open).split(',').length, 2);
      expect(s.substring(open).endsWith(']'), isTrue);
    });

    test('numbers are written the shortest honest way', () {
      final String s = EqFilter.build(curveWith(<double>[
        0, 0, 0, 0, 0, 1, 0, 0, 0, -2.5,
      ]));
      expect(s.contains('g=1,'), isTrue); // not 1.0
      expect(s.contains('g=-2.5'), isTrue);
      expect(s.contains('+'), isFalse); // FFmpeg floats take no plus sign
      expect(s.contains('.0:'), isFalse);
      expect(s.contains('f=1000:'), isTrue); // not 1000.0
    });

    test('a whole preset is one element per non-silent band', () {
      final EqCurve rock =
          TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve;
      final int live =
          rock.gains.where((double g) => g.abs() >= kEqGainZero).length;
      expect(EqFilter.bandEntries(rock).length, live);
      expect(EqFilter.build(rock).length, lessThan(600));
    });
  });
}
