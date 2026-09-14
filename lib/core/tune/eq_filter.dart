import 'tune_model.dart';

/// The one place SALU spells an EQ curve as an mpv audio-filter string
/// (eq_imp.md §6: "the anequalizer filter-string builder").
///
/// mpv's own `audio-equalizer` options no longer exist in the libmpv build
/// media_kit ships, so the EQ is handed to libavfilter through mpv's `lavfi`
/// audio wrapper — with the graph quoted in `[ … ]`, which is exactly what
/// mpv's filter syntax prescribes for values containing `=` or `,`
/// (DOCS/man/vf.rst: "param-value can further be quoted in [ / ]").
///
/// Two spellings, tried in this order by the engine:
///
///  * [primary] — FFmpeg's multi-band `anequalizer`. One filter instance
///    holds all 10 bands; its `params` string names a channel per band, so
///    the entry list repeats for c0…c7 (7.1 = 8 channels; FFmpeg ignores
///    entries whose channel the input does not have).
///  * [fallback] — 10 chained single-band `equalizer` peaking filters, one
///    per mpv filter entry (no commas inside a graph, so nothing to escape).
///    Present because `anequalizer` is not in every libavfilter build, and a
///    dead EQ is worse than a plainer one.
///
/// `Flat` (every gain 0) builds the EMPTY string — the engine then removes
/// the filter from the chain completely, so nothing extra sits in the audio
/// path (eq_imp.md §2's closing rule).
class EqFilter {
  EqFilter._();

  /// Channels the primary spelling covers: stereo through 7.1.
  static const int maxChannels = 8;

  /// Q of each fallback band — a graphic-EQ bell (~1.1 gives the classic
  /// ISO-octave overlap without ringing).
  static const double fallbackQ = 1.1;

  /// The primary `params` string for one curve (`Flat` → `null`).
  static String? params(EqCurve curve) {
    if (curve.isFlat) return null;
    final List<String> bands = <String>[];
    for (int ch = 0; ch < maxChannels; ch++) {
      for (int i = 0; i < kEqBandCount; i++) {
        final double g = curve.at(i);
        if (g.abs() < kEqGainZero) continue;
        bands.add('c$ch f=${_num(kEqBandFreqs[i])} '
            'w=${_num(kEqBandWidthsHz[i])} g=${_num(g)} t=0');
      }
    }
    if (bands.isEmpty) return null;
    return bands.join('|');
  }

  /// The mpv `af` value that carries the curve — `''` when Flat (no filter).
  static String primary(EqCurve curve) {
    final String? p = params(curve);
    if (p == null) return '';
    return 'lavfi=[anequalizer=params=$p]';
  }

  /// The fallback `af` value — one peaking `equalizer` per non-zero band.
  static String fallback(EqCurve curve) {
    if (curve.isFlat) return '';
    final List<String> entries = <String>[];
    for (int i = 0; i < kEqBandCount; i++) {
      final double g = curve.at(i);
      if (g.abs() < kEqGainZero) continue;
      entries.add('lavfi=[equalizer='
          'f=${_num(kEqBandFreqs[i])}'
          ':t=q'
          ':w=${_num(fallbackQ)}'
          ':g=${_num(g)}'
          ']');
    }
    return entries.join(',');
  }

  /// Both spellings, in the order the engine tries them. Empty strings are
  /// dropped — `''` means "no filter", which the caller applies as itself.
  static List<String> candidates(EqCurve curve) {
    if (curve.isFlat) return const <String>[''];
    final String a = primary(curve);
    final String b = fallback(curve);
    return <String>[a, if (b.isNotEmpty) b];
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
