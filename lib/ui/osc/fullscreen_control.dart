import 'package:flutter/material.dart';

import '../../core/window_state_service.dart';
import '../widgets/salu_icon_button.dart';

/// The single viewing control at the far-right edge of the OSC.
///
/// Fullscreen is intentionally a direct, one-click action so this primary
/// action never gains a menu or an extra click.
///
/// Reads [WindowStateService.isFullscreen] — the one shared window-state
/// memory (bug 2 fix) — instead of tracking its own copy, so the mark
/// can never disagree with the real window.
class FullscreenControl extends StatelessWidget {
  const FullscreenControl({super.key});

  @override
  Widget build(BuildContext context) {
    final WindowStateService windows = WindowStateService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: windows.isFullscreen,
      builder: (BuildContext context, bool fullscreen, Widget? _) {
        return SaluIconButton(
          tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
          onTap: windows.toggleFullscreen,
          active: fullscreen,
          child: Icon(
            fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            size: 22,
          ),
        );
      },
    );
  }
}
