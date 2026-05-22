import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

class DesktopConnection {
  final Session session;
  final bool isP2P;
  bool isAgentOnline = false;

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
  final Map<String, Future<DesktopConnection>> _pendingConnections = {};

  Map<String, dynamic>? _turnCredentials;
  DateTime? _turnCredentialsExpiry;

  void _log(String message) {
    debugPrint('[DesktopSession ${DateTime.now().toIso8601String()}] $message');
  }

  // Synchronous cache lookup — returns null if not connected (mirrors web app sessionCache)
  DesktopConnection? get(String realm) {
    final key = 'session:$realm';
    final connection = _connections[key];
    if (connection != null && connection.session.isConnected()) {
      _log('cache hit realm=$realm p2p=${connection.isP2P} active=${_connections.length}');
      return connection;
    }
    if (connection != null) {
      _log('cache stale realm=$realm removing disconnected session');
    }
    _connections.remove(key);
    return null;
  }

  Future<DesktopConnection> acquire({
    required String realm,
    required String authId,
    required bool webRtcEnabled,
    required String privateKey,
    Map<String, dynamic>? turnCredentials,
  }) {
    _log('acquire realm=$realm webrtc=$webRtcEnabled');
    return connect(
      realm: realm,
      authId: authId,
      webRtcEnabled: webRtcEnabled,
      privateKey: privateKey,
      turnCredentials: turnCredentials,
    );
  }

  Future<DesktopConnection> connect({
    required String realm,
    required String authId,
    required bool webRtcEnabled,
    required String privateKey,
    Map<String, dynamic>? turnCredentials,
  }) async {
    final pendingKey = 'session:$realm';
    final pending = _pendingConnections[pendingKey];
    if (pending != null) {
      _log('join pending connect realm=$realm webrtc=$webRtcEnabled');
      return pending;
    }

    final future = _connectInternal(
      realm: realm,
      authId: authId,
      webRtcEnabled: webRtcEnabled,
      privateKey: privateKey,
      turnCredentials: turnCredentials,
    );
    _pendingConnections[pendingKey] = future;

    try {
      return await future;
    } finally {
      if (_pendingConnections[pendingKey] == future) {
        _pendingConnections.remove(pendingKey);
      }
    }
  }

  Future<DesktopConnection> _connectInternal({
    required String realm,
    required String authId,
    required bool webRtcEnabled,
    required String privateKey,
    Map<String, dynamic>? turnCredentials,
  }) async {
    final key = 'session:$realm';
    final existing = _connections[key];
    if (existing != null) {
      try {
        if (existing.session.isConnected()) {
          _log('reuse realm=$realm p2p=${existing.isP2P}');
          return existing;
        }
      } catch (_) {}
      _log('dropping disconnected cached session realm=$realm');
      await release(realm);
    }

    _log('connect start realm=$realm webrtcPreferred=$webRtcEnabled');

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
        _log('connect success realm=$realm transport=webrtc');
      } catch (e) {
        isP2P = false;
        _log('connect fallback realm=$realm webrtc_failed=$e');
      }
    }

    final connection = DesktopConnection(session: finalSession, isP2P: isP2P);
    _connections[key] = connection;
    _log('session cached realm=$realm p2p=$isP2P active=${_connections.length}');

    finalSession.onDisconnect(() {
      if (_connections[key] == connection) {
        _connections.remove(key);
        connection.isAgentOnline = false;
        _log('session disconnected realm=$realm active=${_connections.length}');
      }
    });

    return connection;
  }

  Future<void> release(String realm) async {
    final key = 'session:$realm';
    final connection = _connections.remove(key);
    if (connection != null) {
      _log('release realm=$realm p2p=${connection.isP2P} remaining=${_connections.length}');
      await connection.dispose();
    } else {
      _log('release realm=$realm skipped=no_session');
    }
  }

  Future<void> invalidateAll() async {
    final realms = _connections.keys
        .map((key) => key.startsWith('session:') ? key.substring('session:'.length) : key)
        .toList(growable: false);
    for (final realm in realms) {
      await release(realm);
    }
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) async {
    final cached = _turnCredentials;
    final expiry = _turnCredentialsExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      _log('turn cache hit');
      return cached;
    }
    _log('turn fetch start');
    final turnClient = WampClient();
    try {
      final session = await turnClient.connectCryptoSign(
        authId: authId,
        privateKey: privateKey,
        realm: DeskconnConfig.realm,
      );
      final result = await session.call('io.xconn.deskconn.coturn.credentials.create');
      final c = result.args[0] as Map<String, dynamic>;
      _log('turn fetch success');
      final creds = {
        'username': c['username'],
        'credential': c['credential'],
        'urls': c['urls'],
        'expires_at': c['expires_at'],
      };
      _turnCredentials = creds;
      final expiresAt = creds['expires_at'];
      _turnCredentialsExpiry = expiresAt is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000).subtract(const Duration(minutes: 1))
          : DateTime.now().add(const Duration(hours: 1));
      return creds;
    } finally {
      await turnClient.disconnect();
    }
  }
}
