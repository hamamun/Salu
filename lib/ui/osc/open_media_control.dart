import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/open_media_service.dart';
import '../../core/ui_lock.dart';
import '../widgets/glass_capsule.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import 'open_url_dialog.dart';

/// SALU's Open Media control — the leftmost item of the control row,
/// directly below the timeline (follow.md · §4).
///
/// A thin custom "+" mark. Clicking it rotates the plus 45° into an "×"
/// and blooms a small horizontal frosted-glass pill BELOW the button,
/// floating over the video. The pill is rendered via
/// [OverlayPortal.overlayChildLayoutBuilder] on the root overlay — the
/// container itself never moves or reflows, and the pill tracks the
/// button's on-screen position every layout pass without relying on
/// [CompositedTransformFollower] (which cannot sit above widgets — like
/// [Tooltip] — that build their own overlay children during layout; see
/// follow.md and the Flutter 3.38 RenderFollowerLayer assertion). The
/// pill holds three icon-only marks:
///
///     film frame → Open File…   (native Windows picker, multi-select)
///     stacked frames → Open Folder… (native picker, scan & queue)
///     link → Open URL…          (the SALU glass modal)
///
/// No text rows, no shortcut labels — tooltips on hover-delay only.
/// Esc or a click anywhere outside closes the pill. While the pill is up,
/// [ChromeLock] keeps the top chrome from auto-hiding beneath it.
class OpenMediaControl extends StatefulWidget {
  const OpenMediaControl({super.key});

  @override
  State<OpenMediaControl> createState() => _OpenMediaControlState();
}

class _OpenMediaControlState extends State<OpenMediaControl>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();

  /// Whoever held keyboard focus before the pill opened — restored on
  /// close so Space and the silent shortcuts keep working afterwards.
  FocusNode? _focusBefore;

  /// Set while the pill is open (icon state, tooltip suppression). Goes
  /// false the instant a close is requested — independently of the
  /// overlay child, which lingers ~140 ms longer to play its exit fade.
  bool _open = false;

  /// Removes the overlay child once the reverse fade has finished.
  Timer? _hideTimer;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  );

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_open) ChromeLock.instance.release();
    _anim.dispose();
    super.dispose();
  }

  // ── Pill lifecycle ──────────────────────────────────────────────────

  void _toggle() => _open ? _closePill() : _openPill();

  void _openPill() {
    if (_open) return;
    _hideTimer?.cancel();
    ChromeLock.instance.acquire();
    _focusBefore = FocusManager.instance.primaryFocus;
    setState(() => _open = true);
    _anim.forward();
    _portal.show();
  }

  void _closePill() {
    if (!_open) return;
    setState(() => _open = false);
    _anim.reverse();
    ChromeLock.instance.release();
    _focusBefore?.requestFocus();
    _focusBefore = null;
    // Let the reverse fade play out before tearing the overlay child down.
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) _portal.hide();
    });
  }

  Future<void> _runAction(_OpenAction action) async {
    _closePill();
    switch (action) {
      case _OpenAction.file:
        await OpenMediaService.openFiles();
      case _OpenAction.folder:
        await OpenMediaService.openFolder();
      case _OpenAction.url:
        if (mounted) await showOpenUrlDialog(context);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (BuildContext context, OverlayChildLayoutInfo info) {
        return _PillOverlay(
          childPaintTransform: info.childPaintTransform,
          childSize: info.childSize,
          animation: _anim,
          onDismiss: _closePill,
          onAction: _runAction,
        );
      },
      child: SaluIconButton(
        tooltip: _open ? null : 'Open media',
        size: 36,
        active: _open,
        onTap: _toggle,
        child: RotationTransition(
          // 45° — the plus becomes an × while the pill is showing.
          turns: Tween<double>(begin: 0, end: 0.125).animate(
            CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
          ),
          child: const PlusMark(size: 19),
        ),
      ),
    );
  }
}

enum _OpenAction { file, folder, url }

/// The floating pill: a full-screen dismiss layer + the glass capsule
/// anchored below the plus button.
///
/// Positioned with [childPaintTransform]/[childSize] — the values
/// [OverlayPortal.overlayChildLayoutBuilder] hands us during layout —
/// instead of [CompositedTransformFollower], whose paint transform is
/// only known once compositing runs and therefore can't sit above a
/// [Tooltip] (which builds its own overlay child during layout too).
class _PillOverlay extends StatelessWidget {
  const _PillOverlay({
    required this.childPaintTransform,
    required this.childSize,
    required this.animation,
    required this.onDismiss,
    required this.onAction,
  });

  final Matrix4 childPaintTransform;
  final Size childSize;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final ValueChanged<_OpenAction> onAction;

  @override
  Widget build(BuildContext context) {
    // Mirrors RawAutocomplete's own guard: a zero determinant means the
    // "+" button isn't currently visible/laid out (e.g. mid-transition),
    // so there is nothing sane to anchor the pill to yet.
    if (childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final CurvedAnimation curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Focus(
      // Esc closes (follow.md motion language). The pill briefly owns
      // focus; every other key is left alone.
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: <Widget>[
          // Click-outside-to-close. Opaque: the closing click must never
          // fall through and toggle play/pause on the video underneath.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onSecondaryTap: onDismiss,
            ),
          ),
          // Re-anchors this subtree to the "+" button's on-screen box —
          // (0, 0) here is the button's top-left corner — then drops the
          // pill 6px below it, matching the old bottomLeft→topLeft
          // CompositedTransformFollower anchoring.
          Transform(
            transform: childPaintTransform,
            child: Padding(
              padding: EdgeInsets.only(top: childSize.height + 6),
              child: Align(
                alignment: Alignment.topLeft,
                child: FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                    alignment: Alignment.topLeft,
                    child: _PillBody(onAction: onAction),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({required this.onAction});

  final ValueChanged<_OpenAction> onAction;

  @override
  Widget build(BuildContext context) {
    // The shared glass material (the OSD deck renders the same surface —
    // see GlassCapsule).
    return GlassCapsule(
      radius: 21,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SaluIconButton(
            tooltip: 'Open file',
            size: 36,
            onTap: () => onAction(_OpenAction.file),
            child: const FilmFrameMark(size: 20),
          ),
          const SizedBox(width: 2),
          SaluIconButton(
            tooltip: 'Open folder',
            size: 36,
            onTap: () => onAction(_OpenAction.folder),
            child: const StackedFramesMark(size: 20),
          ),
          const SizedBox(width: 2),
          SaluIconButton(
            tooltip: 'Open URL',
            size: 36,
            onTap: () => onAction(_OpenAction.url),
            child: const LinkMark(size: 20),
          ),
        ],
      ),
    );
  }
}
