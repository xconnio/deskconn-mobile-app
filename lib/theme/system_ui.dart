import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeskconnSystemUi {
  const DeskconnSystemUi._();

  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? DeskconnColors.darkBackground : DeskconnColors.body,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );
  }
}
