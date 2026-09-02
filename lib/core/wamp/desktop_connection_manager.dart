import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/wamp/file_stream_server.dart';
import 'package:deskconn_mobile_app/core/wamp/file_stream_service.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';

const bool kForceWebRtcOnly = false;

class DesktopConnection {
  final Session session;
  final bool isP2P;
  final web_rtc.WebRTCSession? webRtcSession;
  bool isAgentOnline = false;

  // Reused across FileExplorerScreen instances for the same realm so a
  // screen reopen doesn't force a redundant key-exchange RPC on an already
  // key-exchanged, still-healthy session.
  FileExplorerController? explorerController;

  void Function()? onDisconnected;

  FileStreamServer? _fileStreamServer;

  // Only available when this connection is P2P (webRtcSession != null); lazily
  // created so a connection that never previews media never opens the server.
  FileStreamServer? get fileStreamServer {
    final rtc = webRtcSession;
    if (rtc == null) return null;
    return _fileStreamServer ??= FileStreamServer(FileStreamService(rtc));
  }

  DesktopConnection({required this.session, required this.isP2P, this.webRtcSession});

  Future<void> dispose() async {
    try {
      await session.close();
    } catch (_) {}
    try {
      await webRtcSession?.connection.dispose();
    } catch (_) {}
    await _fileStreamServer?.dispose();
  }
}

class DesktopConnectionManager {
  static final DesktopConnectionManager _instance = DesktopConnectionManager._();
  factory DesktopConnectionManager() => _instance;
  DesktopConnectionManager._();

  final Map<String, DesktopConnection> _connections = {};
  final Map<String, Future<DesktopConnection>> _pendingConnections = {};
  final Set<String> _noWebRtcSupportRealms = {};

  // A dropped connection immediately followed by a fresh WebRTC offer for
  // the same realm has been observed to hard-crash the app (native "Callback
  // invoked after it has been deleted" abort — see
  // xconn-webrtc-dart/BUG_REPORT_dispose_native_callback_abort.md), most
  // likely a lifecycle race between the old RTCPeerConnection's native
  // teardown and the new one's setup. This is a mitigation, not a verified
  // fix — it narrows the overlap window, it doesn't prove it's closed.
  static const _webRtcDisposeCooldown = Duration(milliseconds: 500);
  final Map<String, DateTime> _lastWebRtcDisposeAt = {};

  void _markWebRtcDisposed(String realm) {
    _lastWebRtcDisposeAt[realm] = DateTime.now();
  }

  Future<void> _awaitWebRtcDisposeCooldown(String realm) async {
    final lastDispose = _lastWebRtcDisposeAt[realm];
    if (lastDispose == null) return;
    final remaining = _webRtcDisposeCooldown - DateTime.now().difference(lastDispose);
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  void _log(String message) {
    debugPrint('[DesktopSession ${DateTime.now().toIso8601String()}] $message');
  }

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
  }) {
    _log('acquire realm=$realm webrtc=$webRtcEnabled');
    return connect(realm: realm, authId: authId, webRtcEnabled: webRtcEnabled, privateKey: privateKey);
  }

  Future<DesktopConnection> connect({
    required String realm,
    required String authId,
    required bool webRtcEnabled,
    required String privateKey,
  }) async {
    final pendingKey = 'session:$realm';
    final pending = _pendingConnections[pendingKey];
    if (pending != null) {
      _log('join pending connect realm=$realm webrtc=$webRtcEnabled');
      return pending;
    }

    final future = _connectInternal(realm: realm, authId: authId, webRtcEnabled: webRtcEnabled, privateKey: privateKey);
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
    final signalingSession = await signalingFuture;

    Session finalSession = signalingSession;
    bool isP2P = false;

    if (willUseWebRtc) {
      await _awaitWebRtcDisposeCooldown(realm);
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
      const connectTimeout = Duration(seconds: 20);
      Object? lastError;
      try {
        final config = web_rtc.ClientConfig(
          realm: realm,
          procedureWebRTCOffer: DeskconnProcedures.webrtcOffer,
          topicAnswererOnCandidate: DeskconnProcedures.webrtcAnswererOnCandidate,
          topicOffererOnCandidate: DeskconnProcedures.webrtcOffererOnCandidate,
          iceServers: [
            {'urls': 'stun:stun.l.google.com:19302'},
          ],
          serializer: CBORSerializer(),
          session: signalingSession,
          authenticator: CryptoSignAuthenticator(authId, privateKey),
        );

        final connection = await _connectWampWithWebRTC(config).timeout(connectTimeout);
        finalSession = connection.session;
        isP2P = true;
        _connections[key] = DesktopConnection(
          session: finalSession,
          isP2P: isP2P,
          webRtcSession: connection.webRtcSession,
        );
        _log('connect success realm=$realm transport=webrtc');
      } catch (e) {
        lastError = e;
        if (e.toString().contains('wamp.error.no_such_procedure')) {
          _noWebRtcSupportRealms.add(realm);
        }
      }

      if (lastError != null) {
        _log('connect failed realm=$realm webrtc_failed=$lastError (routed fallback requires explicit retry)');
        try {
          await signalingSession.close();
        } catch (_) {}
        throw lastError;
      }
    }

    final connection = _connections[key] ?? DesktopConnection(session: finalSession, isP2P: isP2P);
    _connections[key] = connection;
    _log('session cached realm=$realm p2p=$isP2P active=${_connections.length}');

    finalSession.onDisconnect(() {
      // Only treat this as an unexpected drop (and notify the listening
      // screen) if the connection was still the manager's active entry.
      // A deliberate release() already removed it from the cache before
      // closing the session, so this fires from that close() call too —
      // without this guard, that self-triggered "disconnect" would race
      // the caller's own reconnect (e.g. release() -> switching to routed)
      // with a second, independent reconnect using stale preferences.
      if (_connections[key] == connection) {
        _connections.remove(key);
        connection.isAgentOnline = false;
        if (connection.isP2P) _markWebRtcDisposed(realm);
        unawaited(connection.dispose());
        _log('session disconnected realm=$realm active=${_connections.length}');
        connection.onDisconnected?.call();
      }
    });

    return connection;
  }

  Future<void> release(String realm) async {
    final key = 'session:$realm';
    final connection = _connections.remove(key);
    if (connection != null) {
      _log('release realm=$realm p2p=${connection.isP2P} remaining=${_connections.length}');
      if (connection.isP2P) _markWebRtcDisposed(realm);
      await connection.dispose();
    } else {
      _log('release realm=$realm skipped=no_session');
    }
  }

  // get()'s own isConnected() check can lag well behind a connection
  // actually being unusable (WebRTC's failure detection can take over a
  // minute — see webrtc-dispose-cooldown's bug report), so a screen can
  // still be handed a cached session that fails every call. A timed-out
  // call is treated as just as dead as a closed one, otherwise every
  // retry on this realm keeps reusing the same zombie session forever.
  bool isDeadSessionError(Session session, Object error) {
    return !(session.isConnected() && error is! TimeoutException);
  }

  // Screens hitting a dead cached session (see isDeadSessionError) call
  // this instead of release()+acquire() separately, so the recovery step
  // is one call site instead of duplicated per screen.
  Future<DesktopConnection> reacquire({
    required String realm,
    required String authId,
    required String privateKey,
    required bool webRtcEnabled,
  }) async {
    await release(realm);
    return acquire(realm: realm, authId: authId, privateKey: privateKey, webRtcEnabled: webRtcEnabled);
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
}

