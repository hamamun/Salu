import 'package:flutter/material.dart';

import '../../core/browser_service.dart';
import '../../theme/app_theme.dart';

/// The Player · Web switch (web.md · "a small 'Player · Web' switch at the
/// top-left of the title strip, beside the SALU logo").
///
/// One control for both directions — the same physical slot in the strip in
/// either mode, so the gesture that leaves the browser is exactly where
/// the gesture that entered it was.
class WebModeToggle extends StatelessWidget {
  const WebModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrowserService.instance.mode,
      builder: (BuildContext context, Widget? _) {
        final bool web = BrowserService.instance.isWeb;
        return GestureDetector(
          onTap: BrowserService.instance.toggleFromTitleBar,
          behavior: HitTestBehavior.opaque,
          // A labeled two-state switch, not an icon: both words always
          // stand, and the lit one is the mode the window is in.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Word(label: 'Player', lit: !web),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    '·',
                    style: TextStyle(fontSize: 10.5,
                        color: AppColors.textSecondary),
                  ),
                ),
                _Word(label: 'Web', lit: web),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({required this.label, required this.lit});

  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: lit ? FontWeight.w600 : FontWeight.w500,
        color: lit ? AppColors.textPrimary : AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
      child: Text(label),
    );
  }
}
