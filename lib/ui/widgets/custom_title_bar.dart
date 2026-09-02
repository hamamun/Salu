import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';

/// SALU's invisible-until-hover title bar.
///
/// Sits on top of the edge-to-edge video. Completely transparent while the
/// mouse is idle; fades in gracefully whenever the mouse moves anywhere over
/// the window (visibility is driven by the parent via [visible]).
///
/// Contains: a [DragToMoveArea] spanning the full width, the current media
/// title in the center, and Windows caption buttons (Minimize / Maximize /
/// Close) on the right, rendered with native Segoe Fluent glyphs.
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({
    super.key,
    required this.visible,
    this.title,
  });

  /// Whether the bar is currently shown (parent-driven global hover logic).
  final bool visible;

  /// Title of the playing media; falls back to "SALU".
  final String? title;

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
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Container(
          height: CustomTitleBar.height,
          decoration: const BoxDecoration(
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
                          .clamp(0.0, double.infinity),
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
        ),
      ),
    );
  }
}

/// A single Windows caption button (Min / Max / Close) drawn with the native
/// Segoe Fluent Icons glyph set for a perfectly Windows-native feel.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final String glyph;
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
          child: Text(
            widget.glyph,
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
