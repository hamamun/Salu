import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_utils.dart';
import 'player_service.dart';
import 'queue_service.dart';
import 'settings_service.dart';
import 'tune/auto_eq.dart';
import 'tune/eq_memory.dart';
import 'tune/tune_engine.dart';
import 'tune/tune_model.dart';
import 'tune/tune_presets.dart';
import 'tune/tune_state.dart';

/// The single owner of every value the Tune panel shows (eq_imp.md §6:
/// "one core service owns all values — the button, the panel and the engine
/// can never disagree").
///
/// The four parts are four [Continuum] lines over one state machine:
///
///  * a **knob position** (0…1 on the line) — the selection language;
///  * the **values** that position produced (10 gains, 5 picture values, a
///    ratio, a speed), which the fine sliders can leave the line behind and
///    turn into `Custom`;
///  * a **kept / drag / hover-preview** distinction (§8) — a hover shows it
///    live and reverts, a click or a released drag keeps it and persists.
///
/// Nothing in here knows what mpv is: values leave through [TuneEngine]
/// only, so the whole machine is unit-testable and a refused filter write
/// can never strand the UI with values nobody set.
class TuneService {
  TuneService._internal();

  /// The one and only Tune state for the whole player — one shared EQ for
  /// every file (eq_imp.md §1.5: the per-file memories were dropped).
  static final TuneService instance = TuneService._internal();

  /// One settings entry for the panel, one for the learning map.
  static const String stateKey = 'tune_state';
  static const String memoryKey = 'eq_auto_memory';

  /// Disk writes coalesce while a slider is being dragged.
  static const Duration persistDebounce = Duration(milliseconds: 400);

  /// An `af` write rebuilds mpv's audio chain, so drags coalesce to one
  /// write per this gap — imperceptible, and the last value always lands.
  static const Duration eqWriteGap = Duration(milliseconds: 120);

  /// How long a pointer must rest on a control before it previews (§8).
  static const Duration hoverLead = Duration(milliseconds: 300);

  /// How long the file's own shape is chased at load before SALU gives up.
  static const int _aspectTries = 6;
  static const Duration _aspectGap = Duration(milliseconds: 200);

  /// The mpv engine, attached lazily the way the subtitle engine is — no
  /// bootstrap step can forget it, and a run with no player (a test, a
  /// headless start) simply never touches it. Tests swap it for a recorder.
  TuneEngine get engine => _engine ??= MpvTuneEngine();
  set engine(TuneEngine value) => _engine = value;
  TuneEngine? _engine;

  /// The Auto EQ learning map (bounded — §5's data policy).
  final EqMemory memory = EqMemory.empty();

  // ── State ──────────────────────────────────────────────────────────────

  /// Which preset set the audio line lays out with (§1.6).
  final ValueNotifier<TuneFileKind> fileKind =
      ValueNotifier<TuneFileKind>(TuneFileKind.video);

  /// Whether the panel can act right now: local media, not a channel list.
  /// False greys the button and silences every write (§12).
  final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// False on audio-only files — the panel dims its video parts (§12).
  final ValueNotifier<bool> videoPartsActive = ValueNotifier<bool>(true);

  final ValueNotifier<EqCurve> eq =
      ValueNotifier<EqCurve>(const EqCurve.flat());
  final ValueNotifier<double> eqKnob = ValueNotifier<double>(0);
  final ValueNotifier<String?> eqStop = ValueNotifier<String?>('flat');

  /// True while the bands carry gains the line cannot name: the knob rests
  /// on the nearest stop and the label reads `Custom` (§4's rule, mirrored
  /// onto the audio line).
  final ValueNotifier<bool> eqCustom = ValueNotifier<bool>(false);

  final ValueNotifier<PictureValues> picture =
      ValueNotifier<PictureValues>(PictureValues.original);
  final ValueNotifier<double> pictureKnob = ValueNotifier<double>(0);
  final ValueNotifier<String?> pictureStop =
      ValueNotifier<String?>('original');
  final ValueNotifier<bool> pictureCustom = ValueNotifier<bool>(false);

