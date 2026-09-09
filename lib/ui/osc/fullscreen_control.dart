import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/salu_icon_button.dart';

/// The single viewing control at the far-right edge of the OSC.
///
/// Fullscreen is intentionally a direct, one-click action so this primary
/// action never gains a menu or an extra click.
class FullscreenControl extends StatefulWidget {
  const FullscreenControl({super.key});

  @override
  State<FullscreenControl> createState() => _FullscreenControlState();
}

class _FullscreenControlState extends State<FullscreenControl>
    with WindowListener {
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readWindowState();
  }

  Future<void> _readWindowState() async {
    final bool fullscreen = await windowManager.isFullScreen();
    if (mounted) setState(() => _isFullscreen = fullscreen);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullscreen = false);
  }

  Future<void> _toggle() async {
    await windowManager.setFullScreen(!_isFullscreen);
    // Keep the mark correct even on platforms that do not send a fullscreen
    // listener callback after a programmatic transition.
    await _readWindowState();
  }

  @override
  Widget build(BuildContext context) {
    return SaluIconButton(
      tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
      onTap: _toggle,
      active: _isFullscreen,
      child: Icon(
        _isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        size: 22,
      ),
    );
  }
}
