import 'dart:async';

import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

import 'package:xconn/xconn.dart';

import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  bool _openingShell = false;

  final WampClient _shellClient = WampClient();

  @override
  void dispose() {
    _shellClient.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.read<SessionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.desktop['name'] ?? 'Desktop'),
        actions: [
          if (_openingShell)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.terminal, size: 28),
              tooltip: 'Open Shell',
              onPressed: () => _openShell(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionTile(icon: Icons.brightness_medium, title: "Brightness", onTap: () => _setBrightness(sessionProvider)),
          _ActionTile(icon: Icons.volume_up, title: "Volume", onTap: () => _setVolume(sessionProvider)),
          _ActionTile(icon: Icons.lock, title: "Lock Screen", onTap: () => _lock(sessionProvider)),
        ],
      ),
    );
  }

  Future<void> _openShell(BuildContext context) async {
    if (_openingShell) return;

    setState(() => _openingShell = true);
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text("Connecting shell...")));

    try {
      final shellSession = await _createShellSession();
      if (!context.mounted) return;

      scaffold.hideCurrentSnackBar();

      await Navigator.push(context, MaterialPageRoute(builder: (_) => ShellScreen(session: shellSession)));

      try {
        await shellSession.close();
      } catch (_) {}
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text("Failed to open shell: ${e.toString().split('\n').first}"),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingShell = false);
      }
    }
  }

  Future<Session> _createShellSession() async {
    final String? authId = await DeviceIdentity.lastEmail();
    final String? privateKey = await DeviceIdentity.privateKey();
    final String realm = widget.desktop['realm'];

    if (authId == null || privateKey == null) {
      throw Exception("Missing authid or private_key in desktop data");
    }

    final session = await _shellClient.connectCryptoSign(authId: authId, privateKey: privateKey, realm: realm);

    return session;
  }

  Future<void> _setBrightness(SessionProvider sessionProvider) async {
    await sessionProvider.session!.call("io.xconn.desktop.brightness.set", args: [widget.desktop['authid'], 50]);
  }

  Future<void> _setVolume(SessionProvider sessionProvider) async {
    await sessionProvider.session!.call("io.xconn.desktop.volume.set", args: [widget.desktop['authid'], 30]);
  }

  Future<void> _lock(SessionProvider sessionProvider) async {
    await sessionProvider.session!.call("io.xconn.desktop.lock", args: [widget.desktop['authid']]);
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
