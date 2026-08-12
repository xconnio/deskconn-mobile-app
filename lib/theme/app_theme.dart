import 'package:deskconn_mobile_app/theme/buttons.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:deskconn_mobile_app/theme/inputs.dart';
import 'package:flutter/material.dart';

class DeskconnTheme {
  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: DeskconnColors.primary,
      onPrimary: DeskconnColors.onPrimary,
      secondary: DeskconnColors.secondary,
      onSecondary: Colors.white,
      surface: DeskconnColors.surface,
      onSurface: DeskconnColors.text,
      error: Colors.red.shade700,
      outline: DeskconnColors.border,
      outlineVariant: DeskconnColors.cardBorder,
      surfaceContainerHighest: DeskconnColors.surfaceTint,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DeskconnColors.body,
      cardColor: scheme.surface,
      dividerColor: DeskconnColors.cardBorder,
      disabledColor: DeskconnColors.subtle.withValues(alpha: 0.45),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: DeskconnColors.text,
        displayColor: DeskconnColors.heading,
      ),
      cardTheme: CardThemeData(
        color: DeskconnColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DeskconnColors.cardBorder),
        ),
      ),
      inputDecorationTheme: DeskconnInputs.light(),
      elevatedButtonTheme: DeskconnButtons.light,
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: DeskconnColors.primary)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: DeskconnColors.primary),
      appBarTheme: const AppBarTheme(
        backgroundColor: DeskconnColors.body,
        foregroundColor: DeskconnColors.heading,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: DeskconnColors.surface),
      extensions: const [DeskconnPalette.light],
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: DeskconnColors.darkOnSurface,
      onPrimary: DeskconnColors.darkBackground,
      secondary: DeskconnColors.secondary,
      onSecondary: Colors.white,
      surface: DeskconnColors.darkSurface,
      onSurface: DeskconnColors.darkOnSurface,
      error: Colors.red.shade300,
      outline: DeskconnColors.darkBorder,
      outlineVariant: DeskconnColors.darkBorder,
      surfaceContainerHighest: DeskconnColors.darkSurfaceTint,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DeskconnColors.darkBackground,
      cardColor: scheme.surface,
      dividerColor: DeskconnColors.darkBorder,
      disabledColor: DeskconnColors.darkOnSurface.withValues(alpha: 0.45),
      textTheme: ThemeData.dark().textTheme.apply(bodyColor: DeskconnColors.darkOnSurface, displayColor: Colors.white),
      cardTheme: CardThemeData(
        color: DeskconnColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DeskconnColors.darkBorder),
        ),
      ),
      inputDecorationTheme: DeskconnInputs.dark(),
      elevatedButtonTheme: DeskconnButtons.dark,
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: DeskconnColors.darkOnSurface)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Colors.white),
      appBarTheme: AppBarTheme(
        backgroundColor: DeskconnColors.darkBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: DeskconnColors.darkBackground),
      extensions: const [DeskconnPalette.dark],
    );
  }
}
