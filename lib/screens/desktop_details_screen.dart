import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xconn/xconn.dart';
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_controller.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_registry.dart';
import 'package:deskconn_mobile_app/core/wallpaper/wallpaper_cache.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/screens/file_explorer_screen.dart';
import 'package:deskconn_mobile_app/screens/remote_control_screen.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/terminal/terminal_screen.dart';

import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';

Uint8List _coerceBytes(dynamic raw) {
  if (raw is Uint8List) return raw;
  if (raw is List<int>) return Uint8List.fromList(raw);
  if (raw is String) return Uint8List.fromList(base64.decode(raw));
  throw FormatException('Unsupported payload type: ${raw.runtimeType}');
}

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
  Uint8List? _wallpaperBytes;

  String? get _realm => widget.desktop['realm']?.toString();

  @override
  void initState() {
    super.initState();
    unawaited(_probeDesktopConnection());
    unawaited(_loadCachedWallpaper());
  }

  Future<void> _loadCachedWallpaper() async {
    final realm = _realm;
    if (realm == null) return;
    final cached = await WallpaperCache.load(realm);
    if (cached != null && mounted) {
      setState(() => _wallpaperBytes = cached);
    }
  }

  Future<void> _refreshWallpaper(Session session) async {
    final realm = _realm;
    if (realm == null) return;
    try {
      final checksumResult = await session
          .call('io.xconn.deskconn.deskconnd.wallpaper.checksum')
          .timeout(DeskconnConfig.callTimeout);
      if (checksumResult.args.isEmpty) return;
      final checksum = checksumResult.args[0].toString();

      final cachedChecksum = await WallpaperCache.cachedChecksum(realm);
      if (cachedChecksum == checksum && _wallpaperBytes != null) return;

      final getResult = await session
          .call('io.xconn.deskconn.deskconnd.wallpaper.get')
          .timeout(const Duration(seconds: 120));
      if (getResult.args.length < 2) return;

      final bytes = _coerceBytes(getResult.args[1]);
      await WallpaperCache.store(realm, bytes, checksum);
      if (mounted) setState(() => _wallpaperBytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final terminalEnabled =
        (_connectionStatus == _DesktopConnectionStatus.routed || _connectionStatus == _DesktopConnectionStatus.p2p) &&
        !_openingTerminal;

    final name = widget.desktop['name'] as String?;
    final authId = widget.desktop['authid']?.toString() ?? '';
    final shortId = authId.length > 4 ? authId.substring(authId.length - 4) : authId;
    final displayName = name ?? 'Desktop #$shortId';

    final wallpaper = _wallpaperBytes;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          wallpaper != null
              ? Image.memory(wallpaper, fit: BoxFit.cover)
              : Container(color: Theme.of(context).scaffoldBackgroundColor),
          if (wallpaper != null) Container(color: Colors.black.withValues(alpha: 0.25)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _probeDesktopConnection,
                    child: GridView.count(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 4),
                      crossAxisCount: 4,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 0.85,
                      children: [
                        _LauncherTile(
                          icon: Icons.description_outlined,
                          badgeColor: const Color(0xFF2C82C9),
                          title: "Documents",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openFileExplorer(context, category: 'documents'),
                        ),
                        _LauncherTile(
                          icon: Icons.folder_open,
                          badgeColor: const Color(0xFFE95420),
                          title: "Files",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openFileExplorer(context),
                        ),
                        _LauncherTile(
                          icon: Icons.image_outlined,
                          badgeColor: const Color(0xFF77216F),
                          title: "Photos",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openFileExplorer(context, category: 'images'),
                        ),
                        _LauncherTile(
                          icon: Icons.settings_remote_outlined,
                          badgeColor: const Color(0xFF0E8420),
                          title: "Remote Ctrl",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openRemoteControl(context),
                        ),
                        _LauncherTile(
                          icon: Icons.terminal,
                          badgeColor: const Color(0xFF2C2C2C),
                          title: "Terminal",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openTerminal(context),
                        ),
                        _LauncherTile(
                          icon: Icons.video_library_outlined,
                          badgeColor: const Color(0xFFC7162B),
                          title: "Videos",
                          enabled: terminalEnabled,
                          onWallpaper: wallpaper != null,
                          onTap: () => _openFileExplorer(context, category: 'videos'),
                        ),
                      ],
                    ),
                  ),
                ),
                _DesktopLabel(name: displayName, status: _connectionStatus, onWallpaper: wallpaper != null),
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
    final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? true;

    if (authId == null || privateKey == null || realm == null) {
      if (mounted) {
        setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
      }
      return;
    }

    final status = await _attemptConnection(realm, authId, privateKey, webRtcEnabled);
    if (mounted) {
      setState(() => _connectionStatus = status ?? _DesktopConnectionStatus.offline);
    }
    if (status != null) {
      final session = DesktopConnectionManager().get(realm)?.session;
      if (session != null) unawaited(_refreshWallpaper(session));
    }

    if (status == null) {
      unawaited(_retryInBackground(realm, authId, privateKey, webRtcEnabled));
    }
  }

  Future<void> _retryInBackground(String realm, String authId, String privateKey, bool webRtcEnabled) async {
    final status = await _attemptConnection(realm, authId, privateKey, webRtcEnabled);
    if (status != null && mounted) {
      setState(() => _connectionStatus = status);
      final session = DesktopConnectionManager().get(realm)?.session;
      if (session != null) unawaited(_refreshWallpaper(session));
    }
  }

  Future<_DesktopConnectionStatus?> _attemptConnection(
    String realm,
    String authId,
    String privateKey,
    bool webRtcEnabled,
  ) async {
    try {
      final connection = await DesktopConnectionManager().acquire(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
      );
      connection.onDisconnected = _handleConnectionDisconnected;

      if (connection.isAgentOnline) {
        return connection.isP2P ? _DesktopConnectionStatus.p2p : _DesktopConnectionStatus.routed;
      }

      final desktopOnline = await _isDesktopAgentOnline(connection.session);
      if (desktopOnline) {
        connection.isAgentOnline = true;
        return connection.isP2P ? _DesktopConnectionStatus.p2p : _DesktopConnectionStatus.routed;
      }

      connection.onDisconnected = null;
      await DesktopConnectionManager().release(realm);
      return null;
    } catch (e) {
      _appendTerminalLog("Desktop connection failed: ${e.toString().split('\n').first}");
      return null;
    }
  }

  void _handleConnectionDisconnected() {
    if (!mounted) return;
    setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
    unawaited(_probeDesktopConnection());
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

  Future<void> _openFileExplorer(BuildContext context, {String? category}) async {
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

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileExplorerScreen(config: config, category: category),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to open Files: $e")));
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
  final Color badgeColor;
  final String title;
  final VoidCallback onTap;
  final bool enabled;
  final bool onWallpaper;

  const _LauncherTile({
    required this.icon,
    required this.badgeColor,
    required this.title,
    required this.onTap,
    this.enabled = true,
    this.onWallpaper = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = onWallpaper
        ? (enabled ? Colors.white : Colors.white54)
        : (enabled ? Theme.of(context).colorScheme.onSurface : Theme.of(context).disabledColor);
    final textShadows = onWallpaper ? [Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 6)] : null;
    final effectiveBadgeColor = enabled ? badgeColor : badgeColor.withValues(alpha: 0.4);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: effectiveBadgeColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: onWallpaper
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Icon(icon, size: 26, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 13, shadows: textShadows),
          ),
        ],
      ),
    );
  }
}

class _DesktopLabel extends StatelessWidget {
  final String name;
  final _DesktopConnectionStatus status;
  final bool onWallpaper;

  const _DesktopLabel({required this.name, required this.status, this.onWallpaper = false});

  @override
  Widget build(BuildContext context) {
    final (dotColor, statusLabel) = switch (status) {
      _DesktopConnectionStatus.checking => (Theme.of(context).colorScheme.secondary, 'connecting'),
      _DesktopConnectionStatus.routed => (Colors.amber.shade700, 'routed'),
      _DesktopConnectionStatus.p2p => (Colors.green, 'p2p'),
      _DesktopConnectionStatus.offline => (Colors.red, 'offline'),
    };
    final textColor = onWallpaper ? Colors.white : Theme.of(context).colorScheme.onSurface;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name,
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: '($statusLabel)',
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Center(
        child: onWallpaper
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}
