import 'package:deskconn_mobile_app/screens/account_screen.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/screens/devices_screen.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'theme_toggle.dart';
import 'package:deskconn_mobile_app/screens/invitations_screen.dart';
import 'package:deskconn_mobile_app/screens/organizations_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';

enum AppShellSection { account, desktops, devices, organizations, invitations, settings }

class AppShell extends StatelessWidget {
  final String title;
  final Widget body;
  final PreferredSizeWidget? bottom;
  final AppShellSection currentSection;

  const AppShell({super.key, required this.title, required this.body, required this.currentSection, this.bottom});

  Future<void> _openSection(
    BuildContext context, {
    required AppShellSection section,
    required WidgetBuilder builder,
  }) async {
    Navigator.pop(context);

    if (section == currentSection) {
      return;
    }

    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: builder));
  }

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
                selected: currentSection == AppShellSection.account,
                onTap: () {
                  _openSection(context, section: AppShellSection.account, builder: (_) => const AccountScreen());
                },
              ),

              ListTile(
                leading: const Icon(Icons.devices),
                title: const Text('Desktops'),
                selected: currentSection == AppShellSection.desktops,
                onTap: () {
                  _openSection(context, section: AppShellSection.desktops, builder: (_) => const DesktopListScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.devices),
                title: const Text('Devices'),
                selected: currentSection == AppShellSection.devices,
                onTap: () {
                  _openSection(context, section: AppShellSection.devices, builder: (_) => const DevicesScreen());
                },
              ),

              ListTile(
                leading: const Icon(Icons.business),
                title: const Text('Organizations'),
                selected: currentSection == AppShellSection.organizations,
                onTap: () {
                  _openSection(
                    context,
                    section: AppShellSection.organizations,
                    builder: (_) => const OrganizationsScreen(),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.mail),
                title: const Text('Invitations'),
                selected: currentSection == AppShellSection.invitations,
                onTap: () {
                  _openSection(
                    context,
                    section: AppShellSection.invitations,
                    builder: (_) => const InvitationsScreen(),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                selected: currentSection == AppShellSection.settings,
                onTap: () {
                  _openSection(context, section: AppShellSection.settings, builder: (_) => const SettingsScreen());
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
