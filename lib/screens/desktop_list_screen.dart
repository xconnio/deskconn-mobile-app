import 'package:deskconn_mobile_app/screens/desktop_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

class DesktopListScreen extends StatelessWidget {
  const DesktopListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Desktops")),
      body: session.desktopsLoading
          ? const Center(child: CircularProgressIndicator())
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DesktopDetailsScreen(desktop: d),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
