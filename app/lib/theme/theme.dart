import 'package:flutter/material.dart';

import 'colors.dart';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? SpotColors.light : SpotColors.dark;
  final scheme =
      ColorScheme.fromSeed(seedColor: c.brand, brightness: brightness).copyWith(
        primary: c.brand,
        onPrimary: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF04201F),
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.inkMuted,
        outline: c.line,
        outlineVariant: c.line,
      );

  const family = 'Figtree';
  TextStyle t(double size, FontWeight weight, {double height = 1.3}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: c.ink,
        letterSpacing: size >= 24 ? -0.4 : 0,
      );

  final text = TextTheme(
    displaySmall: t(34, FontWeight.w800, height: 1.12),
    headlineMedium: t(28, FontWeight.w800, height: 1.15),
    headlineSmall: t(23, FontWeight.w700, height: 1.2),
    titleLarge: t(20, FontWeight.w700),
    titleMedium: t(17, FontWeight.w700),
    titleSmall: t(15, FontWeight.w700),
    bodyLarge: t(17, FontWeight.w400, height: 1.45),
    bodyMedium: t(15, FontWeight.w400, height: 1.45),
    bodySmall: t(13, FontWeight.w500, height: 1.4).copyWith(color: c.inkMuted),
    labelLarge: t(16, FontWeight.w700),
    labelMedium: t(14, FontWeight.w600),
    labelSmall: t(12, FontWeight.w700).copyWith(letterSpacing: 0.4),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: family,
    textTheme: text,
    scaffoldBackgroundColor: c.canvas,
    splashFactory: InkSparkle.splashFactory,
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
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        textStyle: text.labelLarge,
        backgroundColor: c.brand,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: c.surfaceMuted,
        disabledForegroundColor: c.inkFaint,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: text.labelLarge,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brandInk,
        textStyle: text.labelMedium,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
      hintStyle: text.bodyMedium?.copyWith(color: c.inkFaint),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.surface),
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
      color: c.brand,
      linearTrackColor: c.surfaceMuted,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.brand : null,
      ),
    ),
  );
}
