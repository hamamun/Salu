import 'package:flutter/material.dart';

/// Global trigger for the big center-screen play/pause flash.
///
/// The widget itself ([CenterPlayPause]) listens to this controller; any
/// code that toggles play/pause calls [flash] so a large, thin icon expands
/// and fades out in the dead center of the screen (Phase 3 · Step 5).
class CenterPlayPauseController extends ChangeNotifier {
  CenterPlayPauseController._();

  static final CenterPlayPauseController instance = CenterPlayPauseController._();

  IconData _icon = Icons.play_arrow_rounded;
  int _nonce = 0;

  IconData get icon => _icon;

  /// Incremented every time a flash is requested, so the widget re-animates.
  int get nonce => _nonce;

  /// Show [icon] (typically play/pause) expanding and fading out.
  void flash(IconData icon) {
    _icon = icon;
    _nonce++;
    notifyListeners();
  }
}

/// The center-screen play/pause animation overlay.
class CenterPlayPause extends StatefulWidget {
  const CenterPlayPause({super.key});

  @override
  State<CenterPlayPause> createState() => _CenterPlayPauseState();
}

class _CenterPlayPauseState extends State<CenterPlayPause>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  IconData _icon = Icons.play_arrow_rounded;

  @override
  void initState() {
    super.initState();
    CenterPlayPauseController.instance.addListener(_onFlash);
  }

  @override
  void dispose() {
    CenterPlayPauseController.instance.removeListener(_onFlash);
    _controller.dispose();
    super.dispose();
  }

  void _onFlash() {
    if (!mounted) return;
    _icon = CenterPlayPauseController.instance.icon;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = _controller.value;
          if (t <= 0) return const SizedBox.shrink();
          final double opacity = (1.0 - t).clamp(0.0, 1.0).toDouble() * 0.95;
          final double scale = 0.7 + 0.3 * Curves.easeOutCubic.transform(t);
          return Center(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(89),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 72, color: Colors.white),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
