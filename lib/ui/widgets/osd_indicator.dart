import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Global trigger for the minimalist top-right OSD indicator.
///
/// Phase 3 · Step 6. Shows a small text/icon for volume, mute, seek, skip
/// etc. and fades out automatically after ~1 second. It must never wake the
/// main OSC bar, so it lives outside the visibility manager.
class OsdController extends ChangeNotifier {
  OsdController._();

  static final OsdController instance = OsdController._();

  static const Duration displayDuration = Duration(seconds: 1);

  String? _text;
  IconData? _icon;
  int _nonce = 0;
  Timer? _timer;

  String? get text => _text;

  IconData? get icon => _icon;

  int get nonce => _nonce;

  void show(String text, {IconData? icon}) {
    _text = text;
    _icon = icon;
    _nonce++;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(displayDuration, () {
      _text = null;
      _icon = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Renders the OSD message pinned to the top-right corner, padded down so it
/// never overlaps the title bar (Phase 3 · Step 6).
class OsdIndicator extends StatelessWidget {
  const OsdIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OsdController.instance,
      builder: (BuildContext context, Widget? child) {
        final OsdController controller = OsdController.instance;
        final String? text = controller.text;
        return AnimatedOpacity(
          opacity: text == null ? 0 : 1,
          duration: const Duration(milliseconds: 160),
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.only(top: 56, right: 20),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (controller.icon != null) ...<Widget>[
                      Icon(controller.icon,
                          size: 18, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      text ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
