import 'dart:math' as math;

/// The pure math of the Tune panel (eq_imp.md §3 · §4 · §6).
///
/// Everything in this file is engine-free and unit-testable: the band grid,
/// the [EqCurve] / [PictureValues] payloads, and the [Continuum] — the ONE
/// selection language the four parts share ("a thin line with labeled
/// stops": a named stop, or a blend between two neighbours).
///
/// `core/tune_service.dart` owns the live state and talks to mpv; this file
/// only answers "what does position *t* mean?".

/// The four continua of the panel (eq_imp.md §1.2).
enum TunePart { eq, picture, aspect, speed }

/// Which preset set the audio line lays out (eq_imp.md §1.6).
enum TuneFileKind { audio, video }

// ── The locked grid (eq_imp.md §2) ─────────────────────────────────────────

/// 10 band centres, Hz, low → high.
const List<double> kEqBandFreqs = <double>[
  31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
];

/// Short spellings under the band sliders.
const List<String> kEqBandLabels = <String>[
  '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
];

/// Band widths in Hz (the `w=` of each peaking filter). Roughly one octave
/// in the middle, opened wide at the two ends so the lowest and highest
/// bands behave like shelves instead of narrow bells — a 10-band graphic EQ
/// that sounds like one. Tuning this by ear is the spec's own note
/// ("final numbers are tuned by ear during the build").
const List<double> kEqBandWidthsHz = <double>[
  62, 62, 88, 176, 354, 707, 1414, 2828, 5657, 8343,
];

const int kEqBandCount = 10;

/// Gain range, dB (eq_imp.md §2).
const double kEqGainMin = -12;
const double kEqGainMax = 12;

/// A gain this close to zero counts as zero: `Flat` then means "no filter at
/// all in the chain" (eq_imp.md §2's closing rule).
const double kEqGainZero = 0.01;

/// The picture fine-tune keys, in the spec's order (§1.2 / §4), each mapped
/// straight onto the mpv option of the same name.
const List<String> kPictureKeys = <String>[
  'saturation', 'gamma', 'contrast', 'brightness', 'hue',
];

/// Labels above the 5 fine sliders.
const List<String> kPictureLabels = <String>[
  'Sat', 'Gamma', 'Contrast', 'Bright', 'Hue',
];

/// mpv's range for every video-equalizer option (§6: −100…+100, 0 = neutral).
const double kPictureMin = -100;
const double kPictureMax = 100;

/// The speed line's span — linear in value, so 2×→3× feels no coarser than
/// 0.5×→0.75× (eq_imp.md §3).
const double kSpeedLineMin = 0.25;
const double kSpeedLineMax = 3.0;

double clampRange(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

double lerpDouble(double a, double b, double t) => a + (b - a) * t;

bool nearEqu(double a, double b, [double eps = 1e-9]) => (a - b).abs() <= eps;

// ── The EQ curve ───────────────────────────────────────────────────────────

/// An immutable 10-band gain set in dB.
class EqCurve {
  const EqCurve(this.gains);

  /// Everything at 0 — the reset state, and the state where no filter is
  /// installed in the audio chain at all.
  const EqCurve.flat()
      : gains = const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  final List<double> gains;

  int get length => gains.length;

  double at(int index) =>
      index >= 0 && index < gains.length ? gains[index] : 0;

  bool get isFlat => gains.every((double g) => g.abs() < kEqGainZero);

  EqCurve withBand(int index, double db) {
    final List<double> out = List<double>.of(gains);
    if (index >= 0 && index < out.length) {
      out[index] = clampRange(db, kEqGainMin, kEqGainMax);
    }
    return EqCurve(out);
  }

  /// Clamped to the ±12 dB grid and rounded to halves — the number the
  /// slider actually holds. Halves keep blends of presets free of float
  /// noise, so "does my curve match a preset?" stays an exact question.
  EqCurve quantized() => EqCurve(gains
      .map((double g) =>
          (clampRange(g, kEqGainMin, kEqGainMax) * 2).roundToDouble() / 2)
      .toList(growable: false));

  static EqCurve blend(EqCurve a, EqCurve b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final List<double> out = List<double>.filled(kEqBandCount, 0);
    for (int i = 0; i < kEqBandCount; i++) {
      out[i] = lerpDouble(a.at(i), b.at(i), t);
    }
    return EqCurve(out);
  }

  static bool same(EqCurve? a, EqCurve? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a.at(i) - b.at(i)).abs() > kEqGainZero) return false;
    }
    return true;
  }

  List<double> toList() => List<double>.unmodifiable(gains);

  List<double> toJson() => gains;

  static EqCurve fromJson(Object? raw) {
    if (raw is List) {
      final List<double> out = List<double>.filled(kEqBandCount, 0);
      for (int i = 0; i < kEqBandCount && i < raw.length; i++) {
        final Object? v = raw[i];
        out[i] = v is num ? clampRange(v.toDouble(), kEqGainMin, kEqGainMax) : 0;
      }
      return EqCurve(out);
    }
    return const EqCurve.flat();
  }

  @override
  bool operator ==(Object other) => other is EqCurve && same(this, other);

  @override
  int get hashCode => Object.hashAll(gains);
}

