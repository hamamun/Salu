import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/tune/auto_eq.dart';
import '../../core/tune/tune_model.dart';
import '../../core/tune/tune_presets.dart';
import '../../core/tune_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import '../widgets/transport_marks.dart';
import '../widgets/tune_continuum.dart';
import '../widgets/tune_sliders.dart';

/// The Equalizer button's Tune panel (eq_imp.md §1.2) — one surface, four
/// parts, every one of them a labeled continuum with its fine layer below:
///
///   · **Part 1 · Audio Equalizer** — the preset line of the playing file
///     (13 stops on music, 4 on video) + the 10 band sliders, with the My
///     mark, the save mark and the curve-on-video mark under the line.
///   · **Part 2 · Picture** — the looks + the 5 fine bars.
///   · **Part 3 · Aspect** — eight shapes, `Auto` being the file's own, and
///     the Snap window switch ("the window is the screen", §1.10).
///   · **Part 4 · Speed** — seven speeds on a line that runs 0.25×–3.0×
///     linear in value, and the Keep pitch switch.
///
/// Slides down over the video like the Tracks panel, closes on Esc /
/// click-outside, and locks the chrome awake while it is open. Every value is
/// read live from [TuneService], so the panel, the control row and the engine
/// can never disagree — and everything answers while the media plays, with no
/// stop and no restart (rule 5: nothing is ever pushed).
///
/// Grey-out, never hide: live media dims every line (the values stay written
/// but the engine is not touched); an audio-only file dims the video parts.
class TunePanel extends StatefulWidget {
  const TunePanel({super.key});

  /// Panel width — wide enough that 13 stop labels and 10 band sliders read
  /// without crowding (the mock's 520 px).
  static const double width = 520;

  @override
  State<TunePanel> createState() => _TunePanelState();
}

