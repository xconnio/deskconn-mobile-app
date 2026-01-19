import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DeskconnLogo extends StatelessWidget {
  final double size;

  const DeskconnLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo/deskconn_logo.svg',
      height: size,
      width: size,
    );
  }
}
