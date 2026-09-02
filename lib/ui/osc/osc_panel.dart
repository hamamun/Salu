import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_prefs.dart';
import '../../core/media_utils.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../managers/ui_visibility_manager.dart';
import 'control_buttons.dart';
import 'osc_bar_anchor.dart';
import 'timeline_slider.dart';

/// The IINA-style glass OSC bar (Phase 3 · Step 2).
///
/// A floating, blurred panel that hosts the timeline and control buttons.
/// It auto-hides with the title bar via [UiVisibilityManager], and its
/// position is configurable (Top-Anchored / Floating Bottom / Fixed Bottom)
/// through [AppPrefs.oscLayout].
class OscPanel extends StatefulWidget {
  const OscPanel({
    super.key,
    required this.onPlayPauseFlash,
    required this.onTogglePanel,
    required this.onToggleHud,
    required this.onToggleLibrary,
  });

  final VoidCallback onPlayPauseFlash;
  final VoidCallback onTogglePanel;
  final VoidCallback onToggleHud;
  final VoidCallback onToggleLibrary;

  @override
  State<OscPanel> createState() => _OscPanelState();
}

class _OscPanelState extends State<OscPanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        UiVisibilityManager.instance,
        AppPrefs.instance,
      ]),
      builder: (BuildContext context, Widget? child) {
        final bool visible = UiVisibilityManager.instance.visible;
        final OscLayout layout = AppPrefs.instance.oscLayout;

        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: Align(
              alignment: _alignmentFor(layout),
              child: MouseRegion(
                onEnter: (_) => UiVisibilityManager.instance.lockInteraction(),
                onExit: (_) => UiVisibilityManager.instance.unlockInteraction(),
                child: Container(
                  key: oscBarKey,
                  margin: _marginFor(layout),
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: ClipRRect(
                    borderRadius: _radiusFor(layout),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        color: AppColors.glass,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: _radiusFor(layout),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _TimelineRow(),
                            const SizedBox(height: 2),
                            ControlButtons(
                              onPlayPauseFlash: widget.onPlayPauseFlash,
                              onTogglePanel: widget.onTogglePanel,
                              onToggleHud: widget.onToggleHud,
                              onToggleLibrary: widget.onToggleLibrary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Alignment _alignmentFor(OscLayout layout) {
    switch (layout) {
      case OscLayout.top:
        return Alignment.topCenter;
      case OscLayout.fixed:
        return Alignment.bottomCenter;
      case OscLayout.floating:
        return Alignment.bottomCenter;
    }
  }

  EdgeInsets _marginFor(OscLayout layout) {
    switch (layout) {
      case OscLayout.top:
        return const EdgeInsets.fromLTRB(24, 44, 24, 0);
      case OscLayout.fixed:
        return const EdgeInsets.fromLTRB(18, 0, 18, 0);
      case OscLayout.floating:
        return const EdgeInsets.fromLTRB(24, 0, 24, 18);
    }
  }

  BorderRadius _radiusFor(OscLayout layout) {
    switch (layout) {
      case OscLayout.top:
      case OscLayout.floating:
        return BorderRadius.circular(14);
      case OscLayout.fixed:
        // Flush to the bottom edge — round only the top corners.
        return const BorderRadius.vertical(top: Radius.circular(14));
    }
  }
}

class _TimelineRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        PlayerService.instance.position,
        PlayerService.instance.duration,
      ]),
      builder: (BuildContext context, Widget? child) {
        final PlayerService player = PlayerService.instance;
        return Row(
          children: <Widget>[
            SizedBox(
              width: 52,
              child: Text(
                MediaUtils.formatDuration(player.position.value),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            const Expanded(child: TimelineSlider()),
            SizedBox(
              width: 52,
              child: Text(
                MediaUtils.formatDuration(player.duration.value),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }
}
