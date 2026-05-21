import 'package:flutter/material.dart';

class DeskconnColors {
  // Web theme tokens from deskconn-web-app/src/assets/theme.css.
  static const primary = Color(0xFF111827);
  static const primaryHover = Color(0xFF1F2937);
  static const onPrimary = Colors.white;
  static const secondary = Color(0xFF2C2E33);

  static const body = Color(0xFFF8FAFC);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFF1F5F9);
  static const border = Color(0xFFE2E8F0);
  static const cardBorder = Color(0xFFE8ECF0);

  static const text = Color(0xFF334155);
  static const heading = Color(0xFF1E293B);
  static const muted = Color(0xFF475569);
  static const subtle = Color(0xFF64748B);

  static const overlay = Color(0x662C2E33);

  // Dark fallback derived from the same slate family so theme toggle stays coherent.
  static const darkBackground = Color(0xFF0F1724);
  static const darkSurface = Color(0xFF141E31);
  static const darkSurfaceTint = Color(0xFF1A2538);
  static const darkBorder = Color(0xFF334155);
  static const darkOnSurface = Color(0xFFE2E8F0);
}
