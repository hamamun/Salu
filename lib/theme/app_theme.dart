import 'package:flutter/material.dart';

extension SaluPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.saluDefault;
}

/// Surface-only tint adjustment. 0 preserves each existing alpha exactly;
/// higher percentages remove that fraction of the original opacity, NOT
/// opacity points. Foregrounds, strokes and the video canvas never use this.
class OverlayAppearance extends ThemeExtension<OverlayAppearance> {
  const OverlayAppearance(this.transparency);

  final int transparency;

  Color tint(Color original) => transparency == 0
      ? original // Retain the exact legacy colour/alpha at the default.
      : original.withValues(alpha: original.a * (1 - transparency / 100));

  @override
  OverlayAppearance copyWith({int? transparency}) =>
      OverlayAppearance(transparency ?? this.transparency);

  @override
  OverlayAppearance lerp(covariant OverlayAppearance? other, double t) =>
      OverlayAppearance(other == null
          ? transparency
          : (transparency + (other.transparency - transparency) * t).round());
}

extension SaluSurfaceContext on BuildContext {
  /// Only call for the background tint of a SALU-owned floating surface.
  Color overlayTint(Color original) =>
      (Theme.of(this).extension<OverlayAppearance>() ??
              const OverlayAppearance(0))
          .tint(original);
}

