import 'dart:async';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import '../constants.dart';
import '../wamp/wamp_client.dart';

class DesktopConnection {
  final Session session;
  final bool isP2P;

  DesktopConnection({required this.session, required this.isP2P});

  Future<void> dispose() async {
    try {
      await session.close();
    } catch (_) {}
  }
}

class DesktopConnectionManager {
  static final DesktopConnectionManager _instance = DesktopConnectionManager._();
  factory DesktopConnectionManager() => _instance;
  DesktopConnectionManager._();

  final Map<String, DesktopConnection> _connections = {};

  Map<String, dynamic>? _turnCredentials;
  DateTime? _turnCredentialsExpiry;

  Future<DesktopConnection> connect({
    required String realm,
    required String authId,
    required bool webRtcEnabled,
    required String privateKey,
    Map<String, dynamic>? turnCredentials,
  }) async {
    final key = 'session:$realm';

    final existing = _connections[key];
    if (existing != null) {
      bool connected = false;
      try {
        connected = existing.session.isConnected();
      } catch (_) {}

      if (connected) {
        if (existing.isP2P == webRtcEnabled) {
          return existing;
        }
        await release(realm);
      } else {
        _connections.remove(key);
      }
    }

    final client = WampClient();
    final signalingSession = await client.connectCryptoSignWithSerializer(
      authId: authId,
      privateKey: privateKey,
      realm: realm,
      serializer: CBORSerializer(),
    );

    Session finalSession = signalingSession;
    bool isP2P = false;

    if (webRtcEnabled) {
      try {
        Map<String, dynamic> credentials;
        if (turnCredentials != null) {
          credentials = turnCredentials;
        } else {
          credentials = await _getTurnCredentials(authId, privateKey);
        }

        final config = web_rtc.ClientConfig(
          realm: realm,
          procedureWebRTCOffer: 'io.xconn.webrtc.offer',
          topicAnswererOnCandidate: 'io.xconn.webrtc.answerer.on_candidate',
          topicOffererOnCandidate: 'io.xconn.webrtc.offerer.on_candidate',
          iceServers: [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': credentials['urls'], 'username': credentials['username'], 'credential': credentials['credential']},
          ],
          serializer: CBORSerializer(),
          session: signalingSession,
          authenticator: CryptoSignAuthenticator(authId, privateKey),
        );

        finalSession = await web_rtc.connectWAMP(config).timeout(const Duration(seconds: 12));
        isP2P = true;
      } catch (e) {
        isP2P = false;
      }
    }

    final connection = DesktopConnection(session: finalSession, isP2P: isP2P);
    _connections[key] = connection;
    return connection;
  }

  Future<void> release(String realm) async {
    final key = 'session:$realm';
    final connection = _connections.remove(key);
    if (connection != null) {
      await connection.dispose();
    }
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) async {
    final cached = _turnCredentials;
    final expiry = _turnCredentialsExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return cached;
    }
    final creds = await fetchTurnCredentials(authId, privateKey);
    _turnCredentials = creds;
    final expiresAt = creds['expires_at'];
    _turnCredentialsExpiry = expiresAt is int
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000).subtract(const Duration(minutes: 1))
        : DateTime.now().add(const Duration(hours: 1));
    return creds;
  }

  Future<Map<String, dynamic>> fetchTurnCredentials(String authId, String privateKey) async {
    final turnClient = WampClient();
    try {
      final session = await turnClient.connectCryptoSign(
        authId: authId,
        privateKey: privateKey,
        realm: DeskconnConfig.realm,
      );
      final result = await session.call('io.xconn.deskconn.coturn.credentials.create');
      final turnCredential = result.args[0];
      return {
        'username': turnCredential['username'],
        'credential': turnCredential['credential'],
        'urls': turnCredential['urls'],
        'expires_at': turnCredential['expires_at'],
      };
    } finally {
      await turnClient.disconnect();
    }
  }
}
