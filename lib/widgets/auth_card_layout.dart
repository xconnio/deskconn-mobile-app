import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:flutter/material.dart';

class AuthCardLayout extends StatelessWidget {
  const AuthCardLayout({super.key, required this.child, this.alignment = const Alignment(0, -0.2)});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DeskconnLogo(),
              const SizedBox(height: 32),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeskconnUI.cardRadius)),
                child: SizedBox(
                  width: DeskconnUI.cardWidth,
                  child: Padding(padding: const EdgeInsets.all(24), child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
