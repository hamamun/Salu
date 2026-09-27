import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import 'glass_capsule.dart';

/// Alt-Peek (shortcut.md §4.2 · Version B) — hold Alt alone for ~200 ms and
/// small key chips appear next to the controls currently on screen. A
/// **peek, never a ladder**: it only watches the keyboard, it never
/// swallows a key (`Alt+Tab`, `Alt+F4` belong to Windows) and pressing a
/// chip's letter fires nothing from here — the real shortcuts are
/// unchanged.
///
/// Rule 2 (follow.md) is untouched: nothing is printed at rest; the chips
/// exist only while Alt is held (owner ruling, shortcut.md §4).
class AltPeek with WidgetsBindingObserver {
  AltPeek._();

  static final AltPeek instance = AltPeek._();

  /// Alt must be held this long, alone, before the chips show.
  static const Duration holdDelay = Duration(milliseconds: 200);

  static const Duration fadeIn = Duration(milliseconds: 120);
  static const Duration fadeOut = Duration(milliseconds: 100);

  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);

  /// True while the chips are on screen.
  ValueListenable<bool> get visible => _visible;

  Timer? _timer;
  bool _installed = false;

  /// Set once another key joins the held Alt before the delay — that Alt
  /// press was a chord (`Alt+Tab`, `Alt+W` …), not a peek.
  bool _chorded = false;

  /// Hooks the global keyboard + window focus. Idempotent.
  void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addObserver(this);
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _hide();
  }

  static bool _isAlt(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.alt;

  /// Never returns true — the peek never consumes a key.
  bool _onKey(KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    if (_isAlt(key)) {
      if (event is KeyDownEvent) {
        _chorded = false;
        _timer?.cancel();
        _timer = Timer(holdDelay, () {
          if (!_chorded && HardwareKeyboard.instance.isAltPressed) {
            _visible.value = true;
          }
        });
      } else if (event is KeyUpEvent) {
        _hide();
      }
      return false;
    }
    if (event is KeyDownEvent) {
      if (_visible.value) {
        // A mode switch while held (`Alt+W`) fires as usual and the chips
        // re-render for the new surface — they stay up until Alt leaves.
        return false;
      }
      _chorded = true;
      _timer?.cancel();
    }
    return false;
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _visible.value = false;
  }

  /// Focus loss / window blur: Windows may never deliver the Alt-up after
  /// an `Alt+Tab`, so the peek must never freeze on screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide();
  }

  /// Test hook.
  @visibleForTesting
  void debugSetVisible(bool value) => _visible.value = value;
}

/// The peek's visibility joined with the dialog lock — a chip shows only
/// while Alt is held AND no modal owns the screen.
final Listenable _peekListenable = Listenable.merge(<Listenable>[
  AltPeek.instance.visible,
  ChromeLock.instance.listenable,
]);

/// The chip recipe (§4.2): one small glass capsule — the OSD deck's
/// [GlassCapsule] material, radius 6, height 20 — the key legend in
/// tabular figures, a hairline outline. Never focusable, never hit-tested.
class PeekChip extends StatelessWidget {
  const PeekChip(this.legend, {super.key, this.bright = false});

  final String legend;

  /// Lit (the Living Map's selected chip).
  final bool bright;

  @override
  Widget build(BuildContext context) {
    return GlassCapsule(
      radius: 6,
      height: 20,
      blur: 12,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Center(
        widthFactor: 1,
        child: Text(
          legend,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            height: 1.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: bright ? AppColors.accent : AppColors.textPrimary,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Where a chip sits against the control it rides.
enum PeekSide { below, above, overStart }

/// Wraps a visible control; while Alt-Peek is up, the control's chip fades
/// in beside it. The chip never moves the control (it floats in an
/// unclipped overlay of the control's own box — follow.md rule 5).
///
/// The legend comes from the registry ([SaluShortcuts.chipLegend]) —
/// a control with no registered key shows nothing.
class AltPeekAnchor extends StatelessWidget {
  const AltPeekAnchor({
    super.key,
    required this.anchor,
    required this.child,
    this.scope = ShortcutScope.player,
    this.side = PeekSide.below,
  });

  final ShortcutAnchor anchor;
  final ShortcutScope scope;
  final PeekSide side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? legend = SaluShortcuts.chipLegend(scope, anchor);
    if (legend == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      // The control keeps exactly the constraints it had without the
      // anchor — wrapping must never re-lay it out.
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        _positioned(
          IgnorePointer(
            child: ExcludeFocus(
              child: ListenableBuilder(
                listenable: _peekListenable,
                builder: (BuildContext context, Widget? _) {
                  final bool on = AltPeek.instance.visible.value;
                  // Dialogs over the surface own the screen; the peek
                  // follows visibility, so chips under a barrier stay out.
                  final bool show = on && !ChromeLock.instance.isLocked;
                  return _PeekFade(
                    show: show,
                    child: PeekChip(legend),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _positioned(Widget chip) {
    switch (side) {
      case PeekSide.below:
        return Positioned(
          left: -60,
          right: -60,
          bottom: -24,
          height: 20,
          child: Center(child: chip),
        );
      case PeekSide.above:
        return Positioned(
          left: -60,
          right: -60,
          top: -24,
          height: 20,
          child: Center(child: chip),
        );
      case PeekSide.overStart:
        return Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(child: chip),
        );
    }
  }
}

/// The chrome-hidden cluster (§4.2): holding Alt never wakes the chrome;
/// instead one quiet cluster floats just above the bottom hairline with
/// the surface keys, and leaves when Alt does.
class AltPeekHiddenCluster extends StatelessWidget {
  const AltPeekHiddenCluster({super.key, required this.chromeVisible});

  final bool chromeVisible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 14,
      child: IgnorePointer(
        child: ExcludeFocus(
          child: ListenableBuilder(
            listenable: _peekListenable,
            builder: (BuildContext context, Widget? _) {
              final bool on = AltPeek.instance.visible.value;
              final bool show =
                  on && !chromeVisible && !ChromeLock.instance.isLocked;
              return _PeekFade(
                show: show,
                child: const Center(
                  child: PeekChip(SaluShortcuts.hiddenChromeCluster),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Fade in 120 ms, fade out 100 ms (§4.2 · timing). At rest nothing is
/// built at all — the chip exists only while the peek does.
class _PeekFade extends StatelessWidget {
  const _PeekFade({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AltPeek.fadeIn,
      reverseDuration: AltPeek.fadeOut,
      child: show ? child : const SizedBox.shrink(),
    );
  }
}
