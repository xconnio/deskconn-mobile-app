import 'package:deskconn_mobile_app/screens/account_screen.dart';
import 'package:deskconn_mobile_app/screens/devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'theme_toggle.dart';
import 'package:deskconn_mobile_app/screens/invitations_screen.dart';
import 'package:deskconn_mobile_app/screens/organizations_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';

class AppShell extends StatelessWidget {
  final String title;
  final Widget body;
  final PreferredSizeWidget? bottom;

  const AppShell({super.key, required this.title, required this.body, this.bottom});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(title), bottom: bottom, actions: const [ThemeToggleButton()]),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),

              ListTile(
                leading: const Icon(Icons.account_circle),
                title: const Text('Account'),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
                },
              ),

              ListTile(
                leading: const Icon(Icons.devices),
                title: const Text('Devices'),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DevicesScreen()));
                },
              ),

              ListTile(
                leading: const Icon(Icons.business),
                title: const Text('Organizations'),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OrganizationsScreen()));
                },
              ),

              ListTile(
                leading: const Icon(Icons.mail),
                title: const Text('Invitations'),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const InvitationsScreen()));
                },
              ),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Logout", style: TextStyle(color: Colors.red)),
                onTap: () async {
                  await session.logout();

                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const SignInScreen()),
                      (_) => false,
                    );
                  }
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}