class _TunePanelState extends State<TunePanel>
    with SingleTickerProviderStateMixin {
  final PanelService _panels = PanelService.instance;
  final TuneService _tune = TuneService.instance;

  late final AnimationController _open;
  late final Animation<double> _curve;

  /// Chrome is locked awake for the panel's lifetime — the continua must stay
  /// answerable while the viewer hovers them.
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _curve = CurvedAnimation(
      parent: _open,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _panels.tunePanelOpen.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    _panels.tunePanelOpen.removeListener(_onOpenChanged);
    if (_locked) ChromeLock.instance.release();
    _open.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    final bool open = _panels.tunePanelOpen.value;
    if (open) {
      // One-popup world (follow.md rule 3) — the other panels step aside.
      _panels.closePlaylist();
      _panels.closeTrackPanel();
      ChromeLock.instance.acquire();
      _locked = true;
      _open.forward();
    } else {
      if (_locked) {
        ChromeLock.instance.release();
        _locked = false;
      }
      // Anything still under the cursor stops being a preview.
      _tune.endPreview();
      _open.reverse();
    }
    // §7a: SALU reads no frames while the panel is closed — the numbers are
    // only ever looked at from here.
    _tune.setHistogramActive(open);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _panels.tunePanelOpen,
      builder: (BuildContext context, bool open, Widget? child) {
        return IgnorePointer(
          ignoring: !open,
          child: AnimatedBuilder(
            animation: _curve,
            builder: (BuildContext context, Widget? _) {
              final double v = _curve.value.clamp(0.0, 1.0).toDouble();
              return Stack(
                children: <Widget>[
                  // Click-outside: opaque, so the closing click never falls
                  // through to the video's play/pause layer.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _panels.closeTunePanel,
                      onSecondaryTap: _panels.closeTunePanel,
                    ),
                  ),
                  Positioned(
                    top: kChromeBlockHeight + 6,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: TunePanel.width,
                        child: Opacity(
                          opacity: v,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..translateByDouble(0.0, (1 - v) * -8, 0.0, 1.0)
                              ..scaleByDouble(
                                0.985 + 0.015 * v,
                                0.985 + 0.015 * v,
                                0.985 + 0.015 * v,
                                1.0,
                              ),
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onSecondaryTap: _panels.closeTunePanel,
                              child: _glass(_body()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Glass — the Tracks panel's recipe: blur 18, AppColors.glass, a hairline
  /// ring, radius 11.
  Widget _glass(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.surfaceOutline),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 50,
                offset: Offset(0, 18),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: child,
        ),
      ),
    );
  }

  Widget _body() {
    // The panel lives in the tree the whole time (the slide is an animation,
    // not a mount), so the four lines are only BUILT while it is actually up:
    // a closed panel listens to nothing and paints nothing.
    return ValueListenableBuilder<bool>(
      valueListenable: _panels.tunePanelOpen,
      builder: (BuildContext context, bool open, Widget? _) =>
          open ? _openBody() : const SizedBox.shrink(),
    );
  }

  Widget _openBody() {
    final PlayerService player = PlayerService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _tune.eq,
        _tune.eqKnob,
        _tune.eqStop,
        _tune.eqCustom,
        _tune.picture,
        _tune.pictureKnob,
        _tune.pictureStop,
        _tune.pictureCustom,
        _tune.aspectKnob,
        _tune.aspectStop,
        _tune.aspectRatio,
        _tune.speed,
        _tune.speedKnob,
        _tune.keepPitch,
        _tune.snapWindow,
        _tune.curveOnVideo,
        _tune.mySlot,
        _tune.autoPick,
        _tune.fileKind,
        _tune.available,
        _tune.videoPartsActive,
        _tune.previewing,
        _tune.fileAspect,
        _tune.histogram,
        _tune.focusedPart,
        player.currentPath,
      ]),
      builder: (BuildContext context, Widget? _) {
        return ConstrainedBox(
          // The panel never covers the whole picture: the media stays
          // watchable while it is open, so the body scrolls when the window
          // is short.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height -
                kChromeBlockHeight -
                28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _audioPart(context),
                      const _Hairline(),
                      _picturePart(context),
                      const _Hairline(),
                      _aspectPart(context),
                      const _Hairline(),
                      _speedPart(context),
                      const _Hairline(),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        );
      },
    );
  }

  /// A part wrapped in the keyboard tier's focus: resting the pointer on a
  /// line is what makes it the line Ctrl+↑/↓ means (§6's "one part at a
  /// time"). The part's name coming up white is the whole answer — no legend,
  /// no instruction (follow.md rule 2).
  Widget _focus(TunePart part, Widget child) {
    return MouseRegion(
      onEnter: (_) => _tune.focusPart(part),
      child: child,
    );
  }

  // ── Part 1 · Audio Equalizer ───────────────────────────────────────────

  Widget _audioPart(BuildContext context) {
    final EqCurve curve = _tune.eq.value;
    return _focus(
      TunePart.eq,
      TuneContinuum(
        focused: _tune.focusedPart.value == TunePart.eq,
        title: 'Audio Equalizer',
        titleExtra:
            _tune.autoPick.value == null ? null : _autoDot(_tune.autoPick.value!),
        line: _tune.eqLine,
        position: _tune.eqKnob.value,
        previewing: _tune.previewing.value,
        enabled: _tune.partActive(TunePart.eq),
        label: _tune.labelFor(TunePart.eq),
        onChanged: (double t, bool commit) =>
            _tune.setKnob(TunePart.eq, t, commit: commit),
        onPreviewStart: _tune.beginPreview,
        onPreviewEnd: _tune.endPreview,
        onGestureStart: _tune.beginGesture,
        onGestureEnd: () => unawaited(_tune.endGesture()),
        marks: <Widget>[
          SaluIconButton(
            tooltip: 'My',
            size: 22,
            enabled: _tune.hasMy && _tune.partActive(TunePart.eq),
            onTap: _tune.applyMy,
            child: MyMark(size: 13, filled: _tune.hasMy),
          ),
          SaluIconButton(
            tooltip: 'Save as My',
            size: 22,
            enabled: _tune.partActive(TunePart.eq),
            onTap: _tune.saveMy,
            child: const SaveMark(size: 15),
          ),
          const SizedBox(width: 4),
          // When the curve is Flat the mark dims — there is nothing to draw
          // on the picture (§1.9's own wording).
          SaluIconButton(
            tooltip: 'Curve on the video',
            size: 22,
            active: _tune.curveOnVideo.value,
            enabled: _tune.partActive(TunePart.eq) && !curve.isFlat,
            onTap: () => _tune.setCurveOnVideo(!_tune.curveOnVideo.value),
            child: const CurveMark(size: 15),
          ),
          const SizedBox(width: 8),
          // The one number a curve cannot say out loud: how much the line
          // asks for at its loudest band. Quiet, secondary, never a warning
          // colour, and only when it is worth noticing.
          if (TunePresets.peakGain(curve).abs() >= 6)
            Text(
              'peak ${formatGainDb(TunePresets.peakGain(curve))} dB',
              style: const TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.3,
                color: AppColors.textSecondary,
              ),
            ),
        ],
        below: TuneBands(
          gains: curve.gains,
          enabled: _tune.partActive(TunePart.eq),
          onBand: (int index, double db, bool commit) =>
              _tune.setBandGain(index, db, commit: commit),
          onPreviewStart: _tune.beginPreview,
          onPreviewEnd: _tune.endPreview,
          onGestureStart: _tune.beginGesture,
          onGestureEnd: () => unawaited(_tune.endGesture()),
        ),
      ),
    );
  }

  /// The Auto EQ indicator (§5): a tiny dot beside the audio line's label,
  /// its tooltip naming what Auto chose — one pixel of honesty.
  Widget _autoDot(String choice) {
    return Tooltip(
      message: AutoEq.describe(choice),
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent,
        ),
      ),
    );
  }

  // ── Part 2 · Picture ───────────────────────────────────────────────────

  Widget _picturePart(BuildContext context) {
    final PictureValues values = _tune.picture.value;
    return _focus(
      TunePart.picture,
      TuneContinuum(
        focused: _tune.focusedPart.value == TunePart.picture,
        title: 'Picture',
        line: _tune.pictureLine,
        position: _tune.pictureKnob.value,
        previewing: _tune.previewing.value,
        enabled: _tune.partActive(TunePart.picture),
        label: _tune.labelFor(TunePart.picture),
        onChanged: (double t, bool commit) =>
            _tune.setKnob(TunePart.picture, t, commit: commit),
        onPreviewStart: _tune.beginPreview,
        onPreviewEnd: _tune.endPreview,
        onGestureStart: _tune.beginGesture,
        onGestureEnd: () => unawaited(_tune.endGesture()),
        below: TunePictureBars(
          values: values.vector,
          enabled: _tune.partActive(TunePart.picture),
          histogram: _tune.histogram.value?.shape,
          onValue: (int index, double v, bool commit) =>
              _tune.setPictureValue(index, v, commit: commit),
          onPreviewStart: _tune.beginPreview,
          onPreviewEnd: _tune.endPreview,
          onGestureStart: _tune.beginGesture,
          onGestureEnd: () => unawaited(_tune.endGesture()),
        ),
      ),
    );
  }

  // ── Part 3 · Aspect ────────────────────────────────────────────────────

  Widget _aspectPart(BuildContext context) {
    return _focus(
      TunePart.aspect,
      TuneContinuum(
        focused: _tune.focusedPart.value == TunePart.aspect,
        title: 'Aspect',
        line: _tune.aspectLine,
        position: _tune.aspectKnob.value,
        previewing: _tune.previewing.value,
        enabled: _tune.partActive(TunePart.aspect),
        label: _tune.labelFor(TunePart.aspect),
        onChanged: (double t, bool commit) =>
            _tune.setKnob(TunePart.aspect, t, commit: commit),
        onPreviewStart: _tune.beginPreview,
        onPreviewEnd: _tune.endPreview,
        onGestureStart: _tune.beginGesture,
        onGestureEnd: () => unawaited(_tune.endGesture()),
        trailing: TuneSwitch(
          label: 'Snap window',
          on: _tune.snapWindow.value,
          enabled: _tune.partActive(TunePart.aspect),
          onChanged: (bool on) {
            _tune.focusPart(TunePart.aspect);
            _tune.beginGesture();
            _tune.setSnapWindow(on);
            unawaited(_tune.endGesture());
          },
        ),
      ),
    );
  }

  // ── Part 4 · Speed ─────────────────────────────────────────────────────

  Widget _speedPart(BuildContext context) {
    return _focus(
      TunePart.speed,
      TuneContinuum(
        focused: _tune.focusedPart.value == TunePart.speed,
        title: 'Speed',
        line: _tune.speedLine,
        position: _tune.speedKnob.value,
        previewing: _tune.previewing.value,
        enabled: _tune.partActive(TunePart.speed),
        label: _tune.labelFor(TunePart.speed),
        onChanged: (double t, bool commit) =>
            _tune.setKnob(TunePart.speed, t, commit: commit),
        onPreviewStart: _tune.beginPreview,
        onPreviewEnd: _tune.endPreview,
        onGestureStart: _tune.beginGesture,
        onGestureEnd: () => unawaited(_tune.endGesture()),
        trailing: TuneSwitch(
          label: 'Keep pitch',
          on: _tune.keepPitch.value,
          enabled: _tune.partActive(TunePart.speed),
          onChanged: (bool on) {
            _tune.focusPart(TunePart.speed);
            _tune.beginGesture();
            _tune.setKeepPitch(on);
            unawaited(_tune.endGesture());
          },
        ),
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────

  /// The footer: the reset-all mark, alone on the right (§3's footer).
  ///
  /// **Owner's call, 2026-09-14 — the three scene marks are gone** (Cinema ·
  /// Podcast · Vivid, §7b). The row carries reset and nothing else, which is
  /// what §3's own list named in the first place. `TuneScene` and
  /// [TuneService.applyScene] stay in core, tested, with no UI entry point.
  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 2),
      child: Row(
        children: <Widget>[
          const Spacer(),
          SaluIconButton(
            tooltip: 'Reset all',
            size: 24,
            // Greyed, never hidden — and on live media there is nothing for
            // it to reset, because nothing was ever written (§12).
            enabled: _tune.available.value,
            onTap: () {
              _tune.beginGesture();
              _tune.resetAll();
              unawaited(_tune.endGesture());
            },
            child: const RestartMark(size: 14),
          ),
        ],
      ),
    );
  }
}

/// The panel's part divider — the Tracks panel's hairline, same weight.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.divider,
    );
  }
}
