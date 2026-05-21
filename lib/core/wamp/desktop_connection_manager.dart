import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

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
  final Map<String, Future<DesktopConnection>> _pendingConnections = {};
  bool _appInBackground = false;

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
    final pendingKey = 'session:$realm:${webRtcEnabled ? 'p2p' : 'routed'}';
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
      bool connected = false;
      try {
        connected = existing.session.isConnected();
      } catch (_) {}

      if (connected) {
        if (existing.isP2P == webRtcEnabled) {
          _log('reuse realm=$realm p2p=${existing.isP2P}');
          return existing;
        }
        _log('mode change realm=$realm oldP2p=${existing.isP2P} newWebrtc=$webRtcEnabled');
        await release(realm);
      } else {
        _log('dropping disconnected cached session realm=$realm');
        await release(realm);
      }
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
    unawaited(_syncBackgroundService());

    // Auto-remove from cache when the session drops (mirrors web app sessionCache pattern)
    finalSession.onDisconnect(() {
      if (_connections[key] == connection) {
        _connections.remove(key);
        _log('session disconnected realm=$realm active=${_connections.length}');
        unawaited(_syncBackgroundService());
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
    await _syncBackgroundService();
  }

  Future<void> invalidateAll() async {
    final realms = _connections.keys
        .map((key) => key.startsWith('session:') ? key.substring('session:'.length) : key)
        .toList(growable: false);
    for (final realm in realms) {
      await release(realm);
    }
  }

  void setAppInBackground(bool isBackground) {
    _appInBackground = isBackground;
    _log('app_background=$isBackground active=${_connections.length}');
    unawaited(_syncBackgroundService());
  }

  Future<void> _syncBackgroundService() {
    _log('service_sync active=${_connections.length} background=$_appInBackground');
    return syncDesktopSessionService(activeConnections: _connections.length, appInBackground: _appInBackground);
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) async {
    final cached = _turnCredentials;
    final expiry = _turnCredentialsExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      _log('turn cache hit');
      return cached;
    }
    _log('turn fetch start');
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
      _log('turn fetch success');
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
