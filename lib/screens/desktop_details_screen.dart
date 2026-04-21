import 'dart:async';
import 'dart:convert';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';

import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

const String _prefKeyTurnExpiresAt = 'turn_expires_at';
const String _prefKeyTurnUsername = 'turn_username';
const String _prefKeyTurnCredential = 'turn_credential';
const String _prefKeyTurnUrls = 'turn_urls';

const _idleTimeout = Duration(minutes: 2);

enum _SessionStatus { connecting, connected, disconnected }

// Pooled connection kept alive across screen navigations, keyed by realm.
class _PooledConnection {
  final WampClient client;
  final Session session;
  final bool webRtcEnabled;
  final _SessionStatus status;

  const _PooledConnection({
    required this.client,
    required this.session,
    required this.webRtcEnabled,
    required this.status,
  });

  _PooledConnection copyWith({_SessionStatus? status}) => _PooledConnection(
    client: client,
    session: session,
    webRtcEnabled: webRtcEnabled,
    status: status ?? this.status,
  );
}

class DesktopDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> desktop;

  const DesktopDetailsScreen({super.key, required this.desktop});

  @override
  State<DesktopDetailsScreen> createState() => _DesktopDetailsScreenState();
}

class _DesktopDetailsScreenState extends State<DesktopDetailsScreen> {
  // Shared across all instances — survives back-navigation.
  static final Map<String, _PooledConnection> _pool = {};

  bool _openingShell = false;
  Timer? _idleTimer;
  _SessionStatus _status = _SessionStatus.connecting;
  bool _webRtcEnabled = false;

  String get _realm => widget.desktop['realm'] as String;
  Session? get _session => _pool[_realm]?.session;

  @override
  void initState() {
    super.initState();
    _attachOrConnect();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    // Do NOT disconnect — session lives in the pool for the next visit.
    super.dispose();
  }

  /// Reuses an existing pooled session or creates a new one.
  Future<void> _attachOrConnect() async {
    final existing = _pool[_realm];
    if (existing != null) {
      _webRtcEnabled = existing.webRtcEnabled;
      if (mounted) setState(() => _status = existing.status);
      if (existing.status == _SessionStatus.connected) _resetIdleTimer();
      return;
    }
    await _connectSession();
  }

