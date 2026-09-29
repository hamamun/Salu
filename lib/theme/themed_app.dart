import 'package:flutter/material.dart';

import '../core/settings_service.dart';
import 'app_theme.dart';

/// Keeps the Navigator, player and browser alive when appearance changes.
/// MaterialApp listens to platform brightness while System is selected.
class SaluThemedApp extends StatelessWidget {
  const SaluThemedApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SaluThemeMode>(
      valueListenable: SettingsService.instance.themeMode,
      builder: (BuildContext context, SaluThemeMode mode, Widget? child) {
        return ValueListenableBuilder<int>(
          valueListenable: SettingsService.instance.overlayTransparency,
          builder: (BuildContext context, int transparency, Widget? home) =>
              MaterialApp(
                title: 'SALU',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightFor(transparency),
                darkTheme: AppTheme.darkFor(transparency),
                themeMode: switch (mode) {
                  SaluThemeMode.defaultTheme => ThemeMode.dark,
                  SaluThemeMode.light => ThemeMode.light,
                  SaluThemeMode.system => ThemeMode.system,
                },
                home: home,
              ),
          child: child,
        );
      },
      child: home,
    );
  }
}
