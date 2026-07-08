import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/account_screen.dart';
import 'package:deskconn_mobile_app/screens/devices_screen.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [DeskconnLogo(size: 24), SizedBox(width: 12), Text("Deskconn")]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<SessionProvider>().logout();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _DashboardTile(
              icon: Icons.desktop_windows,
              title: "Desktops",
              subtitle: session.desktopsLoading ? "Loading..." : "${session.desktops.length} connected",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DesktopListScreen()));
              },
            ),
            _DashboardTile(
              icon: Icons.devices,
              title: "Devices",
              subtitle: "Manage trusted devices",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen()));
              },
            ),
            _DashboardTile(
              icon: Icons.person,
              title: "Account",
              subtitle: "Profile & appearance",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeskconnUI.cardRadius)),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