class _WampWebRTCConnection {
  final Session session;
  final web_rtc.WebRTCSession webRtcSession;

  const _WampWebRTCConnection({required this.session, required this.webRtcSession});
}

class _PendingRemoteCandidate {
  final String requestID;
  final RTCIceCandidate candidate;

  const _PendingRemoteCandidate(this.requestID, this.candidate);
}

Future<_WampWebRTCConnection> _connectWampWithWebRTC(web_rtc.ClientConfig config) async {
  config.validate();

  final offerer = web_rtc.Offerer();
  var requestID = '';
  final pendingCandidates = <_PendingRemoteCandidate>[];

  final offerConfig = web_rtc.OfferConfig(
    protocol: 'wamp.2.cbor',
    iceServers: config.iceServers!,
    ordered: true,
    id: 0,
    topicAnswererOnCandidate: config.topicAnswererOnCandidate,
    additionalChannels: fileStreamChannelLabels(),
  );

  final offerFuture = offerer.offer(offerConfig);
  final subscription = await config.session.subscribe(config.topicOffererOnCandidate, (Event event) async {
    if (event.args.length < 2) return;

    final candidateRequestID = event.args[0] as String?;
    if (candidateRequestID == null) return;

    final candidateMap = jsonDecode(event.args[1] as String) as Map<String, dynamic>;
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String?,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );

    if (requestID.isEmpty) {
      pendingCandidates.add(_PendingRemoteCandidate(candidateRequestID, candidate));
      return;
    }
    if (candidateRequestID != requestID) return;

    try {
      await offerer.addICECandidate(candidate);
    } catch (e) {
      debugPrint('Failed to add WebRTC ICE candidate: $e');
    }
  });

  try {
    final offer = await offerFuture;
    final callResponse = await config.session.call(config.procedureWebRTCOffer, args: [jsonEncode(offer)]);
    final offerResponse = web_rtc.OfferResponse.fromJson(jsonDecode(callResponse.args[0] as String));

    if (offerResponse.requestID.isEmpty) {
      throw Exception('offer response request ID must not be empty');
    }
    requestID = offerResponse.requestID;

    final buffered = List<_PendingRemoteCandidate>.from(pendingCandidates);
    pendingCandidates.clear();
    for (final pending in buffered) {
      if (pending.requestID != requestID) continue;
      try {
        await offerer.addICECandidate(pending.candidate);
      } catch (e) {
        debugPrint('Failed to add buffered WebRTC ICE candidate: $e');
      }
    }

    offerer.startICETrickle(config.session, offerConfig.topicAnswererOnCandidate, requestID);
    await offerer.handleAnswer(offerResponse.answer);
    final channel = await offerer.waitReady().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('WebRTC data channel did not open', const Duration(seconds: 20)),
    );

    final webRtcSession = web_rtc.WebRTCSession(
      connection: offerer.connection!,
      channel: channel,
      incomingChannels: offerer.incomingChannels,
      extraChannel: offerer.extraChannel,
    );
    final base = await joinPeer(web_rtc.WebRTCPeer(channel), config.realm, config.serializer!, config.authenticator!);
    return _WampWebRTCConnection(session: Session(base), webRtcSession: webRtcSession);
  } catch (_) {
    await offerer.connection?.dispose();
    rethrow;
  } finally {
    unawaited(subscription.unsubscribe());
  }
}
