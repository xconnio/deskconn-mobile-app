import 'package:deskconn_mobile_app/core/update/update_service.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:deskconn_mobile_app/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefKeyWebRtcEnabled = 'webrtc_enabled';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _webRtcEnabled = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? false;
    });
  }

  Future<void> _setWebRtc(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyWebRtcEnabled, value);
    setState(() => _webRtcEnabled = value);
    // Invalidate cached sessions so the next connection uses the new mode
    await DesktopConnectionManager().invalidateAll();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final release = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (release != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) => UpdateDialog(release: release),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already on the latest version.')));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Check for Updates'),
            trailing: _checkingUpdate
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _checkingUpdate ? null : _checkForUpdate,
          ),
        ],
      ),
    );
  }
}
