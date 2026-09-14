import 'dart:convert';

import 'tune_model.dart';

/// The whole Tune panel as ONE persisted value (eq_imp.md §6: "one settings
/// entry"), and the snapshot type the hover preview reverts to (§8).
///
/// Both the knob position (`*Knob`) and the values it produced are stored:
/// the position is what makes a reload land back on "Pop ↔ Rock" instead of
/// on a nearest-preset approximation, and the values are what survive a file
/// type change (eq_imp.md §1.6: "your current curve is kept").
class TuneState {
  const TuneState({
    required this.kind,
    required this.eqGains,
    required this.eqKnob,
    required this.eqStop,
    required this.picture,
    required this.pictureKnob,
    required this.pictureStop,
    required this.aspectKnob,
    required this.aspectStop,
    required this.speed,
    required this.speedKnob,
    required this.speedStop,
    required this.keepPitch,
    required this.snapWindow,
    required this.curveOnVideo,
    this.my,
  });

  /// The factory default: nothing touched, nothing in the audio chain, the
  /// picture untouched, the file's own shape, normal speed.
  static const TuneState initial = TuneState(
    kind: TuneFileKind.video,
    eqGains: <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    eqKnob: 0,
    eqStop: 'flat',
    picture: PictureValues.original,
    pictureKnob: 0,
    pictureStop: 'original',
    aspectKnob: 0,
    aspectStop: 'auto',
    speed: 1.0,
    speedKnob: 0.2727272727272727,
    speedStop: 'x1',
    keepPitch: true,
    snapWindow: false,
    curveOnVideo: false,
  );

  /// Which preset set the audio line was laid out with when this was saved.
  final TuneFileKind kind;

  final List<double> eqGains;
  final double eqKnob;
  final String? eqStop;

  final PictureValues picture;
  final double pictureKnob;
  final String? pictureStop;

  final double aspectKnob;

  /// `auto` (or a shaped stop) — `aspectStop == 'auto'` means the file's own
  /// shape, which is what "the window is the screen" reads.
  final String? aspectStop;

  final double speed;
  final double speedKnob;
  final String? speedStop;

  final bool keepPitch;
  final bool snapWindow;
  final bool curveOnVideo;

  /// The saved "My" curve (`null` = the slot is empty).
  final List<double>? my;

  EqCurve get eqCurve => EqCurve(eqGains);

  EqCurve? get myCurve => my == null ? null : EqCurve(my!);

  bool get aspectAuto => aspectStop == null || aspectStop == 'auto';

  TuneState copyWith({
    TuneFileKind? kind,
    List<double>? eqGains,
    double? eqKnob,
    String? eqStop,
    bool clearEqStop = false,
    PictureValues? picture,
    double? pictureKnob,
    String? pictureStop,
    bool clearPictureStop = false,
    double? aspectKnob,
    String? aspectStop,
    double? speed,
    double? speedKnob,
    String? speedStop,
    bool? keepPitch,
    bool? snapWindow,
    bool? curveOnVideo,
    List<double>? my,
    bool clearMy = false,
  }) {
    return TuneState(
      kind: kind ?? this.kind,
      eqGains: eqGains ?? this.eqGains,
      eqKnob: eqKnob ?? this.eqKnob,
      eqStop: clearEqStop ? null : (eqStop ?? this.eqStop),
      picture: picture ?? this.picture,
      pictureKnob: pictureKnob ?? this.pictureKnob,
      pictureStop: clearPictureStop ? null : (pictureStop ?? this.pictureStop),
      aspectKnob: aspectKnob ?? this.aspectKnob,
      aspectStop: aspectStop ?? this.aspectStop,
      speed: speed ?? this.speed,
      speedKnob: speedKnob ?? this.speedKnob,
      speedStop: speedStop ?? this.speedStop,
      keepPitch: keepPitch ?? this.keepPitch,
      snapWindow: snapWindow ?? this.snapWindow,
      curveOnVideo: curveOnVideo ?? this.curveOnVideo,
      my: clearMy ? null : (my ?? this.my),
    );
  }

  // ── JSON ───────────────────────────────────────────────────────────────

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'kind': kind == TuneFileKind.audio ? 'audio' : 'video',
        'eq': eqGains,
        'eqKnob': eqKnob,
        if (eqStop != null) 'eqStop': eqStop,
        'pic': picture.toJson(),
        'picKnob': pictureKnob,
        if (pictureStop != null) 'picStop': pictureStop,
        'aspKnob': aspectKnob,
        if (aspectStop != null) 'aspStop': aspectStop,
        'spd': speed,
        'spdKnob': speedKnob,
        if (speedStop != null) 'spdStop': speedStop,
        'keepPitch': keepPitch,
        'snap': snapWindow,
        'curve': curveOnVideo,
        if (my != null) 'my': my,
      };

  String encode() => jsonEncode(toJson());

  /// Tolerant by design: a missing key keeps the default, a broken blob
  /// returns [TuneState.initial] — a bad settings file must never take
  /// playback down with it.
  static TuneState decode(Object? raw) {
    Map<String, dynamic>? map;
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? d = jsonDecode(raw);
        if (d is Map<String, dynamic>) map = d;
      } catch (_) {
        map = null;
      }
    } else if (raw is Map<String, dynamic>) {
      map = raw;
    }
    if (map == null) return initial;

    double num_(String key, double fallback) {
      final Object? v = map[key];
      return v is num ? v.toDouble() : fallback;
    }

    bool flag(String key, bool fallback) {
      final Object? v = map[key];
      return v is bool ? v : fallback;
    }

    String? text(String key) {
      final Object? v = map[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    List<double>? list(String key) {
      final Object? v = map[key];
      if (v is! List) return null;
      final List<double> out = List<double>.filled(kEqBandCount, 0);
      for (int i = 0; i < kEqBandCount && i < v.length; i++) {
        final Object? e = v[i];
        out[i] = e is num
            ? clampRange(e.toDouble(), kEqGainMin, kEqGainMax)
            : 0.0;
      }
      return out;
    }

    final List<double>? gains = list('eq');
    final List<double>? myGains = list('my');

    return TuneState(
      kind: text('kind') == 'audio' ? TuneFileKind.audio : TuneFileKind.video,
      eqGains: gains ?? initial.eqGains,
      eqKnob: clampRange(num_('eqKnob', 0), 0, 1),
      eqStop: text('eqStop'),
      picture: PictureValues.fromJson(map['pic']),
      pictureKnob: clampRange(num_('picKnob', 0), 0, 1),
      pictureStop: text('picStop'),
      aspectKnob: clampRange(num_('aspKnob', 0), 0, 1),
      aspectStop: text('aspStop') ?? 'auto',
      speed: clampRange(num_('spd', 1), kSpeedLineMin, kSpeedLineMax),
      speedKnob: clampRange(num_('spdKnob', initial.speedKnob), 0, 1),
      speedStop: text('spdStop'),
      keepPitch: flag('keepPitch', true),
      snapWindow: flag('snap', false),
      curveOnVideo: flag('curve', false),
      my: myGains,
    );
  }
}
