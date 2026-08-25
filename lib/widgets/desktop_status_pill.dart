import 'package:flutter/material.dart';

import 'package:deskconn_mobile_app/theme/colors.dart';

class DesktopStatusPill extends StatelessWidget {
  final String name;
  final Color dotColor;
  final String statusLabel;
  final bool onWallpaper;

  const DesktopStatusPill({
    super.key,
    required this.name,
    required this.dotColor,
    required this.statusLabel,
    this.onWallpaper = false,
  });

  factory DesktopStatusPill.forSession({
    Key? key,
    required String name,
    required bool isP2P,
    required DeskconnPalette palette,
    bool onWallpaper = false,
  }) {
    return DesktopStatusPill(
      key: key,
      name: name,
      dotColor: isP2P ? palette.statusOnline : palette.statusRouted,
      statusLabel: isP2P ? 'p2p' : 'routed',
      onWallpaper: onWallpaper,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = onWallpaper ? Colors.white : Theme.of(context).colorScheme.onSurface;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name,
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: '($statusLabel)',
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Center(
        child: onWallpaper
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}
