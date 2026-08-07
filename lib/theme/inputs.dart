import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';

class DeskconnInputs {
  static InputDecorationTheme light() {
    return InputDecorationTheme(
      filled: true,
      fillColor: DeskconnColors.surface,
      border: _border(DeskconnColors.border),
      enabledBorder: _border(DeskconnColors.border),
      focusedBorder: _border(DeskconnColors.primary),
      errorBorder: _border(Colors.red.shade400),
      focusedErrorBorder: _border(Colors.red.shade700),
      labelStyle: const TextStyle(color: DeskconnColors.muted),
      hintStyle: const TextStyle(color: DeskconnColors.subtle),
    );
  }

  static InputDecorationTheme dark() {
    return InputDecorationTheme(
      filled: true,
      fillColor: DeskconnColors.darkSurface,
      border: _border(DeskconnColors.darkBorder),
      enabledBorder: _border(DeskconnColors.darkBorder),
      focusedBorder: _border(DeskconnColors.darkOnSurface),
      errorBorder: _border(Colors.red.shade300),
      focusedErrorBorder: _border(Colors.red.shade300),
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
