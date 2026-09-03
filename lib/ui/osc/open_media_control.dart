import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/open_media_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import 'open_url_dialog.dart';

/// SALU's Open Media control — the leftmost item of the control row,
/// directly below the timeline (follow.md · §4).
///
/// A thin custom "+" mark. Clicking it rotates the plus 45° into an "×"
/// and blooms a small horizontal frosted-glass pill BELOW the button,
/// floating over the video (an [OverlayEntry] — the container itself
/// never moves or reflows). The pill holds three icon-only marks:
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
  final LayerLink _link = LayerLink();
  OverlayEntry? _pill;

  /// Whoever held keyboard focus before the pill opened — restored on
  /// close so Space and the silent shortcuts keep working afterwards.
  FocusNode? _focusBefore;

  /// Entries whose reverse fade is still playing (removed ~140 ms after
  /// close). Tracked so dispose can tear them down instantly — otherwise
  /// a pending removal could rebuild against a disposed controller.
  final Set<OverlayEntry> _retiring = <OverlayEntry>{};

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  );

  bool get _open => _pill != null;

  @override
  void dispose() {
    _removePill(instant: true);
    // Tear down any entry still playing its exit fade — it must not
    // outlive the animation controller it is built on.
    for (final OverlayEntry entry in _retiring) {
      entry.remove();
    }
    _retiring.clear();
    _anim.dispose();
    super.dispose();
  }

  // ── Pill lifecycle ──────────────────────────────────────────────────

  void _toggle() => _open ? _closePill() : _openPill();

  void _openPill() {
    if (_open) return;
    ChromeLock.instance.acquire();
    _focusBefore = FocusManager.instance.primaryFocus;
    _anim.forward();
    _pill = OverlayEntry(
      builder: (BuildContext context) => _PillOverlay(
        link: _link,
        animation: _anim,
        onDismiss: _closePill,
        onAction: _runAction,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_pill!);
    setState(() {});
  }

  void _closePill() {
    if (!_open) return;
    _anim.reverse();
    _removePill();
    _focusBefore?.requestFocus();
    _focusBefore = null;
    setState(() {});
  }

  void _removePill({bool instant = false}) {
    final OverlayEntry? pill = _pill;
    if (pill == null) return;
    _pill = null;
    ChromeLock.instance.release();
    if (instant) {
      pill.remove();
      return;
    }
    // Let the reverse fade play out before tearing the entry down.
    _retiring.add(pill);
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (_retiring.remove(pill)) pill.remove();
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
    return CompositedTransformTarget(
      link: _link,
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
class _PillOverlay extends StatelessWidget {
  const _PillOverlay({
    required this.link,
    required this.animation,
    required this.onDismiss,
    required this.onAction,
  });

  final LayerLink link;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final ValueChanged<_OpenAction> onAction;

  @override
  Widget build(BuildContext context) {
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
          CompositedTransformFollower(
            link: link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                alignment: Alignment.topLeft,
                child: _PillBody(onAction: onAction),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
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
        ),
      ),
    );
  }
}
