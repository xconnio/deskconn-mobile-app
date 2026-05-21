import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';

class DeskconnButtons {
  static ElevatedButtonThemeData light = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: DeskconnColors.primary,
      foregroundColor: DeskconnColors.onPrimary,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  static ElevatedButtonThemeData dark = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: DeskconnColors.primary,
      foregroundColor: DeskconnColors.onPrimary,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}
