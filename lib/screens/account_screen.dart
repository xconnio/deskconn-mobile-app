import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final nameCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool savingProfile = false;
  bool savingPassword = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionProvider>();
    final account = session.account;
    if (account != null && nameCtrl.text.isEmpty) {
      nameCtrl.text = account['name'] ?? '';
    }
  }

  bool get _canUpdateProfile {
    final session = context.read<SessionProvider>();
    final account = session.account;
    if (account == null) return false;
    return nameCtrl.text.trim() != (account['name'] ?? '');
  }

  bool get _canChangePassword {
    return passCtrl.text.isNotEmpty;
  }

  Future<void> _updateProfile() async {
    FocusScope.of(context).unfocus();

    if (!_canUpdateProfile) return;

    final session = context.read<SessionProvider>();

    setState(() {
      savingProfile = true;
    });

    try {
      final res = await session.session!.call(
        'io.xconn.deskconn.account.update',
        kwargs: {'name': nameCtrl.text.trim()},
      );

      if (!mounted) return;

      if (res.args.isNotEmpty) {
        session.updateAccount(Map<String, dynamic>.from(res.args[0]));
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        savingProfile = false;
      });
    }
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();

    if (!_canChangePassword) return;

    setState(() {
      savingPassword = true;
    });

    try {
      final session = context.read<SessionProvider>();
      await session.session!.call('io.xconn.deskconn.account.update', kwargs: {'password': passCtrl.text});
      passCtrl.clear();
    } catch (_) {}

    if (mounted) {
      setState(() {
        savingPassword = false;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      _delete();
    }
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();

    final session = context.read<SessionProvider>();

    try {
      await session.session!.call('io.xconn.deskconn.account.delete');
    } catch (_) {}

    await session.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SignInScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final session = context.watch<SessionProvider>();
    final account = session.account;

    if (account == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: Text(theme.mode == ThemeMode.dark ? 'Enabled' : 'Disabled'),
            value: theme.mode == ThemeMode.dark,
            onChanged: (enabled) {
              theme.setTheme(enabled ? ThemeMode.dark : ThemeMode.light);
            },
            secondary: Icon(theme.mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
          ),
          const SizedBox(height: 12),
          const Text('Email'),
          const SizedBox(height: 4),
          Text(account['email'] ?? ''),
          const SizedBox(height: 12),
          const Text('Role'),
          const SizedBox(height: 4),
          Text(account['role'] ?? ''),
          const SizedBox(height: 24),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          savingProfile
              ? const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))
              : ElevatedButton(
                  onPressed: _canUpdateProfile ? _updateProfile : null,
                  child: const Text('Update profile'),
                ),
          const SizedBox(height: 32),
          const Text('Security'),
          const SizedBox(height: 12),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          savingPassword
              ? const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))
              : ElevatedButton(
                  onPressed: _canChangePassword ? _changePassword : null,
                  child: const Text('Change password'),
                ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: _confirmDelete,
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}
