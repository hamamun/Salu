import 'tune_model.dart';

/// The one place SALU spells an EQ curve as an mpv audio-filter string
/// (eq_imp.md §6: "the filter-string builder").
///
/// The libmpv that media_kit ships for Windows is built against a slimmed
/// FFmpeg (`--disable-filters`, then only a handful re-enabled). Of the
/// libavfilter equalizers, ONLY the single-band peaking `equalizer` is in that
/// build — `anequalizer`, `superequalizer` and `firequalizer` are not, and
/// asking for one of them makes mpv print "Audio filter initialized failed!"
/// and, when the request lands before the audio chain exists (a file
/// landing), disable the audio track outright. So the curve is spelled as a
/// chain of `equalizer` bells, one per non-zero band, inside ONE `lavfi`
/// graph.
///
/// The graph is preceded by mpv's own `format=floatp`. The peaking filter
/// only takes PLANAR samples, and the slim build has no `aresample` for
/// libavfilter to convert with — FLAC, WAV, Opus and PCM decoders hand mpv
/// packed samples, which would fail to configure the graph ("'aresample'
/// filter not present"). `format=floatp` makes mpv's own converter (its
/// built-in swresample wrapper, always present) hand the graph planar float,
/// which is also the format the bell processes natively.
///
/// The graph is quoted in `[ … ]`, which is exactly what mpv's filter syntax
/// prescribes for values containing `=` , `:` or `,` (DOCS/man/vf.rst:
/// "param-value can further be quoted in [ / ]").
///
/// `Flat` (every gain 0) builds the EMPTY string — the engine then removes
/// the filter from the chain completely, so nothing extra sits in the audio
/// path (eq_imp.md §2's closing rule).
class EqFilter {
  EqFilter._();

  /// Q of each band — a graphic-EQ bell (~1.1 gives the classic ISO-octave
  /// overlap without ringing). Tuned by ear, as the spec allows.
  static const double bandQ = 1.1;

  /// The conversion request in front of the graph (see the class note).
  static const String formatEntry = 'format=floatp';

  /// The substring that proves the chain is in mpv's `af` list when it is
  /// read back — the engine checks for it because media_kit's property write
  /// reports no error (see [MpvTuneEngine.setEqCurve]).
  static const String marker = 'equalizer=';

  /// The mpv `af` value that carries the curve — `''` when Flat (no filter).
  static String build(EqCurve curve) {
    final List<String> bands = bandEntries(curve);
    if (bands.isEmpty) return '';
    return '$formatEntry,lavfi=[${bands.join(',')}]';
  }

  /// One `equalizer=` element per non-zero band, in band order.
  static List<String> bandEntries(EqCurve curve) {
    if (curve.isFlat) return const <String>[];
    final List<String> entries = <String>[];
    for (int i = 0; i < kEqBandCount; i++) {
      final double g = curve.at(i);
      if (g.abs() < kEqGainZero) continue;
      entries.add('equalizer='
          'f=${_num(kEqBandFreqs[i])}'
          ':t=q'
          ':w=${_num(bandQ)}'
          ':g=${_num(g)}');
    }
    return entries;
  }

  /// Shortest honest number: `31`, `5`, `-2.5` — no trailing zeros, no `+`.
  /// FFmpeg parses both ints and floats here, and a bare `-` reads cleaner
  /// in logs than `+-2.500000`.
  static String _num(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    String s = v.toStringAsFixed(2);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}
