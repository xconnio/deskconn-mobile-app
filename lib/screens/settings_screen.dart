import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefKeyWebRtcEnabled = 'webrtc_enabled';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _webRtcEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? true;
    });
  }

  Future<void> _setWebRtc(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyWebRtcEnabled, value);
    if (!mounted) return;
    setState(() => _webRtcEnabled = value);
    await DesktopConnectionManager().invalidateAll();
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final theme = context.read<ThemeProvider>();
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) {
        var pending = theme.mode;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return SimpleDialog(
              title: const Text('Choose Theme'),
              children: [
                RadioGroup<ThemeMode>(
                  groupValue: pending,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => pending = value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<ThemeMode>(
                        title: const Text('System Default'),
                        value: ThemeMode.system,
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Light'),
                        value: ThemeMode.light,
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('Dark'),
                        value: ThemeMode.dark,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, pending),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null) theme.setTheme(selected);
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System Default',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return AppShell(
      title: 'Settings',
      currentSection: AppShellSection.settings,
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.settings_ethernet),
            title: const Text('Use WebRTC (P2P)'),
            subtitle: const Text('Direct connection; falls back to routed if unavailable'),
            value: _webRtcEnabled,
            onChanged: _setWebRtc,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _themeLabel(theme.mode),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            onTap: () => _chooseTheme(context),
          ),
        ],
      ),
    );
  }
}
