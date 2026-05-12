import 'dart:async';

import 'package:deskconn_mobile_app/core/shell/shell_controller.dart';
import 'package:deskconn_mobile_app/core/shell/shell_registry.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/screens/file_explorer_screen.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

import 'package:deskconn_mobile_app/core/shell/shell_background_service.dart';

enum _DesktopConnectionStatus { checking, routed, p2p, offline }

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  bool _openingShell = false;
  _DesktopConnectionStatus _connectionStatus = _DesktopConnectionStatus.checking;

  String? get _realm => widget.desktop['realm']?.toString();

  @override
  void initState() {
    super.initState();
    unawaited(_probeDesktopConnection());
  }

  @override
  void dispose() {
    final realm = _realm;
    if (realm != null) {
      unawaited(DesktopConnectionManager().release(realm));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shellEnabled =
        (_connectionStatus == _DesktopConnectionStatus.routed || _connectionStatus == _DesktopConnectionStatus.p2p) &&
        !_openingShell;

    final name = widget.desktop['name'] as String?;
    final authId = widget.desktop['authid']?.toString() ?? '';
    final shortId = authId.length > 4 ? authId.substring(authId.length - 4) : authId;

    return Scaffold(
      appBar: AppBar(title: Text(name ?? 'Desktop #$shortId')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBar(status: _connectionStatus),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ActionTile(
                  icon: Icons.terminal,
                  title: "Shell",
                  enabled: shellEnabled,
                  onTap: () => _openShell(context),
                ),
                _ActionTile(
                  icon: Icons.folder_open,
                  title: "File Explorer",
                  enabled: shellEnabled,
                  onTap: () => _openFileExplorer(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _probeDesktopConnection() async {
    final realm = _realm;
    if (mounted) {
      setState(() => _connectionStatus = _DesktopConnectionStatus.checking);
    }

    final authId = await DeviceIdentity.lastEmail();
    final privateKey = await DeviceIdentity.privateKey();
    final prefs = await SharedPreferences.getInstance();
    final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? false;

    if (authId == null || privateKey == null || realm == null) {
      if (mounted) {
        setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
      }
      return;
    }

    try {
      final connection = await DesktopConnectionManager().connect(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
      );

      if (mounted) {
        setState(
          () => _connectionStatus = connection.isP2P ? _DesktopConnectionStatus.p2p : _DesktopConnectionStatus.routed,
        );
      }
    } catch (e) {
      _appendShellLog("Desktop connection failed: ${e.toString().split('\n').first}");
      if (mounted) {
        setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
      }
    }
  }

  Future<void> _openFileExplorer(BuildContext context) async {
    final realm = _realm;
    if (realm == null ||
        (_connectionStatus != _DesktopConnectionStatus.routed && _connectionStatus != _DesktopConnectionStatus.p2p)) {
      return;
    }

    try {
      final authId = await DeviceIdentity.lastEmail();
      final privateKey = await DeviceIdentity.privateKey();
      if (authId == null || privateKey == null) {
        throw Exception("Missing credentials.");
      }

      if (!context.mounted) return;

      final config = _shellConfig(realm: realm, authId: authId, privateKey: privateKey, status: _connectionStatus);

      await Navigator.push(context, MaterialPageRoute(builder: (_) => FileExplorerScreen(config: config)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to open File Explorer: $e")));
      }
    }
  }

  Future<void> _openShell(BuildContext context) async {
    final realm = _realm;
    if (_openingShell ||
        realm == null ||
        (_connectionStatus != _DesktopConnectionStatus.routed && _connectionStatus != _DesktopConnectionStatus.p2p)) {
      return;
    }

    setState(() => _openingShell = true);
    _appendShellLog("Starting shell connection");

    try {
      var controller = ShellRegistry().getActive(realm);

      if (controller == null) {
        final authId = await DeviceIdentity.lastEmail();
        final privateKey = await DeviceIdentity.privateKey();
        if (authId == null || privateKey == null) {
          throw Exception("Missing shell credentials.");
        }

        final config = _shellConfig(realm: realm, authId: authId, privateKey: privateKey, status: _connectionStatus);

        controller = ShellController(config: config);

        controller.onClosed = () => ShellRegistry().closeShell(realm);

        ShellRegistry().register(realm, controller);
        unawaited(controller.start());
        _appendShellLog("Shell controller created");
      } else {
        _appendShellLog("Reusing persistent shell controller");
      }

      if (!context.mounted) return;

      setState(() => _openingShell = false);
      _appendShellLog("Navigating to shell screen");

      await Navigator.push(context, MaterialPageRoute(builder: (_) => ShellScreen(controller: controller!)));
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

  ShellLaunchConfig _shellConfig({
    required String realm,
    required String authId,
    required String privateKey,
    required _DesktopConnectionStatus status,
  }) {
    return ShellLaunchConfig(
      sessionKey: 'shell:$realm',
      desktopName: widget.desktop['name']?.toString() ?? 'Desktop',
      realm: realm,
      authId: authId,
      privateKey: privateKey,
      webRtcEnabled: status == _DesktopConnectionStatus.p2p,
    );
  }

  void _appendShellLog(String message) {
    final line = "[${DateTime.now().toIso8601String()}] $message";
    debugPrint("DesktopDetailsScreen: $line");
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
  final bool enabled;

  const _ActionTile({required this.icon, required this.title, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: enabled ? null : Theme.of(context).disabledColor),
        title: Text(title, style: enabled ? null : TextStyle(color: Theme.of(context).disabledColor)),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final _DesktopConnectionStatus status;

  const _StatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      _DesktopConnectionStatus.checking => (Colors.orange, 'Connecting'),
      _DesktopConnectionStatus.routed => (Colors.green, 'Online (routed)'),
      _DesktopConnectionStatus.p2p => (Colors.green, 'Online (p2p)'),
      _DesktopConnectionStatus.offline => (Colors.red, 'Offline'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
