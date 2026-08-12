import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Auth-scaffold background: a calm, authored gradient that adapts to theme.
class DeskconnAuthBackground extends StatelessWidget {
  final Widget child;

  const DeskconnAuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = DeskconnPalette.of(context);
    final base = palette.background;
    final tint = DeskconnColors.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, tint, isDark ? 0.18 : 0.45)!],
        ),
      ),
      child: child,
    );
  }
}

/// Renders the app logo at a fixed size with a soft halo behind it.
class DeskconnAuthBrand extends StatelessWidget {
  final double size;

  const DeskconnAuthBrand({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.10),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: SvgPicture.asset('assets/logo/deskconn_logo.svg'),
      ),
    );
  }
}
