import 'tune_model.dart';

/// The locked preset tables (eq_imp.md §2) and the four continuum shapes
/// (§3). Numbers are the spec's starting curves — dB, −12…+12.

/// One audio preset: a name, a short label for the line, and 10 gains.
class EqPreset {
  const EqPreset(this.key, this.label, this.gains);

  final String key;
  final String label;
  final List<double> gains;

  EqCurve get curve => EqCurve(gains);

  ContinuumStop get stop =>
      ContinuumStop(key, label, vector: List<double>.unmodifiable(gains));
}

/// One picture look: 5 values in [kPictureKeys] order.
class PictureLook {
  const PictureLook(this.key, this.label, this.values);

  final String key;
  final String label;
  final List<double> values;

  PictureValues get picture => PictureValues.fromVector(values);

  ContinuumStop get stop =>
      ContinuumStop(key, label, vector: List<double>.unmodifiable(values));
}

class TunePresets {
  TunePresets._();

  // ── Audio file set — 13 preset stops (+ My, which is not a stop) ──────

  static const List<EqPreset> audio = <EqPreset>[
    EqPreset('flat', 'Flat', <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqPreset('pop', 'Pop', <double>[1, 2, 3, 5, 3, 1, -1, -2, -1, 0]),
    EqPreset('rock', 'Rock', <double>[5, 4, 3, 1, -2, -1, 2, 3, 4, 5]),
    EqPreset('jazz', 'Jazz', <double>[4, 3, 1, 0, -2, -2, 0, 1, 2, 3]),
    EqPreset('classical', 'Class', <double>[5, 4, 3, 2, -2, -3, -3, -1, 2, 4]),
    EqPreset('bass', 'Bass', <double>[10, 8, 6, 3, 0, -1, -2, -2, -1, 0]),
    EqPreset('treble', 'Treb', <double>[-1, -1, 0, 0, 1, 2, 4, 6, 8, 10]),
    EqPreset('vshape', 'V-Shape', <double>[8, 6, 3, 1, -2, -2, 1, 4, 7, 9]),
    EqPreset('vocal', 'Vocal', <double>[-2, -3, -4, -2, 0, 3, 5, 4, 2, 0]),
    EqPreset('lounge', 'Lounge', <double>[4, 3, 2, 2, 0, -1, -2, -3, -2, -1]),
    EqPreset('live', 'Live', <double>[3, 2, 1, 0, 2, 3, 4, 5, 6, 7]),
    EqPreset('dance', 'Dance', <double>[9, 8, 5, 2, -1, -1, 1, 3, 5, 7]),
    EqPreset('phone', 'Phone', <double>[-6, -5, -4, -3, -1, 1, 2, 3, 2, 0]),
  ];

  // ── Video file set — 4 preset stops (+ My) ─────────────────────────────

  static const List<EqPreset> video = <EqPreset>[
    EqPreset('flat', 'Flat', <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqPreset('movie', 'Movie', <double>[4, 3, 1, 0, 1, 2, 3, 4, 3, 2]),
    EqPreset('musicvideo', 'Music V', <double>[7, 5, 3, 1, 0, 1, 2, 4, 5, 3]),
    EqPreset('documentary', 'Doc', <double>[-3, -3, -2, 0, 1, 3, 4, 3, 1, 0]),
  ];

  static List<EqPreset> forKind(TuneFileKind kind) =>
      kind == TuneFileKind.audio ? audio : video;

  static Continuum audioContinuum(TuneFileKind kind) => Continuum(
        stops: forKind(kind)
            .map((EqPreset p) => p.stop)
            .toList(growable: false),
      );

  static EqPreset? presetByKey(String? key, TuneFileKind kind) {
    if (key == null) return null;
    for (final EqPreset p in forKind(kind)) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// Which preset (if any) this exact curve is — the rule behind §1.6's
  /// "when it matches a preset of the new set the knob sits on that stop",
  /// and behind a stop staying lit while the viewer watches it.
  static EqPreset? matchCurve(EqCurve curve, TuneFileKind kind) {
    for (final EqPreset p in forKind(kind)) {
      if (EqCurve.same(p.curve, curve)) return p;
    }
    return null;
  }

  /// The single loudest ask on the line (signed) — the headroom note the
  /// panel shows beside the marks. Kept simple on purpose: the number, not a
  /// limiter, and never a warning colour.
  static double peakGain(EqCurve curve) {
    double peak = 0;
    for (final double g in curve.gains) {
      if (g.abs() > peak.abs()) peak = g;
    }
    return peak;
  }

  // ── Picture looks (eq_imp.md §3's table) ───────────────────────────────

  /// Saturation · Gamma · Contrast · Brightness · Hue, each −100…+100.
  static const List<PictureLook> looks = <PictureLook>[
    PictureLook('original', 'Original', <double>[0, 0, 0, 0, 0]),
    PictureLook('vivid', 'Vivid', <double>[26, -6, 14, 5, 0]),
    PictureLook('night', 'Night', <double>[-6, 30, -14, 12, 0]),
    PictureLook('faded', 'Faded', <double>[-24, 8, -26, 9, 0]),
    PictureLook('warm', 'Warm', <double>[8, 0, 4, 2, -6]),
    PictureLook('cool', 'Cool', <double>[6, 0, 5, 1, 7]),
  ];

  static Continuum pictureContinuum() => Continuum(
        stops: looks
            .map((PictureLook l) => l.stop)
            .toList(growable: false),
      );

  static PictureLook? lookByKey(String? key) {
    if (key == null) return null;
    for (final PictureLook l in looks) {
      if (l.key == key) return l;
    }
    return null;
  }

  /// The look (if any) these exact 5 values are.
  static PictureLook? matchPicture(PictureValues values) {
    for (final PictureLook l in looks) {
      if (PictureValues.same(l.picture, values)) return l;
    }
    return null;
  }

  // ── Aspect shapes (eq_imp.md §1.2 Part 3) ──────────────────────────────

  /// `Auto` carries no number — its number is the file's own shape.
  static const List<ContinuumStop> aspectStops = <ContinuumStop>[
    ContinuumStop('auto', 'Auto'),
    ContinuumStop('a4_3', '4:3', value: 1.333333),
    ContinuumStop('a16_9', '16:9', value: 1.777778),
    ContinuumStop('a185', '1.85', value: 1.85),
    ContinuumStop('a235', '2.35', value: 2.35),
    ContinuumStop('a219', '21:9', value: 2.333333),
    ContinuumStop('a1_1', '1:1', value: 1.0),
    ContinuumStop('a916', '9:16', value: 0.5625),
  ];

  static Continuum aspectContinuum() =>
      Continuum(stops: aspectStops, snapTolerance: 0.028);

  /// `Auto` is the shape a snap-to-stop release lands on.
  static bool isAspectAuto(String? stopKey) => stopKey == null || stopKey == 'auto';

  // ── Speeds (eq_imp.md §3 — the one line that is not evenly spaced) ─────

  static const List<ContinuumStop> speedStops = <ContinuumStop>[
    ContinuumStop('x0_5', '0.5×', value: 0.5),
    ContinuumStop('x0_75', '0.75×', value: 0.75),
    ContinuumStop('x1', '1×', value: 1.0),
    ContinuumStop('x1_25', '1.25×', value: 1.25),
    ContinuumStop('x1_5', '1.5×', value: 1.5),
    ContinuumStop('x2', '2×', value: 2.0),
    ContinuumStop('x3', '3×', value: 3.0),
  ];

  static Continuum speedContinuum() => Continuum(
        stops: speedStops,
        spacing: ContinuumSpacing.linearInValue,
        valueMin: kSpeedLineMin,
        valueMax: kSpeedLineMax,
        snapTolerance: 0.02,
      );

  /// The speed stop this value sits on (exact, after the line's snapping).
  static ContinuumStop? speedStopForValue(double speed) {
    for (final ContinuumStop s in speedStops) {
      final double? v = s.value;
      if (v != null && (v - speed).abs() < 1e-6) return s;
    }
    return null;
  }
}

/// A scene (eq_imp.md §7b) — one mark that moves the four lines together.
///
/// Only the fields a scene NAMES are touched: a scene never silently clears
/// something it did not come to change, and keep-pitch is never a scene's
/// business (a scene is a sound and a look, not a preference). The three
/// locked scenes name everything but pitch.
class TuneScene {
  const TuneScene({
    required this.key,
    required this.label,
    required this.note,
    this.eqPreset,
    this.pictureLook,
    this.aspectStop,
    this.speedStop,
    this.snapWindow,
  });

  /// Machine key (persisted nowhere yet — a scene is a gesture, not a state).
  final String key;

  /// The short name on its mark.
  final String label;

  /// One honest line for the tooltip: what this mark moves.
  final String note;

  /// An EQ preset key of the file's own set — skipped when the playing file's
  /// line does not have it (a video line has no `vocal`).
  final String? eqPreset;

  /// A picture look key.
  final String? pictureLook;

  /// An aspect stop key (`auto` = the file's own shape).
  final String? aspectStop;

  /// A speed stop key.
  final String? speedStop;

  /// Whether "the window is the screen" is part of the scene.
  final bool? snapWindow;

  /// The three locked scenes (eq_imp.md §7b).
  static const List<TuneScene> all = <TuneScene>[
    TuneScene(
      key: 'cinema',
      label: 'Cinema',
      note: 'Cinema · the window takes the film’s shape, Night look, Movie sound',
      eqPreset: 'movie',
      pictureLook: 'night',
      aspectStop: 'auto',
      speedStop: 'x1',
      snapWindow: true,
    ),
    TuneScene(
      key: 'podcast',
      label: 'Podcast',
      note: 'Podcast · Vocal sound, normal speed, no window snap',
      eqPreset: 'vocal',
      pictureLook: 'original',
      aspectStop: 'auto',
      speedStop: 'x1',
      snapWindow: false,
    ),
    TuneScene(
      key: 'vivid',
      label: 'Vivid',
      note: 'Vivid · Vivid look, Flat sound, the file’s own shape',
      eqPreset: 'flat',
      pictureLook: 'vivid',
      aspectStop: 'auto',
      speedStop: 'x1',
      snapWindow: false,
    ),
  ];

  static TuneScene? byKey(String? key) {
    if (key == null) return null;
    for (final TuneScene s in all) {
      if (s.key == key) return s;
    }
    return null;
  }
}
