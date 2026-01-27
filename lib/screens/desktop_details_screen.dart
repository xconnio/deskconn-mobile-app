import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/providers/session_provider.dart';

class DesktopDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(desktop['name'] ?? 'Desktop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionTile(
            icon: Icons.brightness_medium,
            title: "Brightness",
            onTap: () => _setBrightness(session, desktop),
          ),
          _ActionTile(icon: Icons.volume_up, title: "Volume", onTap: () => _setVolume(session, desktop)),
          _ActionTile(icon: Icons.lock, title: "Lock Screen", onTap: () => _lock(session, desktop)),
        ],
      ),
    );
  }

  Future<void> _setBrightness(SessionProvider session, Map<String, dynamic> desktop) async {
    await session.session!.call("io.xconn.desktop.brightness.set", args: [desktop['authid'], 50]);
  }

  Future<void> _setVolume(SessionProvider session, Map<String, dynamic> desktop) async {
    await session.session!.call("io.xconn.desktop.volume.set", args: [desktop['authid'], 30]);
  }

  Future<void> _lock(SessionProvider session, Map<String, dynamic> desktop) async {
    await session.session!.call("io.xconn.desktop.lock", args: [desktop['authid']]);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: onTap),
    );
  }
}
