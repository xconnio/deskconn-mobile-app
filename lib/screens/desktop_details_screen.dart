import 'dart:async';
import 'dart:convert';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/shell/shell_background_service.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

const String _prefKeyTurnExpiresAt = 'turn_expires_at';
const String _prefKeyTurnUsername = 'turn_username';
const String _prefKeyTurnCredential = 'turn_credential';
const String _prefKeyTurnUrls = 'turn_urls';

enum _DesktopConnectionStatus { checking, routed, p2p, offline }

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  static final Map<String, _DesktopConnectionStatus> _statuses = {};
  static final Set<String> _warmingShells = {};

  bool _openingShell = false;
  _DesktopConnectionStatus _connectionStatus = _DesktopConnectionStatus.checking;

  String? get _realm => widget.desktop['realm']?.toString();

  @override
  void initState() {
    super.initState();
    unawaited(_probeDesktopConnection());
  }

  @override
  Widget build(BuildContext context) {
    final shellEnabled =
        (_connectionStatus == _DesktopConnectionStatus.routed || _connectionStatus == _DesktopConnectionStatus.p2p) &&
        !_openingShell;

    return Scaffold(
      appBar: AppBar(title: Text(widget.desktop['name'] ?? 'Desktop')),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _probeDesktopConnection() async {
    final realm = _realm;
    final existing = realm == null ? null : _statuses[realm];
    if (existing != null) {
      if (mounted) {
        setState(() => _connectionStatus = existing);
      }
      unawaited(_warmShellService(existing));
      return;
    }

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

    final probeClient = WampClient();
    try {
      final session = await probeClient
          .connectCryptoSignWithSerializer(
            authId: authId,
            privateKey: privateKey,
            realm: realm,
            serializer: CBORSerializer(),
          )
          .timeout(const Duration(seconds: 10));
      await session.call("io.xconn.deskconn.deskconnd.exec", args: ["echo"]).timeout(const Duration(seconds: 5));
      var status = _DesktopConnectionStatus.routed;
      if (webRtcEnabled) {
        Session? p2pSession;
        try {
          p2pSession = await _connectP2pSession(session: session, realm: realm, authId: authId, privateKey: privateKey);
          status = _DesktopConnectionStatus.p2p;
        } catch (e) {
          _appendShellLog("P2P session failed, using routed session: ${e.toString().split('\n').first}");
        } finally {
          await _safeCloseSession(p2pSession);
        }
      }
      _statuses[realm] = status;
      if (mounted) {
        setState(() => _connectionStatus = status);
      }
      unawaited(_warmShellService(status));
    } catch (e) {
      _appendShellLog("Desktop connection probe failed: ${e.toString().split('\n').first}");
      if (mounted) {
        setState(() => _connectionStatus = _DesktopConnectionStatus.offline);
      }
    } finally {
      await probeClient.disconnect();
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
      final authId = await DeviceIdentity.lastEmail();
      final privateKey = await DeviceIdentity.privateKey();
      final prefs = await SharedPreferences.getInstance();
      if (authId == null || privateKey == null) {
        throw Exception("Missing shell credentials.");
      }

      if (!context.mounted) return;

      setState(() => _openingShell = false);
      _appendShellLog("Opening shell in background service");

      final config = _shellConfig(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        status: _connectionStatus,
        prefs: prefs,
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

  Future<void> _warmShellService(_DesktopConnectionStatus status) async {
    final realm = _realm;
    if (realm == null ||
        (status != _DesktopConnectionStatus.routed && status != _DesktopConnectionStatus.p2p) ||
        _warmingShells.contains(realm)) {
      return;
    }

    _warmingShells.add(realm);
    try {
      final authId = await DeviceIdentity.lastEmail();
      final privateKey = await DeviceIdentity.privateKey();
      final prefs = await SharedPreferences.getInstance();
      if (authId == null || privateKey == null) return;

      final config = _shellConfig(realm: realm, authId: authId, privateKey: privateKey, status: status, prefs: prefs);
      await startShellBackgroundService(config);
    } catch (e) {
      _appendShellLog("Shell service warmup failed: ${e.toString().split('\n').first}");
    } finally {
      _warmingShells.remove(realm);
    }
  }

  ShellLaunchConfig _shellConfig({
    required String realm,
    required String authId,
    required String privateKey,
    required _DesktopConnectionStatus status,
    required SharedPreferences prefs,
  }) {
    return ShellLaunchConfig(
      sessionKey: 'shell:$realm',
      desktopName: widget.desktop['name']?.toString() ?? 'Desktop',
      realm: realm,
      authId: authId,
      privateKey: privateKey,
      webRtcEnabled: status == _DesktopConnectionStatus.p2p,
      turnCredentials: _cachedTurnCredentials(prefs),
    );
  }

  Future<void> _safeCloseSession(dynamic session) async {
    try {
      await session?.close();
    } catch (_) {}
  }

  Future<Session> _connectP2pSession({
    required Session session,
    required String realm,
    required String authId,
    required String privateKey,
  }) async {
    final turnCredentials = await _getTurnCredentials(authId, privateKey);
    final config = web_rtc.ClientConfig(
      realm: realm,
      procedureWebRTCOffer: "io.xconn.webrtc.offer",
      topicAnswererOnCandidate: "io.xconn.webrtc.answerer.on_candidate",
      topicOffererOnCandidate: "io.xconn.webrtc.offerer.on_candidate",
      iceServers: [
        {"urls": "stun:stun.l.google.com:19302"},
        {
          "urls": turnCredentials['urls'],
          "username": turnCredentials['username'],
          "credential": turnCredentials['credential'],
        },
      ],
      serializer: CBORSerializer(),
      session: session,
      authenticator: CryptoSignAuthenticator(authId, privateKey),
    );

    return web_rtc.connectWAMP(config).timeout(const Duration(seconds: 12));
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedCredentials = _cachedTurnCredentials(prefs);
    if (cachedCredentials != null) {
      return cachedCredentials;
    }

    final turnClient = WampClient();
    try {
      final session = await turnClient.connectCryptoSign(
        authId: authId,
        privateKey: privateKey,
        realm: DeskconnConfig.realm,
      );
      final result = await session.call("io.xconn.deskconn.coturn.credentials.create");
      final turnCredential = result.args[0];

      final username = turnCredential['username'] as String;
      final credential = turnCredential['credential'] as String;
      final expiresAt = turnCredential['expires_at'] as int;
      final urls = turnCredential['urls'] as List<dynamic>;

      await prefs.setInt(_prefKeyTurnExpiresAt, expiresAt);
      await prefs.setString(_prefKeyTurnUsername, username);
      await prefs.setString(_prefKeyTurnCredential, credential);
      await prefs.setString(_prefKeyTurnUrls, jsonEncode(urls));

      return {'username': username, 'credential': credential, 'urls': urls};
    } finally {
      await turnClient.disconnect();
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
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiresAt <= nowSeconds + 60) return null;
      return {'username': username, 'credential': credential, 'urls': jsonDecode(urlsJson) as List<dynamic>};
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
