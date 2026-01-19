import 'package:deskconn_mobile_app/theme/buttons.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:deskconn_mobile_app/theme/inputs.dart';
import 'package:flutter/material.dart';


class DeskconnTheme {
  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: DeskconnColors.primary,
      onPrimary: DeskconnColors.onPrimary,
      surface: DeskconnColors.lightSurface,
      onSurface: DeskconnColors.lightOnSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surface,
      textTheme: ThemeData.light().textTheme,
      inputDecorationTheme: DeskconnInputs.light(),
      elevatedButtonTheme: DeskconnButtons.light,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: DeskconnColors.primary,
      surface: DeskconnColors.darkSurface,
      onSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surface,
      textTheme: ThemeData.dark().textTheme,
      inputDecorationTheme: DeskconnInputs.dark(),
      elevatedButtonTheme: DeskconnButtons.dark,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }
}