// ── The picture ────────────────────────────────────────────────────────────

/// The 5 fine values, each −100…+100 with 0 = neutral (eq_imp.md §4).
class PictureValues {
  const PictureValues({
    required this.saturation,
    required this.gamma,
    required this.contrast,
    required this.brightness,
    required this.hue,
  });

  /// Original — the untouched picture (also the reset state, and the A/B
  /// reference the continuum's first stop shows on hover).
  static const PictureValues original = PictureValues(
    saturation: 0,
    gamma: 0,
    contrast: 0,
    brightness: 0,
    hue: 0,
  );

  final double saturation;
  final double gamma;
  final double contrast;
  final double brightness;
  final double hue;

  bool get isNeutral =>
      saturation == 0 && gamma == 0 && contrast == 0 &&
      brightness == 0 && hue == 0;

  /// The same 5 values as a vector, in [kPictureKeys] order — the shape the
  /// looks and the blends are written in.
  List<double> get vector =>
      <double>[saturation, gamma, contrast, brightness, hue];

  PictureValues clamped() => PictureValues(
        saturation: clampRange(saturation, kPictureMin, kPictureMax),
        gamma: clampRange(gamma, kPictureMin, kPictureMax),
        contrast: clampRange(contrast, kPictureMin, kPictureMax),
        brightness: clampRange(brightness, kPictureMin, kPictureMax),
        hue: clampRange(hue, kPictureMin, kPictureMax),
      );

  PictureValues withValue(int index, double v) {
    final double c = clampRange(v.roundToDouble(), kPictureMin, kPictureMax);
    return PictureValues(
      saturation: index == 0 ? c : saturation,
      gamma: index == 1 ? c : gamma,
      contrast: index == 2 ? c : contrast,
      brightness: index == 3 ? c : brightness,
      hue: index == 4 ? c : hue,
    );
  }

  PictureValues withKey(String key, double v) {
    switch (key) {
      case 'saturation':
        return withValue(0, v);
      case 'gamma':
        return withValue(1, v);
      case 'contrast':
        return withValue(2, v);
      case 'brightness':
        return withValue(3, v);
      case 'hue':
        return withValue(4, v);
    }
    return this;
  }

  double valueAt(int index) {
    switch (index) {
      case 0:
        return saturation;
      case 1:
        return gamma;
      case 2:
        return contrast;
      case 3:
        return brightness;
      case 4:
        return hue;
    }
    return 0;
  }

  static PictureValues blend(PictureValues a, PictureValues b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return PictureValues(
      saturation: lerpDouble(a.saturation, b.saturation, t),
      gamma: lerpDouble(a.gamma, b.gamma, t),
      contrast: lerpDouble(a.contrast, b.contrast, t),
      brightness: lerpDouble(a.brightness, b.brightness, t),
      hue: lerpDouble(a.hue, b.hue, t),
    ).clamped();
  }

  static PictureValues fromVector(List<double> v) => PictureValues(
        saturation: v.isNotEmpty ? v[0] : 0.0,
        gamma: v.length > 1 ? v[1] : 0.0,
        contrast: v.length > 2 ? v[2] : 0.0,
        brightness: v.length > 3 ? v[3] : 0.0,
        hue: v.length > 4 ? v[4] : 0.0,
      ).clamped();

  Map<String, double> toJson() => <String, double>{
        'saturation': saturation,
        'gamma': gamma,
        'contrast': contrast,
        'brightness': brightness,
        'hue': hue,
      };

