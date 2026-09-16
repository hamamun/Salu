import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/window_state_service.dart';
import '../../theme/app_theme.dart';
import '../mini/mini_marks.dart';
import 'dot_grid_icon.dart';

/// SALU's invisible-until-activity title bar.
///
/// Sits on top of the edge-to-edge video. Completely transparent while the
/// window is idle — even when nothing is playing; slides down from the top
/// edge and fades in whenever the mouse moves anywhere over the window or a
/// key is pressed, then auto-hides 3 seconds after the last activity
/// (visibility is driven by the parent via [visible]).
///
/// Contains: a [DragToMoveArea] spanning the full width, the current media
/// title in the center, and the caption row on the right — the 6-dot
/// settings button followed by Windows caption buttons (Minimize /
/// Maximize / Close) rendered with native Segoe Fluent glyphs.
///
/// When [immersive] is true the bar paints no gradient and performs no
/// visibility animation of its own — the parent block (HomeScreen's fused
/// top chrome) owns the shared background and show/hide motion, so the
/// title bar and the controller below always move and fade as one piece.
///
/// The maximize / restore mark reads [WindowStateService.isMaximized] —
/// the one shared window-state memory (bug 2 fix) — and the button routes
/// through [WindowStateService.toggleMaximize], which exits fullscreen
/// through the clean path instead of restoring around it.
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({
    super.key,
    required this.visible,
    this.title,
    this.onSettings,
    this.immersive = false,
  });

  /// Whether the bar is currently shown (parent-driven global hover logic).
  final bool visible;

  /// Title of the playing media; falls back to "SALU".
  final String? title;

  /// Opens the settings window (the 6-dot button, left of Minimize).
  final VoidCallback? onSettings;

  /// When true the bar renders plain content only: no gradient backdrop
  /// and no slide/fade wrapper (the fused parent block drives both).
  final bool immersive;

  /// Fixed height of the caption area.
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final WindowStateService windows = WindowStateService.instance;
    // The bar's own content — gradient scrim applied only when standalone.
    final Widget content = Container(
      height: CustomTitleBar.height,
      decoration: immersive
          ? null
          : const BoxDecoration(
              // Soft scrim so the bar stays readable over bright video,
              // while keeping the borderless edge-to-edge illusion.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xB3121212), Color(0x00121212)],
              ),
            ),
      child: Stack(
        children: <Widget>[
          // Full-width drag area (double-click toggles maximize).
          Positioned.fill(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: windows.toggleMaximize,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Centered media title.
          Center(
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.of(context).size.width - 320)
                      .clamp(0.0, double.infinity)
                      .toDouble(),
                ),
                child: Text(
                  title ?? 'SALU',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          // Caption buttons — right aligned.
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Mini bar mode — one glyph IMMEDIATELY left of Settings
                // (mini.md §4). A wide, thin rounded strip: the bar itself,
                // drawn in the caption family's ink and stroke, naming the
                // action by shape — never by text (tooltips name controls,
                // they never teach shortcuts; follow.md rule 2).
                _CaptionButton(
                  tooltip: 'Mini bar mode',
                  child: const MiniBarMark(
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: windows.toggleMini,
                ),
                // SALU settings — six dots in two lines (left of Minimize).
                _CaptionButton(
                  tooltip: 'Settings',
                  child: const DotGridIcon(
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => onSettings?.call(),
                ),
                _CaptionButton(
                  glyph: '\uE921', // Minimize
                  tooltip: 'Minimize',
                  onPressed: () => windowManager.minimize(),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: windows.isMaximized,
                  builder:
                      (BuildContext context, bool maximized, Widget? _) {
                    return _CaptionButton(
                      glyph: maximized ? '\uE923' : '\uE922',
                      tooltip: maximized ? 'Restore' : 'Maximize',
                      onPressed: windows.toggleMaximize,
                    );
                  },
                ),
                _CaptionButton(
                  glyph: '\uE8BB', // Close
                  tooltip: 'Close',
                  isClose: true,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (immersive) return content;

    return AnimatedSlide(
      // The bar slides down from the top edge as it fades in (like
      // Windows' own auto-hiding caption bars); the off-screen part is
      // clipped by the window, so at rest it is fully invisible.
      offset: visible ? Offset.zero : const Offset(0, -0.5),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: content,
        ),
      ),
    );
  }
}

/// A single caption button (settings mark or Min / Max / Close glyph) drawn
/// with the native Segoe Fluent Icons glyph set for a perfectly
/// Windows-native feel.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.onPressed,
    this.glyph,
    this.child,
    this.isClose = false,
  }) : assert(glyph != null || child != null);

  /// Segoe Fluent glyph to render (or pass [child] for a custom mark).
  final String? glyph;

  /// Custom content — e.g. the 6-dot settings mark — rendered instead of
  /// [glyph] when provided.
  final Widget? child;

  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color background = _hovered
        ? (widget.isClose
            ? AppColors.closeButtonHover
            : AppColors.captionButtonHover)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: CustomTitleBar.height,
          color: background,
          alignment: Alignment.center,
          child: widget.child ??
              Text(
                widget.glyph!,
                style: TextStyle(
                  // Native Windows caption glyphs (Win11), MDL2 on Win10.
                  fontFamily: 'Segoe Fluent Icons',
                  fontFamilyFallback: const <String>['Segoe MDL2 Assets'],
                  fontSize: 10,
                  color: _hovered && widget.isClose
                      ? Colors.white
                      : AppColors.textPrimary,
                ),
              ),
        ),
      ),
    );
  }
}
