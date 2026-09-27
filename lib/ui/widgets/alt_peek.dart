import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import 'glass_capsule.dart';

/// Alt-Peek (shortcut.md §4.2 · Version C) — hold Alt alone for ~200 ms
/// to **arm** the peek; then, wherever the mouse hovers a control, that
/// control's key appears as a **tooltip in SALU's own tooltip look**.
///
/// A peek, never a ladder: the peek only watches the keyboard — it never
/// swallows a key (`Alt+Tab`, `Alt+F4` belong to Windows) and nothing is
/// printed at rest. While the peek is armed, the control's own name
/// tooltip stands down (the pointer is absorbed, so the inner `Tooltip`
/// never wakes) — the key tooltip takes its place. Release Alt and the
/// normal tooltips are back.
///
/// Rule 2 (follow.md) is untouched: nothing is printed at rest; the key
/// exists only while Alt is held **and** the mouse is on the control
/// (owner ruling, shortcut.md §4).
class AltPeek with WidgetsBindingObserver {
  AltPeek._();

  static final AltPeek instance = AltPeek._();

  /// Alt must be held this long, alone, before the peek arms.
  static const Duration holdDelay = Duration(milliseconds: 200);

  static const Duration fadeIn = Duration(milliseconds: 120);
  static const Duration fadeOut = Duration(milliseconds: 100);

  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);

  /// True while the peek is armed (Alt held, alone).
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
        // A mode switch while held (`Alt+W`) fires as usual; the peek
        // stays armed until Alt leaves.
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
  /// an `Alt+Tab`, so the peek must never freeze armed on screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide();
  }

  /// Test hook.
  @visibleForTesting
  void debugSetVisible(bool value) => _visible.value = value;
}

/// The peek's arming joined with the dialog lock — the key shows only
/// while Alt is held AND no modal owns the screen.
final Listenable _peekListenable = Listenable.merge(<Listenable>[
  AltPeek.instance.visible,
  ChromeLock.instance.listenable,
]);

/// The keycap recipe (the Living Map's keycaps and the detail strip's
/// caps): one small glass capsule, radius 6, height 20, the legend in
/// tabular figures. The on-surface reveal is a tooltip, not a chip.
class PeekChip extends StatelessWidget {
  const PeekChip(this.legend, {super.key, this.bright = false});

  final String legend;

  /// Lit (the Living Map's selected keycap).
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

/// Where the key tooltip sits against the control it rides.
enum PeekSide { below, above, overStart }

/// Wraps a visible control; while the peek is armed and the mouse is on
/// the control, the control's key fades in as a tooltip in SALU's own
/// tooltip look (the app's `TooltipTheme` — same surface, border and
/// font as the name tooltips). The tooltip never moves the control (it
/// floats in an unclipped overlay — follow.md rule 5) and its text is
/// never cut off.
///
/// The legend comes from the registry: [anchor] names the visible
/// control ([SaluShortcuts.chipLegend]) — or [entries] name the exact
/// registered keys for a control that is not an anchor (the right-click
/// menu's rows). A control with no registered key shows nothing.
///
/// With [ignoreLock] the tooltip answers even while a modal owns the
/// screen — for rows of the menu that IS the modal (the right-click
/// menu acquires [ChromeLock] while it is open).
class AltPeekAnchor extends StatefulWidget {
  const AltPeekAnchor({
    super.key,
    required this.child,
    this.anchor,
    this.entries,
    this.scope = ShortcutScope.player,
    this.side = PeekSide.above,
    this.ignoreLock = false,
  });

  /// The visible control the keys ride, when it has one.
  final ShortcutAnchor? anchor;

  /// The exact registered keys, when the control is not an anchor.
  final List<ShortcutEntry>? entries;

  final ShortcutScope scope;
  final PeekSide side;
  final bool ignoreLock;
  final Widget child;

  @override
  State<AltPeekAnchor> createState() => _AltPeekAnchorState();
}

class _AltPeekAnchorState extends State<AltPeekAnchor> {
  bool _hovering = false;

  static String _fold(ShortcutEntry e) =>
      e.legend ?? e.combos.map((ShortcutCombo c) => c.label).join(' · ');

  String get _legend {
    final ShortcutAnchor? anchor = widget.anchor;
    if (anchor != null) {
      return SaluShortcuts.chipLegend(widget.scope, anchor) ?? '';
    }
    final List<ShortcutEntry>? entries = widget.entries;
    if (entries == null || entries.isEmpty) return '';
    return entries.map(_fold).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final String legend = _legend;
    if (legend.isEmpty) return widget.child;

    return ListenableBuilder(
      listenable: _peekListenable,
      builder: (BuildContext context, Widget? _) {
        final bool armed = AltPeek.instance.visible.value;
        final bool locked = ChromeLock.instance.isLocked;
        final bool show =
            armed && _hovering && (widget.ignoreLock || !locked);
        // Opaque: hover is geometric, so the region stays on the hit
        // path even while AbsorbPointer holds the child — otherwise
        // arming would fire a phantom exit and the tooltip could never
        // appear.
        return MouseRegion(
          opaque: true,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Stack(
            clipBehavior: Clip.none,
            // The control keeps exactly the constraints it had without
            // the anchor — wrapping must never re-lay it out.
            fit: StackFit.passthrough,
            children: <Widget>[
              // Armed AND hovered, the control's own name tooltip stands
              // down: the pointer is absorbed, so the inner Tooltip
              // never wakes and the key tooltip takes its place. Keys
              // still reach the focused field — only the pointer is
              // held — and every other control stays interactive.
              AbsorbPointer(
                absorbing: armed && _hovering,
                child: widget.child,
              ),
              _positioned(
                IgnorePointer(
                  child: ExcludeFocus(
                    child: _PeekFade(
                      show: show,
                      child: _PeekTip(legend),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The tooltip floats in a 200-px zone centred on the control, so even
  /// the longest legend (`Ctrl+Shift+O`) sits whole over a small mark.
  Widget _positioned(Widget tip) {
    switch (widget.side) {
      case PeekSide.below:
        return Positioned(
          left: -100,
          right: -100,
          top: 26,
          child: Center(child: tip),
        );
      case PeekSide.above:
        return Positioned(
          left: -100,
          right: -100,
          bottom: 26,
          child: Center(child: tip),
        );
      case PeekSide.overStart:
        // The timeline: above the bar, hugging its left end.
        return Positioned(
          left: 0,
          bottom: 26,
          child: Align(alignment: Alignment.centerLeft, child: tip),
        );
    }
  }
}

/// The key tooltip — the app's own `TooltipTheme` (decoration + font),
/// the legend in tabular figures. Sized to its text: the key is never
/// clipped or ellipsised.
class _PeekTip extends StatelessWidget {
  const _PeekTip(this.legend);

  final String legend;

  @override
  Widget build(BuildContext context) {
    final TooltipThemeData tt = TooltipTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: tt.decoration ??
          const BoxDecoration(
            color: AppColors.surfaceHighlight,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
      child: Text(
        legend,
        maxLines: 1,
        softWrap: false,
        style: (tt.textStyle ??
                const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ))
            .merge(
              const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
      ),
    );
  }
}

/// Fade in 120 ms, fade out 100 ms (§4.2 · timing). At rest nothing is
/// built at all — the tooltip exists only while the peek does.
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
