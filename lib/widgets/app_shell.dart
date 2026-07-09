import 'package:deskconn_mobile_app/screens/account_screen.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'theme_toggle.dart';

enum AppShellSection { account, desktops, settings }

class AppShell extends StatelessWidget {
  final String title;
  final Widget body;
  final PreferredSizeWidget? bottom;
  final AppShellSection currentSection;
  final List<Widget>? actions;

  const AppShell({
    super.key,
    required this.title,
    required this.body,
    required this.currentSection,
    this.bottom,
    this.actions,
  });

  Future<void> _openSection(
    BuildContext context, {
    required AppShellSection section,
    required WidgetBuilder builder,
  }) async {
    Navigator.pop(context);
    if (section == currentSection) return;
    if (section == AppShellSection.desktops) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final account = session.account;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = (account?['name'] as String? ?? '').trim();
    final email = (account?['email'] as String? ?? '').trim();
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : email.isNotEmpty
        ? email[0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(title: Text(title), bottom: bottom, actions: [...?actions, const ThemeToggleButton()]),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () =>
                    _openSection(context, section: AppShellSection.account, builder: (_) => const AccountScreen()),
                child: Container(
                  color: isDark ? DeskconnColors.darkSurfaceTint : colorScheme.primary,
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: colorScheme.onPrimary.withValues(alpha: 0.15),
                        child: Text(
                          initial,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.onPrimary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (name.isNotEmpty)
                        Text(
                          name,
                          style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: TextStyle(color: colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _NavTile(
                      icon: Icons.desktop_windows_outlined,
                      label: 'Desktops',
                      selected: currentSection == AppShellSection.desktops,
                      onTap: () => _openSection(
                        context,
                        section: AppShellSection.desktops,
                        builder: (_) => const DesktopListScreen(),
                      ),
                    ),
                    _NavTile(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      selected: currentSection == AppShellSection.settings,
                      onTap: () => _openSection(
                        context,
                        section: AppShellSection.settings,
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(color: Colors.red)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onTap: () async {
                    Navigator.pop(context);
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
              ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? colorScheme.onSurface.withValues(alpha: 0.88) : null;
    final selectedColor = isDark ? Colors.white : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        leading: Icon(icon, color: selected ? selectedColor : defaultColor),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? selectedColor : defaultColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: selected,
        selectedTileColor: isDark ? Colors.white.withValues(alpha: 0.06) : colorScheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: onTap,
      ),
    );
  }
}
