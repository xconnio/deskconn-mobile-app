import 'dart:async';

import 'package:xconn/xconn.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_controller.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_registry.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/screens/file_explorer_screen.dart';
import 'package:deskconn_mobile_app/screens/remote_control_screen.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/terminal/terminal_screen.dart';

import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';

enum _DesktopConnectionStatus { checking, routed, p2p, offline }

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  bool _openingTerminal = false;
  _DesktopConnectionStatus _connectionStatus = _DesktopConnectionStatus.checking;

  String? get _realm => widget.desktop['realm']?.toString();

  @override
  void initState() {
    super.initState();
    unawaited(_probeDesktopConnection());
  }

  @override
  Widget build(BuildContext context) {
    final terminalEnabled =
        (_connectionStatus == _DesktopConnectionStatus.routed || _connectionStatus == _DesktopConnectionStatus.p2p) &&
        !_openingTerminal;

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
            child: RefreshIndicator(
              onRefresh: _probeDesktopConnection,
              child: GridView.count(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _LauncherTile(
                    icon: Icons.terminal,
                    title: "Terminal",
                    enabled: terminalEnabled,
                    onTap: () => _openTerminal(context),
                  ),
                  _LauncherTile(
                    icon: Icons.folder_open,
                    title: "Files",
                    enabled: terminalEnabled,
                    onTap: () => _openFileExplorer(context),
                  ),
                  _LauncherTile(
                    icon: Icons.settings_remote_outlined,
                    title: "Remote Ctrl",
                    enabled: terminalEnabled,
                    onTap: () => _openRemoteControl(context),
                  ),
                ],
              ),
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
      final connection = await DesktopConnectionManager().acquire(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
      );

      if (connection.isAgentOnline) {
        if (mounted) {
          setState(
            () => _connectionStatus = connection.isP2P ? _DesktopConnectionStatus.p2p : _DesktopConnectionStatus.routed,
          );
        }
        return;
      }

      final desktopOnline = await _isDesktopAgentOnline(connection.session);
      if (desktopOnline) connection.isAgentOnline = true;

      if (mounted) {
        setState(
          () => _connectionStatus = desktopOnline
              ? (connection.isP2P ? _DesktopConnectionStatus.p2p : _DesktopConnectionStatus.routed)
              : _DesktopConnectionStatus.offline,
        );
      }
    } catch (e) {
      _appendTerminalLog("Desktop connection failed: ${e.toString().split('\n').first}");
      if (mounted) {
        setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
      }
    }
  }

  Future<bool> _isDesktopAgentOnline(Session session) async {
    try {
      final enc = await Encryption.create();
      await session
          .call('io.xconn.deskconn.deskconnd.key.exchange', args: [enc.clientPublicKey])
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      if (e.toString().toLowerCase().contains('wamp.error.no_such_procedure')) {
        return false;
      }
      if (e is TimeoutException) return false;
      return true;
    }
  }

  Future<void> _openRemoteControl(BuildContext context) async {
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

      final config = _terminalConfig(realm: realm, authId: authId, privateKey: privateKey, status: _connectionStatus);

      await Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteControlScreen(config: config)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to open Remote Control: $e")));
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

      final config = _terminalConfig(realm: realm, authId: authId, privateKey: privateKey, status: _connectionStatus);

      await Navigator.push(context, MaterialPageRoute(builder: (_) => FileExplorerScreen(config: config)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to open File Explorer: $e")));
      }
    }
  }

  Future<void> _openTerminal(BuildContext context) async {
    final realm = _realm;
    if (_openingTerminal ||
        realm == null ||
        (_connectionStatus != _DesktopConnectionStatus.routed && _connectionStatus != _DesktopConnectionStatus.p2p)) {
      return;
    }

    setState(() => _openingTerminal = true);
    _appendTerminalLog("Starting terminal connection");

    try {
      var controller = TerminalRegistry().getActive(realm);

      if (controller == null) {
        final authId = await DeviceIdentity.lastEmail();
        final privateKey = await DeviceIdentity.privateKey();
        if (authId == null || privateKey == null) {
          throw Exception("Missing terminal credentials.");
        }

        final config = _terminalConfig(realm: realm, authId: authId, privateKey: privateKey, status: _connectionStatus);

        controller = TerminalController(config: config);

        controller.onClosed = () => TerminalRegistry().remove(realm);

        TerminalRegistry().register(realm, controller);
        unawaited(controller.start());
        _appendTerminalLog("Terminal controller created");
      } else {
        _appendTerminalLog("Reusing persistent terminal controller");
      }

      if (!context.mounted) return;

      setState(() => _openingTerminal = false);
      _appendTerminalLog("Navigating to terminal screen");

      await Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalScreen(controller: controller!)));
    } catch (e) {
      final message = _friendlyTerminalError(e);
      _appendTerminalLog("Terminal open failed: $message");
      if (context.mounted) {
        await _showTerminalErrorDialog(context, message);
      }
    } finally {
      if (mounted) {
        setState(() => _openingTerminal = false);
      }
    }
  }

  DesktopSessionLaunchConfig _terminalConfig({
    required String realm,
    required String authId,
    required String privateKey,
    required _DesktopConnectionStatus status,
  }) {
    return DesktopSessionLaunchConfig(
      sessionKey: 'terminal:$realm',
      desktopName: widget.desktop['name']?.toString() ?? 'Desktop',
      realm: realm,
      authId: authId,
      privateKey: privateKey,
      webRtcEnabled: status == _DesktopConnectionStatus.p2p,
    );
  }

  void _appendTerminalLog(String message) {
    final line = "[${DateTime.now().toIso8601String()}] $message";
    debugPrint("DesktopDetailsScreen: $line");
  }

  Future<void> _showTerminalErrorDialog(BuildContext context, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Terminal Unavailable"),
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

  String _friendlyTerminalError(Object error) {
    final errorText = error.toString();
    if (_isMissingProcedureError(errorText)) {
      return "Remote device offline. Check internet and try again.";
    }
    if (errorText.toLowerCase().contains("timeout")) {
      return "Terminal connection timed out. Try again.";
    }
    return "Remote device offline or Check internet and try again.";
  }
}

class _LauncherTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;

  const _LauncherTile({required this.icon, required this.title, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor;
    final textColor = enabled ? Theme.of(context).colorScheme.onSurface : Theme.of(context).disabledColor;

    return Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: iconColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ],
        ),
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
      _DesktopConnectionStatus.checking => (Theme.of(context).colorScheme.secondary, 'Connecting'),
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
