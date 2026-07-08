import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

/// Forces every connection attempt through WebRTC even when the user has P2P
/// disabled in settings, and skips the routed fallback on failure. Useful to
/// flip back on temporarily when diagnosing WebRTC regressions in isolation.
const bool kForceWebRtcOnly = false;

class DesktopConnection {
  final Session session;
  final bool isP2P;
  bool isAgentOnline = false;

  // Session.onDisconnect is a single-callback setter, already claimed by the
  // manager for its own cache cleanup. UI code that wants to react to this
  // connection dying (e.g. to flip a status badge without waiting for the
  // user to pull-to-refresh) should set this instead of touching the session.
  void Function()? onDisconnected;

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
  // Realms whose agent doesn't expose the WebRTC offer procedure at all
  // (wamp.error.no_such_procedure). Only consulted when kForceWebRtcOnly is
  // on — with routed fallback restored, retrying these just costs one quick
  // failed attempt before falling back, not a hard failure.
  final Set<String> _noWebRtcSupportRealms = {};
  final Random _retryJitter = Random();

  Map<String, dynamic>? _turnCredentials;
  DateTime? _turnCredentialsExpiry;
  Future<Map<String, dynamic>>? _pendingTurnCredentials;

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

  // Call as early as possible (login/session-restore) so the TURN round-trip
  // is already paid for by the time the user reaches a desktop and triggers a
  // real connect. Safe to call repeatedly; errors are swallowed since this is
  // purely a warm-up — a real connect attempt will retry and surface failures.
  Future<void> prefetchTurnCredentials(String authId, String privateKey) async {
    try {
      await _getTurnCredentials(authId, privateKey);
    } catch (_) {}
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

    final willUseWebRtc = webRtcEnabled || kForceWebRtcOnly;

    if (willUseWebRtc && kForceWebRtcOnly && _noWebRtcSupportRealms.contains(realm)) {
      _log('connect skipped realm=$realm reason=known_no_webrtc_support');
      throw Exception('wamp.error.no_such_procedure (cached: desktop agent does not support WebRTC)');
    }

    _log('connect start realm=$realm webrtcPreferred=$webRtcEnabled');

    final client = WampClient();
    final signalingFuture = client.connectCryptoSignWithSerializer(
      authId: authId,
      privateKey: privateKey,
      realm: realm,
      serializer: CBORSerializer(),
    );
    // Fetch TURN credentials concurrently with the signaling connect instead of
    // after it — they're independent, so this takes it off the critical path.
    final turnFuture = (willUseWebRtc && turnCredentials == null) ? _getTurnCredentials(authId, privateKey) : null;
    // If signaling fails before we get to `await turnFuture!` below, don't let
    // this become an unhandled Future error.
    turnFuture?.ignore();

    final signalingSession = await signalingFuture;

    Session finalSession = signalingSession;
    bool isP2P = false;

    if (willUseWebRtc) {
      if (!kIsWeb) {
        try {
          if (Platform.isAndroid) {
            await Helper.setAndroidAudioConfiguration(
              AndroidAudioConfiguration(manageAudioFocus: false, androidAudioMode: AndroidAudioMode.normal),
            );
          } else if (Platform.isIOS) {
            await Helper.setAppleAudioConfiguration(
              AppleAudioConfiguration(
                appleAudioCategory: AppleAudioCategory.playback,
                appleAudioCategoryOptions: {AppleAudioCategoryOption.mixWithOthers},
              ),
            );
          }
        } catch (e) {
          debugPrint('Failed to configure WebRTC audio: $e');
        }
      }
      // A timed-out WAMP join over an already-open data channel is transient
      // transport flakiness (SCTP/ICE-timing), not a capability gap — retry
      // with a fresh offer/answer before giving up. no_such_procedure is a
      // permanent gap and is never worth retrying.
      //
      // Measured successful joins complete in well under 1.5s, so the first
      // few attempts use a short timeout to fail fast and retry quickly; the
      // final attempt uses a longer timeout in case it's just a one-off slow
      // network, then the whole cycle stops — no unbounded retries.
      const maxAttempts = 4;
      const shortTimeout = Duration(seconds: 4);
      const finalTimeout = Duration(seconds: 10);
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final timeout = attempt < maxAttempts ? shortTimeout : finalTimeout;
        try {
          final credentials = turnCredentials ?? await turnFuture!;

          final config = web_rtc.ClientConfig(
            realm: realm,
            procedureWebRTCOffer: 'io.xconn.webrtc.offer',
            topicAnswererOnCandidate: 'io.xconn.webrtc.answerer.on_candidate',
            topicOffererOnCandidate: 'io.xconn.webrtc.offerer.on_candidate',
            iceServers: [
              {'urls': 'stun:stun.l.google.com:19302'},
              {
                'urls': credentials['urls'],
                'username': credentials['username'],
                'credential': credentials['credential'],
              },
            ],
            serializer: CBORSerializer(),
            session: signalingSession,
            authenticator: CryptoSignAuthenticator(authId, privateKey),
          );

          finalSession = await web_rtc.connectWAMP(config).timeout(timeout);
          isP2P = true;
          lastError = null;
          _log('connect success realm=$realm transport=webrtc attempt=$attempt');
          break;
        } catch (e) {
          lastError = e;
          if (e.toString().contains('wamp.error.no_such_procedure')) {
            _noWebRtcSupportRealms.add(realm);
            break;
          }
          if (e is TimeoutException && attempt < maxAttempts) {
            // Linear backoff plus jitter so repeated failures (e.g. a TURN
            // server that's down for everyone) don't hammer signaling/TURN
            // back-to-back across many devices retrying in lockstep.
            final backoff = Duration(milliseconds: 300 * attempt + _retryJitter.nextInt(300));
            _log('connect retry realm=$realm attempt=$attempt timeout=$timeout backoff=$backoff reason=$e');
            await Future.delayed(backoff);
            continue;
          }
          break;
        }
      }

      if (lastError != null) {
        if (kForceWebRtcOnly) {
          _log('connect failed realm=$realm webrtc_failed=$lastError (routed fallback disabled)');
          try {
            await signalingSession.close();
          } catch (_) {}
          throw lastError;
        }
        isP2P = false;
        _log('connect fallback realm=$realm webrtc_failed=$lastError');
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
      connection.onDisconnected?.call();
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
    _noWebRtcSupportRealms.clear();
  }

  Future<Map<String, dynamic>> _getTurnCredentials(String authId, String privateKey) {
    final cached = _turnCredentials;
    final expiry = _turnCredentialsExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      _log('turn cache hit');
      return Future.value(cached);
    }

    final pending = _pendingTurnCredentials;
    if (pending != null) {
      _log('turn join pending fetch');
      return pending;
    }

    final future = _fetchTurnCredentials(authId, privateKey);
    _pendingTurnCredentials = future;
    return future.whenComplete(() {
      if (_pendingTurnCredentials == future) {
        _pendingTurnCredentials = null;
      }
    });
  }

  Future<Map<String, dynamic>> _fetchTurnCredentials(String authId, String privateKey) async {
    _log('turn fetch start');
    final turnClient = WampClient();
    try {
      final session = await turnClient.connectCryptoSign(
        authId: authId,
        privateKey: privateKey,
        realm: DeskconnConfig.realm,
      );
      final result = await session
          .call('io.xconn.deskconn.coturn.credentials.create')
          .timeout(DeskconnConfig.callTimeout);
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
