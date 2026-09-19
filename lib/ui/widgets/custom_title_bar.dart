import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/window_state_service.dart';
import '../../theme/app_theme.dart';
import '../mini/mini_marks.dart';
import 'dot_grid_icon.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';

/// SALU's invisible-until-activity title bar.
///
/// Sits on top of the edge-to-edge video. Completely transparent while the
/// window is idle — even when nothing is playing; slides down from the top
/// edge and fades in whenever the mouse moves anywhere over the window or a
/// key is pressed, then auto-hides 3 seconds after the last activity
/// (visibility is driven by the parent via [visible]).
///
/// Contains: a [DragToMoveArea] spanning the full width, the SALU mark in
/// the left corner (with the mode switch beside it), the current media
/// title in the center, and the caption row on the right — the 6-dot
/// settings button followed by the Windows caption buttons (Minimize /
/// Maximize / Close) drawn as SALU marks in the family's own thin stroke
/// (follow.md rule 6) — never stock glyphs. Every control in the row
/// rides the shared icon recipe: light + scale on hover, sink on press,
/// and nothing is ever drawn behind it (follow.md rules 2 & 4).
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
    this.leading,
    this.badge,
    this.showMini = true,
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

  /// A widget pinned just RIGHT of the SALU mark at the bar's left corner
  /// — web mode's Player · Web switch lives in this slot (web.md · the
  /// toggle lock: the switch always stands next to the SALU logo, in the
  /// same place in both modes). The centered title is untouched by it.
  final Widget? leading;

  /// A live status mark standing at the caption row's left end, before
  /// the Mini-bar glyph — the download badge's second home. It is the
  /// only signal that can follow a download into Player mode: the
  /// browser stays alive behind the mode switch, so a file keeps landing
  /// while you watch, and this corner is where the news can wait.
  /// Like the caption marks themselves it rides the shared icon recipe
  /// (no hover box — follow.md rule 4).
  final Widget? badge;

  /// false hides the Mini-bar glyph: there is no room for a browser
  /// inside a 32-px strip (mini.md §8), so in web mode that button
  /// simply does not stand on the stage.
  final bool showMini;

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
          // The left corner — the SALU mark ALWAYS stands at the very
          // left (web.md · toggle lock: the mode switch sits NEXT to the
          // SALU logo, same place in both modes), then the mode slot.
          // Drawn above the drag area: the mark never answers the pointer
          // (the drag area behind it moves the window); the controls
          // beside it do.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const _SaluMarkTile(),
                    if (leading != null) ...<Widget>[
                      const SizedBox(width: 10),
                      leading!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Caption buttons — right aligned. Every control in the row is
          // a [SaluIconButton]: the mark lights gray → white and scales
          // 1.06 on hover, sinks 0.90 on press, and NOTHING is drawn
          // behind it (follow.md rules 2 & 4). The marks themselves are
          // drawn in the family's own thin stroke (rule 6).
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The live badge slot (downloads) — leftmost of the row,
                // so the caption buttons themselves never shift.
                if (badge != null) badge!,
                // Mini bar mode — one glyph IMMEDIATELY left of Settings
                // (mini.md §4). A wide, thin rounded strip: the bar
                // itself, naming the action by shape — never by text
                // (tooltips name controls, they never teach shortcuts;
                // follow.md rule 2).
                // Web mode hides it (mini.md §8 — the browser does not fit
                // a 32-px strip), so it never appears to lie.
                if (showMini)
                  SaluIconButton(
                    tooltip: 'Mini bar mode',
                    onTap: windows.toggleMini,
                    hitSize: const Size(46, CustomTitleBar.height),
                    child: const MiniBarMark(size: 18),
                  ),
                // SALU settings — six dots in two lines (left of Minimize).
                SaluIconButton(
                  tooltip: 'Settings',
                  enabled: onSettings != null,
                  onTap: onSettings ?? () {},
                  hitSize: const Size(46, CustomTitleBar.height),
                  child: const DotGridIcon(size: 18),
                ),
                // Minimize — one thin rule.
                SaluIconButton(
                  tooltip: 'Minimize',
                  onTap: () => windowManager.minimize(),
                  hitSize: const Size(46, CustomTitleBar.height),
                  child: const MinimizeMark(size: 18),
                ),
                // Maximize — one thin hollow square; while maximized it
                // reads as the same mark, modified: two squares.
                ValueListenableBuilder<bool>(
                  valueListenable: windows.isMaximized,
                  builder:
                      (BuildContext context, bool maximized, Widget? _) {
                    return SaluIconButton(
                      tooltip: maximized ? 'Restore' : 'Maximize',
                      onTap: windows.toggleMaximize,
                      hitSize: const Size(46, CustomTitleBar.height),
                      child: maximized
                          ? const RestoreMark(size: 18)
                          : const MaximizeMark(size: 18),
                    );
                  },
                ),
                // Close — the family's ×. It lights to full white on
                // hover like every other mark; the red close box is gone.
                SaluIconButton(
                  tooltip: 'Close',
                  onTap: () => windowManager.close(),
                  hitSize: const Size(46, CustomTitleBar.height),
                  child: const CloseMark(size: 18),
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

/// The SALU mark in the bar's left corner (web.md · toggle lock — the
/// Player · Web switch stands next to it in both modes). The app's own
/// tile at 22 px, softly rounded — the mini bar's 19 px tile
/// (mini.md §3) is its cousin in the 32 px strip.
///
/// It is a brand mark, not a control: it never answers the pointer
/// (the drag area behind it still moves the window) and never takes a
/// hover shape.
class _SaluMarkTile extends StatelessWidget {
  const _SaluMarkTile();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.asset(
          'assets/images/salu_logo.png',
          width: 22,
          height: 22,
          filterQuality: FilterQuality.medium,
          // A caption-size decode of the app icon: sharp at any DPI, and
          // nowhere near the cost of the full-size PNG.
          cacheWidth: 64,
          errorBuilder: (BuildContext context, Object error,
              StackTrace? stack) {
            // Never a broken-image glyph — a thin frame in the family's
            // ink.
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.surfaceOutline),
              ),
              child: const SizedBox(width: 22, height: 22),
            );
          },
        ),
      ),
    );
  }
}