  /// The aspect line's knob, its stop (`null` = between stops) and the ratio
  /// in force (`0` = the file's own shape).
  final ValueNotifier<double> aspectKnob = ValueNotifier<double>(0);
  final ValueNotifier<String?> aspectStop = ValueNotifier<String?>('auto');
  final ValueNotifier<double> aspectRatio = ValueNotifier<double>(0);

  final ValueNotifier<double> speed = ValueNotifier<double>(1);
  final ValueNotifier<double> speedKnob =
      ValueNotifier<double>(TuneState.initial.speedKnob);
  final ValueNotifier<String?> speedStop = ValueNotifier<String?>('x1');

  /// ON = mpv keeps the pitch natural at any speed (the default); OFF drops
  /// the correction, so the classic tape-style shift comes with the speed
  /// change (§6).
  final ValueNotifier<bool> keepPitch = ValueNotifier<bool>(true);

  /// "The window is the screen" (§1.10).
  final ValueNotifier<bool> snapWindow = ValueNotifier<bool>(false);

  /// Draw the curve on the picture itself (§1.9).
  final ValueNotifier<bool> curveOnVideo = ValueNotifier<bool>(false);

  /// One shared "My" slot (`null` = nothing saved yet).
  final ValueNotifier<EqCurve?> mySlot = ValueNotifier<EqCurve?>(null);

  /// The preset Auto EQ applied at the last load — the indicator dot's
  /// content (`null` = Auto stayed silent).
  final ValueNotifier<String?> autoPick = ValueNotifier<String?>(null);

  /// The playing file's real display ratio: what `Auto` and window snap use.
  final ValueNotifier<double?> fileAspect = ValueNotifier<double?>(null);

  /// Whether what is on screen right now is a hover preview that will
  /// revert. The panel answers with a quieter knob — never a second label.
  final ValueNotifier<bool> previewing = ValueNotifier<bool>(false);

  // ── The four lines ─────────────────────────────────────────────────────

  Continuum? _eqAudioLine;
  Continuum? _eqVideoLine;

  Continuum get eqLine => fileKind.value == TuneFileKind.audio
      ? (_eqAudioLine ??=
          TunePresets.audioContinuum(TuneFileKind.audio))
      : (_eqVideoLine ??= TunePresets.audioContinuum(TuneFileKind.video));

  late final Continuum pictureLine = TunePresets.pictureContinuum();
  late final Continuum aspectLine = TunePresets.aspectContinuum();
  late final Continuum speedLine = TunePresets.speedContinuum();

  Continuum lineFor(TunePart part) {
    switch (part) {
      case TunePart.eq:
        return eqLine;
      case TunePart.picture:
        return pictureLine;
      case TunePart.aspect:
        return aspectLine;
      case TunePart.speed:
        return speedLine;
    }
  }

  double knobFor(TunePart part) {
    switch (part) {
      case TunePart.eq:
        return eqKnob.value;
      case TunePart.picture:
        return pictureKnob.value;
      case TunePart.aspect:
        return aspectKnob.value;
      case TunePart.speed:
        return speedKnob.value;
    }
  }

  String? stopFor(TunePart part) {
    switch (part) {
      case TunePart.eq:
        return eqStop.value;
      case TunePart.picture:
        return pictureStop.value;
      case TunePart.aspect:
        return aspectStop.value;
      case TunePart.speed:
        return speedStop.value;
    }
  }

  /// The greyed parts of the panel: the video ones on an audio-only file
  /// (§12), everything on live media.
  bool partActive(TunePart part) =>
      available.value && (part == TunePart.eq || videoPartsActive.value);

