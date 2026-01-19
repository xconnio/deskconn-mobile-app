import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return IconButton(
      icon: Icon(
        theme.mode == ThemeMode.dark
            ? Icons.light_mode
            : Icons.dark_mode,
      ),
      tooltip: 'Toggle theme',
      onPressed: () {
        theme.setTheme(
          theme.mode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        );
      },
    );
  }
}
