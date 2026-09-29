import 'dart:async';
import 'dart:math' as math;

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
            color:
                bright ? context.palette.accent : context.palette.textPrimary,
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
/// font as the name tooltips). The tooltip **renders in an OverlayPortal**
/// so it floats above all clipping parents (pills, menus, glass capsules)
/// and is never cut off.
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
  /// The tip floats this far off the control's edge (§4.2 — it never
  /// covers the mark and never sits INSIDE it, the old overlap bug).
  static const double _gap = 6;

  /// The tip keeps this much window edge around itself — a legend near
  /// the window border slides inward instead of leaving the window.
  static const double _margin = 4;

  bool _hovering = false;

  /// The tip's overlay child. Shown once, on mount, and kept for the
  /// anchor's life — visibility is decided inside the child (the tip is
  /// an empty box unless the peek is armed AND the mouse is on the
  /// control), so no show/hide juggling ever races a build phase. The
  /// entry lives in the ROOT overlay: no pill, menu or capsule can clip
  /// it, and it paints above every non-overlay surface (the right-click
  /// menu, the chrome) and above earlier entries.
  final OverlayPortalController _portal = OverlayPortalController();

  /// Marks the control's box — the tip reads the box's on-screen rect
  /// from here (the anchor's own context would find a big ancestor box).
  final GlobalKey _childKey = GlobalKey();

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

  bool get _showTip {
    final bool locked = ChromeLock.instance.isLocked;
    return AltPeek.instance.visible.value &&
        _hovering &&
        (widget.ignoreLock || !locked);
  }

  @override
  void initState() {
    super.initState();
    // Only when a legend exists — the portal is built then. (A keyless
    // control builds its plain child and never mounts a portal.) The
    // post-frame show picks up a peek armed before this control existed
    // too (mode switch with Alt held).
    if (_legend.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_portal.isShowing) _portal.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final String legend = _legend;
    if (legend.isEmpty) return widget.child;

    return ListenableBuilder(
      listenable: _peekListenable,
      builder: (BuildContext context, Widget? _) {
        final bool armed = AltPeek.instance.visible.value;
        final bool hovering = _hovering;
        // Armed AND hovered, the control's own name tooltip stands
        // down: the pointer is absorbed, so the inner Tooltip never
        // wakes and the key tooltip takes its place. Keys still reach
        // the focused field — only the pointer is held.
        final bool absorb = armed && hovering;
        return MouseRegion(
          opaque: true,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: OverlayPortal(
            controller: _portal,
            overlayLocation: OverlayChildLocation.rootOverlay,
            overlayChildBuilder: _buildOverlayChild,
            child: AbsorbPointer(
              absorbing: absorb,
              child: KeyedSubtree(key: _childKey, child: widget.child),
            ),
          ),
        );
      },
    );
  }

  /// The tip — built in the root Overlay, so it floats above every
  /// clipping parent (the pill's glass, the right menu's capsule, the
  /// web rows) and is never cut off (follow.md rule 5). The overlay child
  /// arrives with the full window's tight constraints, so the layout
  /// delegate fills the window and places the tip at absolute
  /// coordinates; the fade wrapper stays mounted so the fade-out can
  /// play (while the peek is away it shows nothing).
  Widget _buildOverlayChild(BuildContext context) {
    final BuildContext? targetContext = _childKey.currentContext;
    final RenderObject? ro = targetContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeFocus(
        child: CustomSingleChildLayout(
          delegate: _PeekPositionDelegate(
            target: ro.localToGlobal(Offset.zero) & ro.size,
            side: widget.side,
            gap: _gap,
            margin: _margin,
          ),
          child: _PeekFade(show: _showTip, child: _PeekTip(_legend)),
        ),
      ),
    );
  }
}

/// Lays the key tooltip out against the control's on-screen box — centred
/// above or below it, the timeline's tip hugging its left end — clamped to
/// stay inside the window (flipping to the other side at an edge). The
/// same recipe Flutter's own [Tooltip] uses; running in the root overlay
/// it can never be clipped by the control's ancestors.
class _PeekPositionDelegate extends SingleChildLayoutDelegate {
  const _PeekPositionDelegate({
    required this.target,
    required this.side,
    required this.gap,
    required this.margin,
  });

  /// The control's box in global (== root-overlay) coordinates.
  final Rect target;
  final PeekSide side;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double dx = target.left + (target.width - childSize.width) / 2;
    double dy;
    switch (side) {
      case PeekSide.overStart:
        // The timeline: above the bar, hugging its left end.
        dx = target.left;
        dy = target.top - gap - childSize.height;
      case PeekSide.above:
        dy = target.top - gap - childSize.height;
        if (dy < margin) dy = target.bottom + gap; // flip below at the top edge
      case PeekSide.below:
        dy = target.bottom + gap;
        if (dy + childSize.height > size.height - margin) {
          dy = target.top -
              gap -
              childSize.height; // flip above at the bottom edge
        }
    }
    dx = dx.clamp(
      margin,
      math.max(margin, size.width - childSize.width - margin),
    );
    dy = dy.clamp(
      margin,
      math.max(margin, size.height - childSize.height - margin),
    );
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_PeekPositionDelegate old) =>
      target != old.target ||
      side != old.side ||
      gap != old.gap ||
      margin != old.margin;
}

/// Fade in 120 ms, fade out 100 ms (§4.2 · timing). While the peek is
/// away the tip is not built at all — nothing is on screen (and nothing
/// is findable); the AnimatedSwitcher keeps the outgoing tip mounted just
/// long enough to play the fade-out.
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
          BoxDecoration(
            color: context.palette.surfaceHighlight,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
      child: Text(
        legend,
        maxLines: 1,
        softWrap: false,
        style: (tt.textStyle ??
                TextStyle(color: context.palette.textPrimary, fontSize: 12))
            .merge(
          const TextStyle(
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