  /// The floating label's text (§3): the stop's name, an exact custom value,
  /// a blend pair, or `Custom`.
  String labelFor(TunePart part) {
    final Continuum line = lineFor(part);
    final double t = knobFor(part);
    final ContinuumStop? on = line.stopAtPosition(t);
    if (on != null) return on.label;
    switch (part) {
      case TunePart.aspect:
        return formatAspectValue(aspectRatio.value);
      case TunePart.speed:
        return formatSpeedValue(speed.value);
      case TunePart.eq:
      case TunePart.picture:
        final bool custom =
            part == TunePart.eq ? eqCustom.value : pictureCustom.value;
        if (custom) return 'Custom';
        final ContinuumSpan span = line.spanOf(t);
        return formatBlendPair(
          line.stopAt(span.a).label,
          line.stopAt(span.b).label,
        );
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  bool _loaded = false;
  bool _watching = false;
  AutoEqFacts? _facts;

  /// Reads the persisted panel and the learning map. Safe before the engine
  /// exists: nothing is written out until a value changes or a file lands.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    TuneState state = TuneState.initial;
    String? rawMemory;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      state = TuneState.decode(prefs.getString(stateKey));
      rawMemory = prefs.getString(memoryKey);
    } catch (_) {
      // No prefs (tests, first run, a broken store) — the defaults stand.
    }
    memory.restore(EqMemory.decode(rawMemory).snapshot());
    memory.pruneStale(); // §5: 90+ days unused = gone at app start
    applyState(state, persist: false, push: false);
  }