/// Runtime palette values. The original SALU palette remains the default.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.videoBackdrop,
    required this.surface,
    required this.surfaceHighlight,
    required this.glass,
    required this.accent,
    required this.textPrimary,
    required this.iconIdle,
    required this.textSecondary,
    required this.whisper,
    required this.divider,
    required this.surfaceOutline,
    required this.statusAlive,
    required this.statusDead,
    required this.statusUnknown,
    required this.captionButtonHover,
    required this.barTrack,
    required this.barFill,
    required this.barThumb,
    required this.barTick,
    required this.chipBackground,
    required this.threadFill,
    required this.scrimTop,
    required this.scrimBottom,
    required this.shadow,
  });

  final Color background, videoBackdrop, surface, surfaceHighlight, glass;
  final Color accent, textPrimary, iconIdle, textSecondary, whisper;
  final Color divider, surfaceOutline, statusAlive, statusDead, statusUnknown;
  final Color captionButtonHover, barTrack, barFill, barThumb, barTick;
  final Color chipBackground, threadFill, scrimTop, scrimBottom, shadow;

  bool get isLight => background.computeLuminance() > 0.5;

  /// Explicit pairs for custom surfaces that are not Material widgets.
  Color resolve(Color dark, Color light) => isLight ? light : dark;

  @override
  AppPalette copyWith({
    Color? background,
    Color? videoBackdrop,
    Color? surface,
    Color? surfaceHighlight,
    Color? glass,
    Color? accent,
    Color? textPrimary,
    Color? iconIdle,
    Color? textSecondary,
    Color? whisper,
    Color? divider,
    Color? surfaceOutline,
    Color? statusAlive,
    Color? statusDead,
    Color? statusUnknown,
    Color? captionButtonHover,
    Color? barTrack,
    Color? barFill,
    Color? barThumb,
    Color? barTick,
    Color? chipBackground,
    Color? threadFill,
    Color? scrimTop,
    Color? scrimBottom,
    Color? shadow,
  }) =>
      AppPalette(
        background: background ?? this.background,
        videoBackdrop: videoBackdrop ?? this.videoBackdrop,
        surface: surface ?? this.surface,
        surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
        glass: glass ?? this.glass,
        accent: accent ?? this.accent,
        textPrimary: textPrimary ?? this.textPrimary,
        iconIdle: iconIdle ?? this.iconIdle,
        textSecondary: textSecondary ?? this.textSecondary,
        whisper: whisper ?? this.whisper,
        divider: divider ?? this.divider,
        surfaceOutline: surfaceOutline ?? this.surfaceOutline,
        statusAlive: statusAlive ?? this.statusAlive,
        statusDead: statusDead ?? this.statusDead,
        statusUnknown: statusUnknown ?? this.statusUnknown,
        captionButtonHover: captionButtonHover ?? this.captionButtonHover,
        barTrack: barTrack ?? this.barTrack,
        barFill: barFill ?? this.barFill,
        barThumb: barThumb ?? this.barThumb,
        barTick: barTick ?? this.barTick,
        chipBackground: chipBackground ?? this.chipBackground,
        threadFill: threadFill ?? this.threadFill,
        scrimTop: scrimTop ?? this.scrimTop,
        scrimBottom: scrimBottom ?? this.scrimBottom,
        shadow: shadow ?? this.shadow,
      );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      videoBackdrop: Color.lerp(videoBackdrop, other.videoBackdrop, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHighlight: Color.lerp(
        surfaceHighlight,
        other.surfaceHighlight,
        t,
      )!,
      glass: Color.lerp(glass, other.glass, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      iconIdle: Color.lerp(iconIdle, other.iconIdle, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      whisper: Color.lerp(whisper, other.whisper, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      surfaceOutline: Color.lerp(surfaceOutline, other.surfaceOutline, t)!,
      statusAlive: Color.lerp(statusAlive, other.statusAlive, t)!,
      statusDead: Color.lerp(statusDead, other.statusDead, t)!,
      statusUnknown: Color.lerp(statusUnknown, other.statusUnknown, t)!,
      captionButtonHover: Color.lerp(
        captionButtonHover,
        other.captionButtonHover,
        t,
      )!,
      barTrack: Color.lerp(barTrack, other.barTrack, t)!,
      barFill: Color.lerp(barFill, other.barFill, t)!,
      barThumb: Color.lerp(barThumb, other.barThumb, t)!,
      barTick: Color.lerp(barTick, other.barTick, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      threadFill: Color.lerp(threadFill, other.threadFill, t)!,
      scrimTop: Color.lerp(scrimTop, other.scrimTop, t)!,
      scrimBottom: Color.lerp(scrimBottom, other.scrimBottom, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }

  static const AppPalette saluDefault = AppPalette(
    background: Color(0xFF1E1E1E),
    videoBackdrop: Color(0xFF121212),
    surface: Color(0xFF252526),
    surfaceHighlight: Color(0xFF2D2D30),
    glass: Color(0xCC1E1E1E),
    accent: Color(0xFF4C9EEB),
    textPrimary: Color(0xFFEDEDED),
    iconIdle: Color(0xFFA6A6A6),
    textSecondary: Color(0xFF9A9A9A),
    whisper: Color(0x33EDEDED),
    divider: Color(0xFF3A3A3C),
    surfaceOutline: Color(0xFF333336),
    statusAlive: Color(0xFF57C777),
    statusDead: Color(0xFFE05B5B),
    statusUnknown: Color(0xFF5A5A5E),
    captionButtonHover: Color(0x1AFFFFFF),
    barTrack: Color(0xFF35353C),
    barFill: Color(0x80FFFFFF),
    barThumb: Color(0xFFF2F2F2),
    barTick: Color(0x33FFFFFF),
    chipBackground: Color(0xF02C2C31),
    threadFill: Color(0xD9EDEDED),
    scrimTop: Color(0xF0121212),
    scrimBottom: Color(0x00121212),
    shadow: Color(0x80000000),
  );

  static const AppPalette light = AppPalette(
    background: Color(0xFFF4F4F4),
    videoBackdrop: Color(0xFF121212),
    surface: Color(0xFFFFFFFF),
    surfaceHighlight: Color(0xFFE8E8EA),
    glass: Color(0xCCF4F4F4),
    accent: Color(0xFF1769AA),
    textPrimary: Color(0xFF202124),
    iconIdle: Color(0xFF5F6368),
    textSecondary: Color(0xFF5F6368),
    whisper: Color(0x33202124),
    divider: Color(0xFFD5D5D8),
    surfaceOutline: Color(0xFFC9C9CE),
    statusAlive: Color(0xFF218739),
    statusDead: Color(0xFFC62828),
    statusUnknown: Color(0xFF77777A),
    captionButtonHover: Color(0x14000000),
    barTrack: Color(0xFFB8BBC0),
    barFill: Color(0x80666A70),
    barThumb: Color(0xFF25272B),
    barTick: Color(0x33000000),
    chipBackground: Color(0xF0FFFFFF),
    threadFill: Color(0xD9202124),
    scrimTop: Color(0xF0F4F4F4),
    scrimBottom: Color(0x00F4F4F4),
    shadow: Color(0x33000000),
  );
}

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

  /// Resting tone of interactive icon marks (~65% white). Hovering an icon
  /// glides this to [textPrimary] — SALU's icons light up, they are never
  /// boxed by a background shape (see follow.md · interaction recipe).
  static const Color iconIdle = Color(0xFFA6A6A6);

  /// Secondary, de-emphasized text/icons.
  static const Color textSecondary = Color(0xFF9A9A9A);

  /// The owner's signature tone — the About tab's "created by HAM" line,
  /// and nothing else. White at ~20 % over the dark canvas: there if you
  /// look for it, gone if you don't. Deliberately not a UI color.
  static const Color whisper = Color(0x33EDEDED);

  /// Hairline separators.
  static const Color divider = Color(0xFF3A3A3C);

  /// Quiet hairline around floating glass surfaces (pill, modals).
  static const Color surfaceOutline = Color(0xFF333336);

  /// Status dot — the URL's last play attempt succeeded.
  static const Color statusAlive = Color(0xFF57C777);

  /// Status dot — the URL's last play attempt failed.
  static const Color statusDead = Color(0xFFE05B5B);

  /// Status dot — never tried / unknown.
  static const Color statusUnknown = Color(0xFF5A5A5E);

  /// Subtle hover wash for Material interactive surfaces (menus, rows).
  /// The window caption buttons deliberately take NO background shape —
  /// the mark itself lights up (follow.md rule 4).
  static const Color captionButtonHover = Color(0x1AFFFFFF);

  // ── Timeline & volume bars (monochrome — same for video and audio) ────

  /// Unfilled track base of the paste-window-style bars.
  static const Color barTrack = Color(0xFF35353C);

  /// Gentle translucent fill — light enough to read, soft enough to see
  /// the time text sitting inside it.
  static const Color barFill = Color(0x80FFFFFF);

  /// Playhead notch (a flat 2px tick, no glow).
  static const Color barThumb = Color(0xFFF2F2F2);

  /// Faint aiming ticks shown while hovering the timeline.
  static const Color barTick = Color(0x33FFFFFF);

  /// Solid backdrop of the hover time chip (tooltip).
  static const Color chipBackground = Color(0xF02C2C31);

  /// Hairline progress shown at the very bottom of the window when the
  /// chrome auto-hides (display only — never interactive).
  static const Color threadFill = Color(0xD9EDEDED);
}

/// SALU global typography and Material themes.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Segoe UI Variable Display';
  static const List<String> fontFamilyFallback = <String>[
    'Segoe UI Variable Text',
    'Segoe UI Variable',
    'Segoe UI',
  ];

  static ThemeData get dark => darkFor(0);
  static ThemeData get light => lightFor(0);
  static ThemeData darkFor(int transparency) =>
      _build(AppPalette.saluDefault, Brightness.dark, transparency);
  static ThemeData lightFor(int transparency) =>
      _build(AppPalette.light, Brightness.light, transparency);

  static ThemeData _build(AppPalette p, Brightness brightness, int transparency) {
    final OverlayAppearance overlay = OverlayAppearance(transparency);
    final ColorScheme scheme = (brightness == Brightness.dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      surface: p.background,
      primary: p.accent,
      secondary: p.accent,
      onSurface: p.textPrimary,
      onPrimary: brightness == Brightness.dark ? null : Colors.white,
      outline: brightness == Brightness.dark ? null : p.surfaceOutline,
    );
    final TextTheme baseText =
        (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
            .textTheme
            .apply(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
              bodyColor: p.textPrimary,
              displayColor: p.textPrimary,
            );

    return ThemeData(
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[p, overlay],
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: baseText,
      iconTheme: IconThemeData(
        color: p.textPrimary,
        size: 20,
        weight: 300,
        opticalSize: 24,
      ),
      cardTheme: CardThemeData(
        color: overlay.tint(p.surface),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay.tint(p.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlay.tint(p.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: overlay.tint(p.surfaceHighlight),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 12,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.divider,
        thumbColor:
            brightness == Brightness.dark ? Colors.white : p.textPrimary,
        trackHeight: 3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          brightness == Brightness.dark
              ? const Color(0x66FFFFFF)
              : p.textSecondary.withValues(alpha: 0.4),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll<double>(4),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: p.captionButtonHover,
      focusColor: Colors.transparent,
    );
  }
}
