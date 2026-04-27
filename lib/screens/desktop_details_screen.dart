import 'dart:convert';

import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/shell/shell_background_service.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

const String _prefKeyTurnExpiresAt = 'turn_expires_at';
const String _prefKeyTurnUsername = 'turn_username';
const String _prefKeyTurnCredential = 'turn_credential';
const String _prefKeyTurnUrls = 'turn_urls';

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  bool _openingShell = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.desktop['name'] ?? 'Desktop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionTile(
            icon: Icons.terminal,
            title: "Shell",
            onTap: () {
              if (!_openingShell) _openShell(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openShell(BuildContext context) async {
    if (_openingShell) return;

    setState(() => _openingShell = true);
    _appendShellLog("Starting shell connection");

    try {
      final String? authId = await DeviceIdentity.lastEmail();
      final String? privateKey = await DeviceIdentity.privateKey();
      final String? realm = widget.desktop['realm']?.toString();
      final prefs = await SharedPreferences.getInstance();
      final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? false;

      if (authId == null || privateKey == null || realm == null) {
        throw Exception("Missing shell credentials or remote realm.");
      }

      if (!context.mounted) return;

      setState(() => _openingShell = false);
      _appendShellLog("Opening foreground shell service");

      final config = ShellLaunchConfig(
        sessionKey: DateTime.now().microsecondsSinceEpoch.toString(),
        desktopName: widget.desktop['name']?.toString() ?? 'Desktop',
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
        turnCredentials: _cachedTurnCredentials(prefs),
      );

      await Navigator.push(context, MaterialPageRoute(builder: (_) => ShellScreen(config: config)));
    } catch (e) {
      final message = _friendlyShellError(e);
      _appendShellLog("Shell open failed: $message");
      if (context.mounted) {
        await _showShellErrorDialog(context, message);
      }
    } finally {
      if (mounted) {
        setState(() => _openingShell = false);
      }
    }
  }

  void _appendShellLog(String message) {
    final line = "[${DateTime.now().toIso8601String()}] $message";
    debugPrint("DesktopDetailsScreen: $line");
  }

  Map<String, dynamic>? _cachedTurnCredentials(SharedPreferences prefs) {
    final expiresAt = prefs.getInt(_prefKeyTurnExpiresAt);
    final username = prefs.getString(_prefKeyTurnUsername);
    final credential = prefs.getString(_prefKeyTurnCredential);
    final urlsJson = prefs.getString(_prefKeyTurnUrls);

    if (expiresAt == null || username == null || credential == null || urlsJson == null) {
      return null;
    }

    try {
      return {
        'expiresAt': expiresAt,
        'username': username,
        'credential': credential,
        'urls': jsonDecode(urlsJson) as List<dynamic>,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _showShellErrorDialog(BuildContext context, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Shell Unavailable"),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text("Close"))],
        );
      },
    );
  }

  bool _isMissingProcedureError(String errorText) {
    final normalized = errorText.toLowerCase();
    return normalized.contains("wamp.error.no_such_procedure");
  }

  String _friendlyShellError(Object error) {
    final errorText = error.toString();
    if (_isMissingProcedureError(errorText)) {
      return "Remote device offline. Check internet and try again.";
    }
    if (errorText.toLowerCase().contains("timeout")) {
      return "Shell connection timed out. Try again.";
    }
    return "Remote device offline or Check internet and try again.";
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
