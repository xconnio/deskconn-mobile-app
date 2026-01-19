import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';

class DeskconnInputs {
  static InputDecorationTheme light() {
    return InputDecorationTheme(
      filled: true,
      fillColor: DeskconnColors.lightSurface,
      border: _border(Colors.grey.shade300),
      enabledBorder: _border(Colors.grey.shade300),
      focusedBorder: _border(DeskconnColors.primary),
    );
  }

  static InputDecorationTheme dark() {
    return InputDecorationTheme(
      filled: true,
      fillColor: DeskconnColors.darkSurface,
      border: _border(DeskconnColors.darkBorder),
      enabledBorder: _border(DeskconnColors.darkBorder),
      focusedBorder: _border(DeskconnColors.primary),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white54),
    );
  }

  static OutlineInputBorder _border(Color c) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
  }
}
