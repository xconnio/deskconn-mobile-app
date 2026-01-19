import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: Text(
              theme.mode == ThemeMode.dark ? 'Enabled' : 'Disabled',
            ),
            value: theme.mode == ThemeMode.dark,
            onChanged: (enabled) {
              theme.setTheme(
                enabled ? ThemeMode.dark : ThemeMode.light,
              );
            },
            secondary: Icon(
              theme.mode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
          ),
        ],
      ),
    );
  }
}
