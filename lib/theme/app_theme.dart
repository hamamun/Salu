import 'package:flutter/material.dart';

/// SALU's central color vocabulary.
///
/// Design rule: deep dark grays (#121212 / #1E1E1E) — never pure black —
/// with thin monochromatic iconography and soft rounded corners everywhere.
class AppColors {
  AppColors._();

  /// The main app canvas — a rich dark gray, NOT pure black.
  static const Color background = Color(0xFF1E1E1E);

  /// A slightly deeper gray used behind video letterboxing.
  static const Color videoBackdrop = Color(0xFF121212);

  /// Raised surfaces (panels, menus, popovers).
  static const Color surface = Color(0xFF252526);

  /// Hovered / highlighted surfaces.
  static const Color surfaceHighlight = Color(0xFF2D2D30);

  /// Semi-transparent glass base for BackdropFilter panels (OSC, sidebars).
  static const Color glass = Color(0xCC1E1E1E);

  /// Accent color foundation. (The user-facing accent picker arrives in
  /// Phase 4 — everything reads the accent from here so it can be swapped.)
  static const Color accent = Color(0xFF4C9EEB);

  /// Primary text/icons.
  static const Color textPrimary = Color(0xFFEDEDED);

  /// Secondary, de-emphasized text/icons.
  static const Color textSecondary = Color(0xFF9A9A9A);

  /// Hairline separators.
  static const Color divider = Color(0xFF3A3A3C);

  /// Windows-native red used when hovering the Close window button.
  static const Color closeButtonHover = Color(0xFFE81123);

  /// Subtle hover wash for the Minimize / Maximize window buttons.
  static const Color captionButtonHover = Color(0x1AFFFFFF);
}

/// SALU global theme — strictly Segoe UI Variable, dark, minimal.
class AppTheme {
  AppTheme._();

  /// Strict typography rule: Segoe UI Variable (Windows 11 system font).
  /// Falls back to classic Segoe UI on Windows 10.
  static const String fontFamily = 'Segoe UI Variable Display';
  static const List<String> fontFamilyFallback = <String>[
    'Segoe UI Variable Text',
    'Segoe UI Variable',
    'Segoe UI',
  ];

  static ThemeData get dark {
    final ColorScheme scheme = const ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.accent,
      secondary: AppColors.accent,
      onSurface: AppColors.textPrimary,
    );

    final TextTheme baseText = ThemeData.dark().textTheme.apply(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: baseText,

      // Thin, modern, monochromatic outline icons.
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 20,
        weight: 300,
        opticalSize: 24,
      ),

      // Smooth rounded corners on all UI elements.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.divider,
        thumbColor: Colors.white,
        trackHeight: 3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x66FFFFFF)),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(4),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: AppColors.captionButtonHover,
      focusColor: Colors.transparent,
    );
  }
}
