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
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.desktop_windows_outlined,
                      size: 80,
                      color: Theme.of(context).disabledColor.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No desktop attached yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connected desktops will appear here',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).hintColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: session.desktops.length,
              itemBuilder: (context, i) {
                final d = session.desktops[i];
                final name = d['name'] as String?;
                final authId = d['authid']?.toString() ?? '';
                final shortId = authId.length > 4 ? authId.substring(authId.length - 4) : authId;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.desktop_windows, color: Theme.of(context).primaryColor),
                    ),
                    title: Text(name ?? 'Unnamed Desktop', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('• $shortId', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DesktopDetailsScreen(desktop: d)));
                    },
                  ),
                );
              },
            ),
    );
  }
}
