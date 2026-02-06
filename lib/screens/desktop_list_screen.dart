import 'package:deskconn_mobile_app/screens/desktop_details_screen.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/providers/session_provider.dart';

class DesktopListScreen extends StatelessWidget {
  const DesktopListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return AppShell(
      title: 'Desktops',
      body: session.desktopsLoading
          ? const Center(child: CircularProgressIndicator())
          : session.desktops.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.desktop_windows_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No desktop attached yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                ],
              ),
            )
          : ListView.builder(
              itemCount: session.desktops.length,
              itemBuilder: (context, i) {
                final d = session.desktops[i];

                return ListTile(
                  leading: const Icon(Icons.desktop_windows),
                  title: Text(d['name'] ?? d['authid']),
                  subtitle: Text(d['authid']),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => DesktopDetailsScreen(desktop: d)));
                  },
                );
              },
            ),
    );
  }
}
