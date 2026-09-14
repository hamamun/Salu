import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/tune/eq_filter.dart';
import 'package:salu/core/tune/tune_model.dart';
import 'package:salu/core/tune/tune_presets.dart';

/// The `--af` strings SALU hands mpv (eq_imp.md §6's named unit test: "the
/// anequalizer filter-string builder"). This is the one place where a typo
/// becomes a silent audio failure, so the shape is pinned here rather than
/// discovered by ear:
///
///   · `Flat` builds NOTHING — the filter leaves the chain entirely (§2);
///   · bands with no gain are skipped, so the string stays short;
///   · numbers are bare (`g=6`, `g=-2.5`) — FFmpeg parses no `+`, and a
///     trailing `.0` in an 8-channel × 10-band string is noise;
///   · the primary spelling carries no comma outside its `[ … ]` quoting,
///     which is what lets mpv split `--af` correctly at all.
void main() {
  EqCurve curveWith(List<double> gains) => EqCurve(gains);

  group('Flat means no filter', () {
    test('the empty string, from every builder', () {
      const EqCurve flat = EqCurve.flat();
      expect(EqFilter.params(flat), isNull);
      expect(EqFilter.primary(flat), '');
      expect(EqFilter.fallback(flat), '');
      expect(EqFilter.candidates(flat), <String>['']);
    });

    test('a curve under the zero tolerance is Flat too', () {
      expect(
        EqFilter.primary(const EqCurve(<double>[
          0.005, -0.005, 0, 0, 0, 0, 0, 0, 0, 0,
        ])),
        '',
      );
    });
  });

  group('the primary (anequalizer) spelling', () {
    final String s =
        EqFilter.primary(curveWith(<double>[6, 0, 0, 0, 0, 0, 0, 0, 0, 0]));

    test('one lavfi entry, quoted against the comma split', () {
      expect(s, startsWith('lavfi=[anequalizer=params='));
      expect(s, endsWith(']'));
      // No bare comma: `[ … ]` is the quoting mpv's filter parser expects.
      expect(s.contains(','), isFalse);
    });

    test('every channel repeats the entry list, bands joined by |', () {
      final String body = s.substring(
        s.indexOf('params=') + 'params='.length,
        s.length - 1,
      );
      final List<String> bands = body.split('|');
      expect(bands.length, EqFilter.maxChannels);
      for (int ch = 0; ch < EqFilter.maxChannels; ch++) {
        expect(bands[ch], 'c$ch f=31 w=62 g=6 t=0');
      }
    });

    test('a zero band is not in the string at all', () {
      final String two = EqFilter.primary(curveWith(<double>[
        6, 0, 0, 0, 0, 0, 0, 0, 0, -3,
      ]));
      final String body = two.substring(
        two.indexOf('params=') + 'params='.length,
        two.length - 1,
      );
      // 8 channels × 2 live bands.
      expect(body.split('|').length, EqFilter.maxChannels * 2);
      expect(body.contains(' f=31 '), isTrue);
      expect(body.contains(' f=16000 '), isTrue);
      expect(body.contains(' f=62 '), isFalse);
    });

    test('numbers are written the shortest honest way', () {
      final String s = EqFilter.primary(curveWith(<double>[
        0, 0, 0, 0, 0, 1, 0, 0, 0, -2.5,
      ]));
      expect(s.contains('g=1 '), isTrue); // not 1.0
      expect(s.contains('g=-2.5'), isTrue);
      expect(s.contains('+'), isFalse); // FFmpeg floats take no plus sign
      expect(s.contains('.0 '), isFalse);
      expect(s.contains('f=1000 '), isTrue); // not 1000.0
    });

    test('a whole preset builds a string that fits mpv comfortably', () {
      final EqCurve rock =
          TunePresets.presetByKey('rock', TuneFileKind.audio)!.curve;
      final String s = EqFilter.primary(rock);
      // 5 of Rock's 10 bands are inside the zero tolerance? (none are) — so
      // 8 channels × every non-silent band.
      final int live = rock.gains
          .where((double g) => g.abs() >= kEqGainZero)
          .length;
      expect(
        s
            .substring(s.indexOf('params=') + 7, s.length - 1)
            .split('|')
            .length,
        live * EqFilter.maxChannels,
      );
      expect(s.length, lessThan(4000));
    });
  });

  group('the fallback (chained peaking) spelling', () {
    test('one comma-separated lavfi entry per live band', () {
      final String s = EqFilter.fallback(curveWith(<double>[
        6, 0, 0, 0, 0, 0, 0, 0, 0, -3,
      ]));
      final List<String> entries = s.split(',');
      expect(entries.length, 2);
      // Pinned literally: the Q of the fallback bell is tuned by ear, so a
      // change to it should have to say so here.
      expect(entries[0], 'lavfi=[equalizer=f=31:t=q:w=1.1:g=6]');
      expect(entries[1], contains('f=16000'));
      expect(entries[1], contains('g=-3'));
    });

    test('it carries no per-channel list (the filter mixes down itself)', () {
      expect(
        EqFilter.fallback(curveWith(<double>[
          6, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ])),
        isNot(contains('c0')),
      );
    });
  });

  group('candidates', () {
    test('the primary is tried first, the fallback behind it', () {
      final EqCurve c = TunePresets.presetByKey('bass', TuneFileKind.audio)!.curve;
      final List<String> list = EqFilter.candidates(c);
      expect(list.length, 2);
      expect(list.first, EqFilter.primary(c));
      expect(list[1], EqFilter.fallback(c));
    });
  });
}
