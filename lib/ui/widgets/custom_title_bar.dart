import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';
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
class CustomTitleBar extends StatefulWidget {
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
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximizedState() async {
    final bool maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The bar's own content — gradient scrim applied only when standalone.
    final Widget content = Container(
      height: CustomTitleBar.height,
      decoration: widget.immersive
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
                onDoubleTap: _toggleMaximize,
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
                  widget.title ?? 'SALU',
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
                // SALU settings — six dots in two lines (left of Minimize).
                _CaptionButton(
                  tooltip: 'Settings',
                  child: const DotGridIcon(
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => widget.onSettings?.call(),
                ),
                _CaptionButton(
                  glyph: '\uE921', // Minimize
                  tooltip: 'Minimize',
                  onPressed: () => windowManager.minimize(),
                ),
                _CaptionButton(
                  glyph: _isMaximized ? '\uE923' : '\uE922',
                  tooltip: _isMaximized ? 'Restore' : 'Maximize',
                  onPressed: _toggleMaximize,
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

    if (widget.immersive) return content;

    return AnimatedSlide(
      // The bar slides down from the top edge as it fades in (like
      // Windows' own auto-hiding caption bars); the off-screen part is
      // clipped by the window, so at rest it is fully invisible.
      offset: widget.visible ? Offset.zero : const Offset(0, -0.5),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !widget.visible,
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