  static PictureValues fromJson(Object? raw) {
    if (raw is Map) {
      double read(String key) {
        final Object? v = raw[key];
        return v is num
            ? clampRange(v.toDouble(), kPictureMin, kPictureMax)
            : 0.0;
      }

      return PictureValues(
        saturation: read('saturation'),
        gamma: read('gamma'),
        contrast: read('contrast'),
        brightness: read('brightness'),
        hue: read('hue'),
      );
    }
    return original;
  }

  static bool same(PictureValues? a, PictureValues? b) {
    if (a == null || b == null) return a == b;
    return a.saturation == b.saturation &&
        a.gamma == b.gamma &&
        a.contrast == b.contrast &&
        a.brightness == b.brightness &&
        a.hue == b.hue;
  }

  @override
  bool operator ==(Object other) => other is PictureValues && same(this, other);

  @override
  int get hashCode => Object.hash(saturation, gamma, contrast, brightness, hue);
}

// ── The continuum ───────────────────────────────────────────────────────────

/// One named tick on a continuum line.
class ContinuumStop {
  const ContinuumStop(
    this.key,
    this.label, {
    this.value,
    this.vector,
  });

  /// Machine key — persisted, and the key the Auto EQ learning map stores.
  final String key;

  /// The short label printed under the line.
  final String label;

  /// Numeric payload for value continua (an aspect ratio, a speed). `null`
  /// means "no number of its own" — the aspect line's `Auto` stop, whose
  /// number is the file's own shape.
  final double? value;

  /// Blended payload for the curve/look continua (10 gains, or 5 picture
  /// values). `null` for value continua.
  final List<double>? vector;

  double get doubleValue => value ?? double.nan;
}

/// The result of locating a position on the line: the two neighbouring stops
/// and the fraction between them.
class ContinuumSpan {
  const ContinuumSpan(this.a, this.b, this.frac);

  final int a;
  final int b;

  /// 0 = exactly on [a], 1 = exactly on [b].
  final double frac;

  bool get isStop => a == b || frac <= 0 || frac >= 1;
}

/// How stops are spread along the line (eq_imp.md §3).
enum ContinuumSpacing {
  /// Evenly spaced, whatever the values behind them mean.
  even,

  /// Evenly spaced in value: `t = (v − min) / (max − min)`.
  linearInValue,
}

/// A thin line with labeled stops — knob on a stop (a named setting) or
/// between stops (a blend), with snapping and a label for every position.
class Continuum {
  Continuum({
    required this.stops,
    this.spacing = ContinuumSpacing.even,
    this.valueMin = 0,
    this.valueMax = 1,
    this.snapTolerance = 0.035,
  }) : positions = _positions(stops, spacing, valueMin, valueMax);

  final List<ContinuumStop> stops;
  final ContinuumSpacing spacing;
  final double valueMin;
  final double valueMax;

  /// How close to a stop a release has to be to snap to it (fraction of the
  /// whole line).
  final double snapTolerance;

  /// Precomputed `t` of every stop, in [stops] order.
  final List<double> positions;

  bool get isEmpty => stops.isEmpty;

  int get length => stops.length;

  ContinuumStop stopAt(int index) =>
      index >= 0 && index < stops.length ? stops[index] : stops[0];

  double positionOf(int index) =>
      index >= 0 && index < positions.length ? positions[index] : 0;

  int indexOfKey(String key) =>
      stops.indexWhere((ContinuumStop s) => s.key == key);

  /// The position a key sits at, or 0 when the key is unknown (a preset the
  /// new file type's set does not have — the knob parks at the line's head).
  double positionForKey(String key) {
    final int i = indexOfKey(key);
    return i < 0 ? 0 : positionOf(i);
  }

  /// Locate [t] between the stops. Clamped to the line.
  ContinuumSpan spanOf(double t) {
    if (positions.isEmpty) return const ContinuumSpan(0, 0, 0);
    final double x = clampRange(t, 0, 1);
    if (positions.length == 1) return const ContinuumSpan(0, 0, 0);
    if (x <= positions.first) return ContinuumSpan(0, 0, 0);
    if (x >= positions.last) {
      final int last = positions.length - 1;
      return ContinuumSpan(last, last, 0);
    }
    for (int i = 0; i < positions.length - 1; i++) {
      final double p0 = positions[i], p1 = positions[i + 1];
      if (x >= p0 && x <= p1) {
        final double span = p1 - p0;
        final double f = span <= 1e-9 ? 0 : (x - p0) / span;
        return ContinuumSpan(i, i + 1, clampRange(f, 0, 1));
      }
    }
    return ContinuumSpan(positions.length - 1, positions.length - 1, 0);
  }