  Future<void> _connectSession() async {
    if (mounted) setState(() => _status = _SessionStatus.connecting);

    // Clean up any stale pool entry for this realm before reconnecting.
    final stale = _pool.remove(_realm);
    await stale?.client.disconnect();

    try {
      final authId = await DeviceIdentity.lastEmail();
      final privateKey = await DeviceIdentity.privateKey();
      if (authId == null || privateKey == null) {
        if (mounted) setState(() => _status = _SessionStatus.disconnected);
        return;
      }

      final client = WampClient();
      final session = await client.connectCryptoSign(authId: authId, privateKey: privateKey, realm: _realm);

      if (!mounted) {
        await client.disconnect();
        return;
      }

      // Probe the desktop agent — cloud router can be reachable while the
      // agent on the actual machine is not running.
      try {
        await session.call("io.xconn.deskconn.deskconnd.exec", args: ["echo"]).timeout(const Duration(seconds: 5));
      } catch (e) {
        final err = e.toString().toLowerCase();
        if (err.contains("no_such_procedure")) {
          _pool[_realm] = _PooledConnection(
            client: client,
            session: session,
            webRtcEnabled: false,
            status: _SessionStatus.disconnected,
          );
          if (mounted) setState(() => _status = _SessionStatus.disconnected);
          return;
        }
        await client.disconnect();
        if (mounted) setState(() => _status = _SessionStatus.disconnected);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? false;

      _pool[_realm] = _PooledConnection(
        client: client,
        session: session,
        webRtcEnabled: webRtcEnabled,
        status: _SessionStatus.connected,
      );
      _webRtcEnabled = webRtcEnabled;
      setState(() => _status = _SessionStatus.connected);
      _resetIdleTimer();
    } catch (_) {
      if (mounted) setState(() => _status = _SessionStatus.disconnected);
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _killSessionSilently);
  }

  void _killSessionSilently() {
    final conn = _pool.remove(_realm);
    if (mounted) setState(() => _status = _SessionStatus.disconnected);
    conn?.client.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == _SessionStatus.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.desktop['name'] ?? 'Desktop')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBar(status: _status, webRtcEnabled: _webRtcEnabled),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ActionTile(
                  icon: Icons.terminal,
                  title: "Shell",
                  enabled: connected,
                  onTap: () {
                    if (!_openingShell) _openShell(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openShell(BuildContext context) async {
    if (_openingShell) return;
    setState(() => _openingShell = true);
    _idleTimer?.cancel();
    _showShellLoadingDialog(context);

    Session? shellSession;

    try {
      final session = _session;
      if (session == null) throw Exception("Could not connect to desktop");

      final authId = await DeviceIdentity.lastEmail();
      final privateKey = await DeviceIdentity.privateKey();
      if (authId == null || privateKey == null) throw Exception("Missing credentials");

      shellSession = await _buildShellSession(session, authId, privateKey);
      if (!context.mounted) return;

      _closeActiveDialog(context);
      setState(() => _openingShell = false);

      await Navigator.push(context, MaterialPageRoute(builder: (_) => ShellScreen(session: shellSession!)));

      // Whether the user typed "exit" or pressed back, session stays alive.
      // For WebRTC the wrapper is no longer needed; close it but keep the WAMP session.
      if (shellSession != session) _safeCloseSession(shellSession);
      if (_session != null) _resetIdleTimer();
    } catch (e) {
      final message = _friendlyShellError(e);
      if (context.mounted) {
        _closeActiveDialog(context);
        await _showShellErrorDialog(context, message);
      }
      _resetIdleTimer();
    } finally {
      if (mounted) setState(() => _openingShell = false);
    }
  }

  Future<Session> _buildShellSession(Session session, String authId, String privateKey) async {
    if (!_webRtcEnabled) return session;

    final turnCredentials = await _getTurnCredentials(authId, privateKey);
    final config = web_rtc.ClientConfig(
      realm: _realm,
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
      return await web_rtc.connectWAMP(config).timeout(const Duration(seconds: 12));
    } catch (e) {
      final errorText = e.toString();
      if (_isMissingProcedureError(errorText)) {
        throw Exception(
          "Remote device offline or check internet connection. Shell service is unavailable on the remote device.",
        );
      }
      throw Exception(errorText);
    }
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_prefKeyTurnExpiresAt) ?? 0;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (expiresAt > nowSeconds + 60) {
      return {
        'username': prefs.getString(_prefKeyTurnUsername)!,
        'credential': prefs.getString(_prefKeyTurnCredential)!,
        'urls': jsonDecode(prefs.getString(_prefKeyTurnUrls)!) as List<dynamic>,
      };
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
      final newExpiresAt = turnCredential['expires_at'] as int;
      final urls = turnCredential['urls'] as List<dynamic>;

      await prefs.setInt(_prefKeyTurnExpiresAt, newExpiresAt);
      await prefs.setString(_prefKeyTurnUsername, username);
      await prefs.setString(_prefKeyTurnCredential, credential);
      await prefs.setString(_prefKeyTurnUrls, jsonEncode(urls));

      return {'username': username, 'credential': credential, 'urls': urls};
    } finally {
      await turnClient.disconnect();
    }
  }

  void _showShellLoadingDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Flexible(child: Text("Connecting to shell...")),
          ],
        ),
      ),
    );
  }

  void _closeActiveDialog(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _showShellErrorDialog(BuildContext context, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Shell Unavailable"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text("Close"))],
      ),
    );
  }

  bool _isMissingProcedureError(String errorText) =>
      errorText.toLowerCase().contains("wamp.error.no_such_procedure");

  String _friendlyShellError(Object error) {
    final errorText = error.toString();
    if (_isMissingProcedureError(errorText)) return "Remote device offline. Check internet and try again.";
    if (errorText.toLowerCase().contains("timeout")) return "Shell connection timed out. Try again.";
    return "Remote device offline or check internet and try again.";
  }

  Future<void> _safeCloseSession(dynamic session) async {
    try {
      await session?.close();
    } catch (_) {}
  }
}

class _StatusBar extends StatelessWidget {
  final _SessionStatus status;
  final bool webRtcEnabled;

  const _StatusBar({required this.status, required this.webRtcEnabled});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      _SessionStatus.connecting => (Colors.orange, 'Connecting'),
      _SessionStatus.connected => (Colors.green, webRtcEnabled ? 'WebRTC' : 'P2P'),
      _SessionStatus.disconnected => (Colors.red, 'Offline'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withOpacity(0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
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