  /// Starts mirroring the player — once, right after [engine] is set.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    PlayerService.instance.currentPath.addListener(_onMediaChanged);
    QueueService.instance.items.addListener(_onMediaChanged);
    SettingsService.instance.autoEq.addListener(_onAutoEqChanged);
    _onMediaChanged();
  }

  void _onMediaChanged() => unawaited(onMediaLanded());

  void _onAutoEqChanged() {
    // "Turning the switch off leaves the current settings exactly as they
    // are" — so only the indicator goes away; nothing else moves.
    if (!SettingsService.instance.autoEq.value) autoPick.value = null;
  }

  /// A file landed: re-lay the line for its kind, keep the curve, read the
  /// facts, let Auto EQ speak, and hand every value to the engine.
  Future<void> onMediaLanded() async {
    final String? path = PlayerService.instance.currentPath.value;
    final bool local = path != null &&
        !path.contains('://') &&
        !QueueService.instance.isChannelList;
    available.value = local;
    if (!local) {
      // Live channels and URLs: the panel stays visible and inert (§12) and
      // SALU writes nothing to a stream.
      return;
    }
    fileKind.value =
        MediaUtils.isAudio(path) ? TuneFileKind.audio : TuneFileKind.video;
    videoPartsActive.value = !MediaUtils.isAudio(path);
    // A fresh file rebuilds mpv's chains, so whatever the engine believes is
    // installed no longer is.
    engine.forgetInstalledFilter();
    resyncEqFromCurve(); // §1.6 — the curve is kept, the knob may find a stop
    applyAll();
    await _readFacts(path);
    if (SettingsService.instance.autoEq.value) await _autoPick();
    snapWindowToFit(force: true);
  }

  Future<void> _readFacts(String path) async {
    final bool audioOnly = MediaUtils.isAudio(path);
    double? aspect;
    if (!audioOnly) {
      for (int i = 0; i < _aspectTries; i++) {
        aspect = await engine.readFileAspect();
        if (aspect != null) break;
        await Future<void>.delayed(_aspectGap);
      }
      fileAspect.value = aspect;
    }
    final int? channels = await engine.readAudioChannels();
    String? genre;
    if (audioOnly) genre = await engine.readGenre();
    _facts = AutoEqFacts(
      kind: fileKind.value,
      fileName: MediaUtils.displayName(path),
      genre: genre,
      duration: PlayerService.instance.duration.value,
      channelCount: channels,
    );
  }

  Future<void> _autoPick() async {
    final AutoEqFacts? facts = _facts;
    if (facts == null) return;
    final String? kept = memory.presetFor(AutoEq.memoryKey(facts));
    AutoEqPick pick = kept == null
        ? AutoEq.pick(facts)
        : AutoEqPick(kept, AutoEqRule.genreTag);
    // A name this line does not have (an audio preset on a video file, a
    // stale map entry) is no pick at all.
    EqPreset? preset = TunePresets.presetByKey(pick.presetKey, facts.kind);
    if (preset == null) {
      pick = const AutoEqPick('flat', AutoEqRule.none);
      preset = TunePresets.presetByKey(pick.presetKey, facts.kind);
    }
    if (preset == null) return;
    // The slide into the new curve is the panel's animation (§1.11); here
    // the values simply become the preset.
    eq.value = preset.curve;
    eqCustom.value = false;
    eqStop.value = preset.key;
    eqKnob.value = eqLine.positionOf(eqLine.indexOfKey(preset.key));
    autoPick.value = preset.key;
    unawaited(_writeEqNow(force: true));
    _persist();
  }

  // ── The knobs ──────────────────────────────────────────────────────────

  /// Moves a knob. `commit: false` is a live drag or a hover preview: the
  /// engine follows, nothing is kept until the release.
  void setKnob(TunePart part, double t, {bool commit = true}) {
    final Continuum line = lineFor(part);
    if (line.isEmpty) return;
    final double raw = clampRange(t, 0, 1);
    final double position = commit ? line.snap(raw) : raw;
    final ContinuumStop? stop = line.stopAtPosition(position);
    switch (part) {
      case TunePart.eq:
        eqKnob.value = position;
        eqStop.value = stop?.key;
        eqCustom.value = false;
        final List<double>? v = line.vectorAt(position);
        if (v != null) eq.value = EqCurve(v).quantized();
        _pushEq(commit: commit);
      case TunePart.picture:
        pictureKnob.value = position;
        pictureStop.value = stop?.key;
        pictureCustom.value = false;
        final List<double>? v = line.vectorAt(position);
        if (v != null) picture.value = PictureValues.fromVector(v);
        _engineWrite(() => engine.setPicture(picture.value));
      case TunePart.aspect:
        aspectKnob.value = position;
        aspectStop.value = stop?.key;
        aspectRatio.value =
            stop?.key == 'auto' ? 0 : (line.valueAt(position) ?? 0);
        _engineWrite(() => engine.setAspectOverride(aspectRatio.value));
        if (commit) snapWindowToFit();
      case TunePart.speed:
        speedKnob.value = position;
        final double v = line.valueOnLine(position);
        speed.value = v.isFinite && v > 0 ? v : 1;
        speedStop.value = TunePresets.speedStopForValue(speed.value)?.key;
        _engineWrite(
            () => engine.setSpeed(speed.value, keepPitch: keepPitch.value));
    }
    if (commit) _kept(part);
  }

  /// A click on a named stop — the whole point of the line.
  void selectStop(TunePart part, String key) {
    final Continuum line = lineFor(part);
    final int i = line.indexOfKey(key);
    if (i < 0) return;
    setKnob(part, line.positionOf(i), commit: true);
  }

  /// The keyboard tier: step to the previous / next named stop. From between
  /// two stops the line moves to the stop it is heading towards, so the keys
  /// never feel stuck (Ctrl+↑/↓ — eq_imp.md §6).
  String? nudgeStop(TunePart part, int delta) {
    if (delta == 0) return null;
    final Continuum line = lineFor(part);
    if (line.length < 2) return null;
    final double t = knobFor(part);
    final ContinuumStop? on = line.stopAtPosition(t);
    int index;
    if (on != null) {
      index = line.indexOfKey(on.key);
    } else if (delta > 0) {
      index = -1;
      for (int i = 0; i < line.length; i++) {
        if (line.positionOf(i) <= t + 1e-9) index = i;
      }
      if (index < 0) index = 0;
    } else {
      index = line.length - 1;
      for (int i = line.length - 1; i >= 0; i--) {
        if (line.positionOf(i) >= t - 1e-9) index = i;
      }
    }
    final int next = (index + delta).clamp(0, line.length - 1).toInt();
    if (next == index) return null;
    final String key = line.stopAt(next).key;
    selectStop(part, key);
    return key;
  }

  /// The part's short word — for the deck card and anywhere the part is
  /// named without the panel's own title beside it.
  String partName(TunePart part) => switch (part) {
        TunePart.eq => 'Audio',
        TunePart.picture => 'Picture',
        TunePart.aspect => 'Aspect',
        TunePart.speed => 'Speed',
      };

  /// Which of the four lines the silent keyboard tier drives (eq_imp.md §6's
  /// "one part at a time"). It follows the pointer inside the panel — the
  /// line you are looking at is the line the arrows mean — and Ctrl+Alt+↑/↓
  /// walks it when the pointer is elsewhere. Nothing on screen explains this;
  /// the deck card names the part after the first press.
  final ValueNotifier<TunePart> focusedPart =
      ValueNotifier<TunePart>(TunePart.eq);

  void focusPart(TunePart part) {
    if (focusedPart.value != part) focusedPart.value = part;
  }

  /// Walks the keyboard focus over the four lines (down the panel's order).
  TunePart moveFocus(int delta) {
    const List<TunePart> all = TunePart.values;
    final int n = all.length;
    final int at = ((all.indexOf(focusedPart.value) + delta) % n + n) % n;
    focusedPart.value = all[at];
    return all[at];
  }

  /// The keyboard tier's one call: step the focused line, unless that part is
  /// greyed right now (live media, or a video part on an audio file) — then
  /// the keys answer nothing at all, exactly like the line.
  String? nudgeFocused(int delta) {
    final TunePart part = focusedPart.value;
    if (!partActive(part)) return null;
    return nudgeStop(part, delta);
  }

  // ── The fine sliders ───────────────────────────────────────────────────

  /// One band gain — the 10 sliders below the audio line. Dragging a slider
  /// leaves the line: the knob parks on the nearest stop and the label reads
  /// `Custom`.
  void setBandGain(int index, double db, {bool commit = true}) {
    // The grid is the service's, not the widget's: halves only, ±12 dB, so a
    // preset stays exactly matchable and the label never lies.
    eq.value = eq.value.withBand(index, (db * 2).roundToDouble() / 2);
    eqCustom.value = true;
    eqStop.value = null;
    final Continuum line = eqLine;
    eqKnob.value = line.positionOf(line.nearestStop(eqKnob.value));
    _pushEq(commit: commit);
    if (commit) _kept(TunePart.eq);
  }

  /// Every band back to 0 — which is `Flat`, so the filter leaves the audio
  /// chain entirely (§2).
  void resetBands() {
    eq.value = const EqCurve.flat();
    final Continuum line = eqLine;
    final int i = line.indexOfKey('flat');
    eqStop.value = i >= 0 ? 'flat' : null;
    eqCustom.value = false;
    if (i >= 0) eqKnob.value = line.positionOf(i);
    _pushEq(commit: true);
    _kept(TunePart.eq);
  }

  /// One of the 5 picture values (Saturation · Gamma · Contrast ·
  /// Brightness · Hue).
  void setPictureValue(int index, double v, {bool commit = true}) {
    picture.value = picture.value.withValue(index, v);
    pictureCustom.value = true;
    pictureStop.value = null;
    final Continuum line = pictureLine;
    pictureKnob.value = line.positionOf(line.nearestStop(pictureKnob.value));
    _engineWrite(() => engine.setPicture(picture.value));
    if (commit) _kept(TunePart.picture);
  }

  // ── My · toggles · reset ───────────────────────────────────────────────

  /// Stores the current 10-band setup as "My" (§1.5).
  void saveMy() {
    mySlot.value = eq.value;
    _persist();
  }

  bool get hasMy => mySlot.value != null;

  void applyMy() {
    final EqCurve? curve = mySlot.value;
    if (curve == null) return;
    eq.value = curve;
    eqCustom.value = true;
    eqStop.value = null;
    final Continuum line = eqLine;
    eqKnob.value = line.positionOf(line.nearestStop(eqKnob.value));
    autoPick.value = null;
    _pushEq(commit: true);
    _kept(TunePart.eq);
  }

  void setKeepPitch(bool on) {
    keepPitch.value = on;
    _engineWrite(() => engine.setSpeed(speed.value, keepPitch: on));
    _persist();
  }

  void setSnapWindow(bool on) {
    snapWindow.value = on;
    snapWindowToFit(force: true);
    _persist();
  }

  void setCurveOnVideo(bool on) {
    curveOnVideo.value = on;
    _persist();
  }

  /// The footer's reset-all mark: the media untouched again. The "My" slot
  /// survives — it is a saved thing, not a setting.
  void resetAll() {
    applyState(
      TuneState(
        kind: fileKind.value,
        eqGains: TuneState.initial.eqGains,
        eqKnob: 0,
        eqStop: 'flat',
        picture: PictureValues.original,
        pictureKnob: 0,
        pictureStop: 'original',
        aspectKnob: 0,
        aspectStop: 'auto',
        speed: 1,
        speedKnob: TuneState.initial.speedKnob,
        speedStop: 'x1',
        keepPitch: true,
        snapWindow: false,
        curveOnVideo: false,
        my: mySlot.value?.gains,
      ),
      persist: true,
      push: true,
    );
    snapWindowToFit(force: true);
  }

  // ── Hover preview (§8) ─────────────────────────────────────────────────

  TuneState? _hoverSnapshot;
  bool _gestureDown = false;

  /// The pointer has rested on a control: everything written from here is a
  /// preview, until a click keeps it or the pointer leaves.
  void beginPreview() {
    if (_hoverSnapshot != null) return;
    _hoverSnapshot = capture();
    previewing.value = true;
  }

  /// The pointer left: the preview goes away and nothing was saved.
  void endPreview() {
    final TuneState? snapshot = _hoverSnapshot;
    _hoverSnapshot = null;
    previewing.value = false;
    if (snapshot == null || _gestureDown) return;
    applyState(snapshot, persist: false, push: true);
  }

  /// A press inside the panel makes whatever is showing the truth.
  void beginGesture() {
    _gestureDown = true;
  }

  Future<void> endGesture() async {
    _gestureDown = false;
    _hoverSnapshot = null;
    previewing.value = false;
    _flushEq();
    await persistNow();
    await persistMemory();
  }

  // ── Pushing to the engine ──────────────────────────────────────────────

  /// Every value the viewer changes leaves through here, and greyed-out means
  /// greyed-through: on live media and URLs SALU writes NOTHING to mpv
  /// (eq_imp.md §12's "safe by design"), it only remembers the numbers so the
  /// next local file plays exactly as asked.
  void _engineWrite(Future<void> Function() write) {
    if (!available.value) return;
    unawaited(write());
  }

  /// The whole state to the engine — the load path and the reset mark.
  void applyAll() {
    resyncEqFromCurve();
    unawaited(_writeEqNow(force: true));
    unawaited(engine.setPicture(picture.value));
    unawaited(engine.setAspectOverride(aspectRatio.value));
    unawaited(engine.setSpeed(speed.value, keepPitch: keepPitch.value));
  }

  bool get aspectAuto =>
      aspectRatio.value <= 0.05 || (aspectStop.value ?? 'auto') == 'auto';

  /// The window's shape: the file's own when the line rests on `Auto`.
  double? get snapRatio => aspectAuto
      ? fileAspect.value
      : (aspectRatio.value > 0.05 ? aspectRatio.value : null);

  bool _snapActive = false;
  double _lastFitted = 0;

  /// §1.10 — while snap is on, the window takes the shape in force.
  void snapWindowToFit({bool force = false}) {
    if (!available.value || !snapWindow.value) {
      if (_snapActive) {
        _snapActive = false;
        unawaited(engine.setSnapMode(false));
      }
      return;
    }
    if (!_snapActive) {
      _snapActive = true;
      unawaited(engine.setSnapMode(true));
    }
    final double? ratio = snapRatio;
    if (ratio == null) return;
    if (!force && (ratio - _lastFitted).abs() < 0.004) return;
    _lastFitted = ratio;
    unawaited(engine.fitWindow(ratio));
  }

  /// The EQ write is coalesced while a drag runs, and guaranteed to land on
  /// release.
  Timer? _eqCooldown;
  bool _eqDirty = false;
  String _eqPushed = '';

  void _pushEq({required bool commit}) {
    if (commit) {
      _flushEq();
      return;
    }
    if (_eqCooldown != null) {
      _eqDirty = true;
      return;
    }
    unawaited(_writeEqNow(force: true));
    _eqCooldown = Timer(eqWriteGap, () {
      _eqCooldown = null;
      if (!_eqDirty) return;
      _eqDirty = false;
      unawaited(_writeEqNow(force: true));
    });
  }

  void _flushEq() {
    _eqCooldown?.cancel();
    _eqCooldown = null;
    _eqDirty = false;
    unawaited(_writeEqNow(force: true));
  }

  Future<void> _writeEqNow({bool force = false}) async {
    final EqCurve curve = eq.value;
    final String signature = curve.gains.join(',');
    if (!force && signature == _eqPushed) return;
    _eqPushed = signature;
    if (!available.value) return; // live media — the panel is inert (§12)
    await engine.setEqCurve(curve);
  }

  /// A kept change: remembered on disk, and it teaches the learning map.
  void _kept(TunePart part) {
    _persist();
    if (part == TunePart.eq) _teach();
  }

  /// §5: only a KEPT choice teaches, and in v1 a kept choice is always a
  /// named preset (a custom curve teaches nothing).
  void _teach() {
    final AutoEqFacts? facts = _facts;
    if (facts == null || !available.value) return;
    final String? key = eqStop.value;
    if (key == null || key.isEmpty) return;
    memory.teach(AutoEq.memoryKey(facts), key);
    unawaited(persistMemory());
  }

  /// A curve that IS a preset of the current set parks the knob on that stop
  /// (§1.6); anything else stays `Custom` on its nearest stop.
  void resyncEqFromCurve() {
    final Continuum line = eqLine;
    final EqPreset? match = TunePresets.matchCurve(eq.value, fileKind.value);
    if (match != null) {
      eqStop.value = match.key;
      eqCustom.value = false;
      eqKnob.value = line.positionOf(line.indexOfKey(match.key));
      return;
    }
    if (eq.value.isFlat) {
      final int i = line.indexOfKey('flat');
      eqStop.value = i >= 0 ? 'flat' : null;
      eqCustom.value = false;
      if (i >= 0) eqKnob.value = line.positionOf(i);
      return;
    }
    eqStop.value = null;
    eqCustom.value = true;
  }

  // ── Capture / restore ──────────────────────────────────────────────────

  TuneState capture() => TuneState(
        kind: fileKind.value,
        eqGains: eq.value.gains,
        eqKnob: eqKnob.value,
        eqStop: eqStop.value,
        picture: picture.value,
        pictureKnob: pictureKnob.value,
        pictureStop: pictureStop.value,
        aspectKnob: aspectKnob.value,
        aspectStop: aspectStop.value,
        speed: speed.value,
        speedKnob: speedKnob.value,
        speedStop: speedStop.value,
        keepPitch: keepPitch.value,
        snapWindow: snapWindow.value,
        curveOnVideo: curveOnVideo.value,
        my: mySlot.value?.gains,
      );

  /// Puts a captured state back. The load path, the hover revert and the
  /// reset-all mark all come through here, so they can never disagree.
  void applyState(
    TuneState state, {
    bool persist = true,
    bool push = true,
  }) {
    fileKind.value = state.kind;
    eq.value = EqCurve(state.eqGains);
    eqKnob.value = state.eqKnob;
    eqStop.value = state.eqStop;
    eqCustom.value = state.eqStop == null && !EqCurve(state.eqGains).isFlat;
    picture.value = state.picture;
    pictureKnob.value = state.pictureKnob;
    pictureStop.value = state.pictureStop;
    pictureCustom.value =
        state.pictureStop == null && !state.picture.isNeutral;
    aspectKnob.value = state.aspectKnob;
    aspectStop.value = state.aspectStop;
    // `Auto` has no number of its own; every other position carries one,
    // read from the restored knob so a between-stops ratio survives too.
    aspectRatio.value = (state.aspectStop == 'auto')
        ? 0
        : (aspectLine.valueAt(state.aspectKnob) ?? 0);
    speed.value = state.speed;
    speedKnob.value = state.speedKnob;
    speedStop.value = state.speedStop;
    keepPitch.value = state.keepPitch;
    snapWindow.value = state.snapWindow;
    curveOnVideo.value = state.curveOnVideo;
    mySlot.value = state.myCurve;
    if (push) {
      unawaited(_writeEqNow(force: true));
      unawaited(engine.setPicture(picture.value));
      unawaited(engine.setAspectOverride(aspectRatio.value));
      unawaited(engine.setSpeed(speed.value, keepPitch: keepPitch.value));
      snapWindowToFit(force: true);
    }
    if (persist) _persist();
  }

  // ── Persistence ────────────────────────────────────────────────────────

  Timer? _persistTimer;

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      _persistTimer = null;
      unawaited(persistNow());
    });
  }

  /// Immediate write of the panel state (the close hook calls [flush]).
  Future<void> persistNow() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(stateKey, capture().encode());
    } catch (_) {
      // The in-memory state stays authoritative: a missing prefs store must
      // never be a playback hazard.
    }
  }

  Future<void> persistMemory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (memory.isEmpty) {
        await prefs.remove(memoryKey);
      } else {
        await prefs.setString(memoryKey, memory.encode());
      }
    } catch (_) {
      // Same rule.
    }
  }

  /// Both stores at once — the window-close path, and the tests.
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _flushEq();
    await persistNow();
    await persistMemory();
  }

  // ── Learning map maintenance ───────────────────────────────────────────

  /// Settings → "Clear EQ memory": one tap wipes the map and hands back the
  /// snapshot the Undo toast restores (no confirm dialog, follow.md 3).
  Map<String, EqMemoryEntry> clearMemory() {
    final Map<String, EqMemoryEntry> previous = memory.snapshot();
    memory.clear();
    autoPick.value = null;
    unawaited(persistMemory());
    return previous;
  }

  void restoreMemory(Map<String, EqMemoryEntry> previous) {
    memory.restore(previous);
    unawaited(persistMemory());
  }

  /// The test seam: a known starting point without touching disk.
  void resetForTest() {
    _facts = null;
    available.value = true;
    videoPartsActive.value = true;
    autoPick.value = null;
    fileAspect.value = null;
    _snapActive = false;
    _lastFitted = 0;
    _eqPushed = '';
    _eqDirty = false;
    _eqCooldown?.cancel();
    _eqCooldown = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    _hoverSnapshot = null;
    _gestureDown = false;
    previewing.value = false;
    applyState(TuneState.initial, persist: false, push: false);
  }
}