  /// The stop nearest [t], whatever the distance.
  int nearestStop(double t) {
    if (positions.isEmpty) return 0;
    final double x = clampRange(t, 0, 1);
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < positions.length; i++) {
      final double d = (positions[i] - x).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// The stop within snap distance of [t] — [snap]'s answer.
  int? stopWithinTolerance(double t) {
    if (positions.isEmpty) return null;
    final int i = nearestStop(t);
    final double d = (positionOf(i) - clampRange(t, 0, 1)).abs();
    return d <= snapTolerance ? i : null;
  }

  /// Release within snap distance of a stop → snap to the named stop.
  double snap(double t) {
    final int? i = stopWithinTolerance(t);
    return i == null ? clampRange(t, 0, 1) : positionOf(i);
  }

  /// The blended payload at [t] (`null` when the line carries no vectors).
  List<double>? vectorAt(double t) {
    if (stops.isEmpty) return null;
    final ContinuumSpan span = spanOf(t);
    final List<double>? va = stopAt(span.a).vector;
    final List<double>? vb = span.b == span.a
        ? va
        : stopAt(span.b).vector;
    if (va == null || vb == null) return null;
    final int n = math.min(va.length, vb.length);
    final List<double> out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      out[i] = lerpDouble(va[i], vb[i], span.frac);
    }
    return out;
  }

  /// The numeric value at [t] (ratio, speed) — `null` when a neighbour has
  /// no number of its own (the aspect line's `Auto`).
  double? valueAt(double t) {
    if (stops.isEmpty) return null;
    final ContinuumSpan span = spanOf(t);
    final double? va = stopAt(span.a).value;
    if (va == null) return null;
    if (span.b == span.a || span.frac <= 0) return va;
    final double? vb = stopAt(span.b).value;
    if (vb == null) return null;
    return lerpDouble(va, vb, span.frac);
  }

  /// `t` of a numeric value on a [ContinuumSpacing.linearInValue] line.
  double positionForValue(double v) {
    if (valueMax <= valueMin) return 0;
    return clampRange((v - valueMin) / (valueMax - valueMin), 0, 1);
  }

  /// The value a numeric line holds at [t].
  double valueOnLine(double t) {
    final int? snapped = stopWithinTolerance(t);
    if (snapped != null) {
      final double? v = stops[snapped].value;
      if (v != null) return v;
    }
    return valueAt(t) ?? double.nan;
  }

  /// The exact stop [t] rests on (after snapping), else `null`.
  ContinuumStop? stopAtPosition(double t) {
    final int? i = stopWithinTolerance(t);
    return i == null ? null : stops[i];
  }

  static List<double> _positions(
    List<ContinuumStop> stops,
    ContinuumSpacing spacing,
    double valueMin,
    double valueMax,
  ) {
    final int n = stops.length;
    if (n == 0) return const <double>[];
    if (n == 1) return const <double>[0];
    final List<double> out = List<double>.filled(n, 0);
    if (spacing == ContinuumSpacing.even) {
      for (int i = 0; i < n; i++) {
        out[i] = i / (n - 1);
      }
      return out;
    }
    final double span = valueMax - valueMin;
    for (int i = 0; i < n; i++) {
      final double? v = stops[i].value;
      out[i] = v == null || span <= 0 ? 0 : clampRange((v - valueMin) / span, 0, 1);
    }
    return out;
  }
}

// ── Labels (the floating label's spelling — eq_imp.md §3) ─────────────────

/// The exact custom aspect value, `1.52:1`.
String formatAspectValue(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return 'Auto';
  return '${ratio.toStringAsFixed(2)}:1';
}

/// The exact custom speed, `1.37×` (trailing zeros trimmed: `1.5×`).
String formatSpeedValue(double speed) {
  if (!speed.isFinite || speed <= 0) return '1×';
  String s = speed.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return '${s}×';
}

/// A blended pair, `Pop ↔ Rock`.
String formatBlendPair(String a, String b) => '$a ↔ $b';

/// An EQ gain as the value chip spells it: `+3`, `0`, `−4.5` dB.
String formatGainDb(double gain) {
  final double q = (gain * 2).roundToDouble() / 2;
  final String magnitude =
      q == q.roundToDouble() ? q.abs().toStringAsFixed(0) : q.abs().toStringAsFixed(1);
  if (q == 0) return '0';
  return '${q > 0 ? '+' : '−'}$magnitude';
}
