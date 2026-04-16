import 'dart:async';
import 'dart:convert';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

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
          IconButton(
            icon: const Icon(Icons.terminal, size: 28),
            tooltip: 'Open Shell',
            onPressed: _openingShell ? null : () => _openShell(context),
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
    _appendShellLog("Starting shell connection");
    _showShellLoadingDialog(context);

    try {
      final shellSession = await _createShellSession();
      if (!context.mounted) return;

      _closeActiveDialog(context);
      setState(() => _openingShell = false);
      _appendShellLog("Shell session ready, opening terminal screen");

      await Navigator.push(context, MaterialPageRoute(builder: (_) => ShellScreen(session: shellSession)));
    } catch (e) {
      final message = _friendlyShellError(e);
      _appendShellLog("Shell open failed: $message");
      if (context.mounted) {
        _closeActiveDialog(context);
        await _showShellErrorDialog(context, message);
      }
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
    _appendShellLog("Loaded device identity for realm $realm");

    if (authId == null || privateKey == null) {
      throw Exception("Missing authid or private_key in desktop data");
    }

    _appendShellLog("Connecting to remote realm");
    final session = await _shellClient.connectCryptoSign(authId: authId, privateKey: privateKey, realm: realm);
    _appendShellLog("Connected to remote realm");

    final prefs = await SharedPreferences.getInstance();
    final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? false;

    if (!webRtcEnabled) {
      _appendShellLog("WebRTC disabled, using direct WAMP session");
      return session;
    }

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

    try {
      _appendShellLog("Attempting WebRTC shell session");
      final webRtcSession = await web_rtc.connectWAMP(config).timeout(const Duration(seconds: 12));
      _appendShellLog("WebRTC shell session established");
      return webRtcSession;
    } catch (e) {
      final errorText = e.toString();
      _appendShellLog("WebRTC shell session failed: ${errorText.split('\n').first}");

      if (_isMissingProcedureError(errorText)) {
        await _safeCloseSession(session);
        throw Exception(
          "Remote device offline or check internet connection. Shell service is unavailable on the remote device.",
        );
      }

      await _safeCloseSession(session);
      throw Exception(errorText);
    }
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authID, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_prefKeyTurnExpiresAt) ?? 0;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (expiresAt > nowSeconds + 60) {
      final username = prefs.getString(_prefKeyTurnUsername)!;
      final credential = prefs.getString(_prefKeyTurnCredential)!;
      final urls = jsonDecode(prefs.getString(_prefKeyTurnUrls)!) as List<dynamic>;
      _appendShellLog("Using cached TURN credentials (expires in ${expiresAt - nowSeconds}s)");
      return {'username': username, 'credential': credential, 'urls': urls};
    }

    _appendShellLog("Fetching fresh TURN credentials from server");
    var session = await _shellClient.connectCryptoSign(
      authId: authID,
      privateKey: privateKey,
      realm: DeskconnConfig.realm,
    );
    final result = await session.call("io.xconn.deskconn.coturn.credentials.create");
    final turnCredential = result.args[0];

    final username = turnCredential['username'] as String;
    final credential = turnCredential['credential'] as String;
    final newExpiresAt = turnCredential['expires_at'] as int;
    final urls = turnCredential['urls'] as List<dynamic>;

    await prefs.setInt(_prefKeyTurnExpiresAt, newExpiresAt);
    await prefs.setString(_prefKeyTurnUsername, username);
    await prefs.setString(_prefKeyTurnCredential, credential);
    await prefs.setString(_prefKeyTurnUrls, jsonEncode(urls));

    _appendShellLog("TURN credentials fetched and cached");
    return {'username': username, 'credential': credential, 'urls': urls};
  }

  void _appendShellLog(String message) {
    final line = "[${DateTime.now().toIso8601String()}] $message";
    debugPrint("DesktopDetailsScreen: $line");
  }

  void _showShellLoadingDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: 16),
              Flexible(child: Text("Connecting to shell...")),
            ],
          ),
        );
      },
    );
  }

  void _closeActiveDialog(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
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

  Future<void> _safeCloseSession(dynamic session) async {
    try {
      await session.close();
    } catch (_) {}
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
