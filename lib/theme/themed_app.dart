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
        return MaterialApp(
          title: 'SALU',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: switch (mode) {
            SaluThemeMode.defaultTheme => ThemeMode.dark,
            SaluThemeMode.light => ThemeMode.light,
            SaluThemeMode.system => ThemeMode.system,
          },
          home: child,
        );
      },
      child: home,
    );
  }
}
