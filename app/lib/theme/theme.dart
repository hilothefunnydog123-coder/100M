import 'package:flutter/material.dart';

import 'colors.dart';

const bodyFont = 'Barlow';

/// Condensed display face for headlines and money.
const numberFont = 'BarlowSemiCondensed';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? JobColors.light : JobColors.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.ink,
        onSecondary: c.canvas,
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.inkMuted,
        outline: c.line,
        outlineVariant: c.line,
        error: c.danger.fg,
      );

  TextStyle t(
    double size,
    FontWeight weight, {
    double height = 1.3,
    String family = bodyFont,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: c.ink,
    letterSpacing: spacing,
  );

  final text = TextTheme(
    displayMedium: t(44, FontWeight.w800, height: 1.02, family: numberFont),
    displaySmall: t(36, FontWeight.w800, height: 1.05, family: numberFont),
    headlineMedium: t(30, FontWeight.w800, height: 1.1, family: numberFont),
    headlineSmall: t(24, FontWeight.w700, height: 1.15, family: numberFont),
    titleLarge: t(20, FontWeight.w700),
    titleMedium: t(17, FontWeight.w700),
    titleSmall: t(15, FontWeight.w700),
    bodyLarge: t(17, FontWeight.w400, height: 1.45),
    bodyMedium: t(15, FontWeight.w400, height: 1.45),
    bodySmall: t(13, FontWeight.w500, height: 1.4).copyWith(color: c.inkMuted),
    labelLarge: t(16, FontWeight.w700),
    labelMedium: t(14, FontWeight.w600),
    labelSmall: t(12, FontWeight.w700, spacing: 0.8),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: c.canvas,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: c.ink,
      titleTextStyle: text.titleMedium,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: shape,
        textStyle: text.labelLarge,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surfaceMuted,
        disabledForegroundColor: c.inkFaint,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: text.labelLarge,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink,
        textStyle: text.labelMedium,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.ink, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: c.inkMuted),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: c.ink),
      hintStyle: text.bodyMedium?.copyWith(color: c.inkFaint),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.ink,
      disabledColor: c.surfaceMuted,
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium?.copyWith(color: c.canvas),
      side: BorderSide(color: c.line, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.canvas),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceMuted,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ink : null,
      ),
      checkColor: WidgetStatePropertyAll(c.canvas),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: c.inkFaint, width: 1.8),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.canvas : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ink : null,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.inkMuted,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    ),
  );
}
