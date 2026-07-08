import 'dart:async';
import 'dart:io';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/cryptosign_keys.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionProvider extends ChangeNotifier {
  final _client = WampClient();

  Session? session;
  Map<String, dynamic>? account;
  String? error;

  Future<Session>? _reconnecting;

  // Lazily reconnects the account session using the stored device identity —
  // mirrors AuthProvider._getSession()'s pattern. Without this, a dropped
  // connection (network blip, server restart) left every account-level call
  // failing silently until the user logged out and back in.
  Future<Session> _ensureSession() {
    final current = session;
    if (current != null && current.isConnected()) return Future.value(current);
    return _reconnecting ??= _reconnect().whenComplete(() => _reconnecting = null);
  }

  Future<Session> _reconnect() async {
    final privateKey = await DeviceIdentity.privateKey();
    final email = await DeviceIdentity.lastEmail();
    if (privateKey == null || email == null) {
      throw Exception('No stored credentials to reconnect with');
    }

    final newSession = await _client.connectCryptoSign(
      authId: email,
      privateKey: privateKey,
      realm: DeskconnConfig.realm,
    );
    session = newSession;
    notifyListeners();
    return newSession;
  }

  List<Map<String, dynamic>> organizations = [];
  List<Map<String, dynamic>> invitationsInbox = [];
  List<Map<String, dynamic>> invitationsOutbox = [];

  bool _isLoading = false;
  bool loggedIn = false;

  bool get isLoading => _isLoading;

  bool orgLoading = false;
  bool invitationLoading = false;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void updateAccount(Map<String, dynamic> newAccountData) {
    account = newAccountData;
    notifyListeners();
  }

  List<Map<String, dynamic>> desktops = [];
  bool desktopsLoading = false;

  Future<void> login(String email, String password) async {
    error = null;
    _setLoading(true);

    try {
      session = await _client.connectCra(email: email, password: password, realm: DeskconnConfig.realm);

      final res = await session!.call("io.xconn.deskconn.account.get").timeout(DeskconnConfig.callTimeout);

      if (res.args.isEmpty) {
        throw Exception("Empty account response");
      }

      account = Map<String, dynamic>.from(res.args[0]);

      await Future.wait([loadDesktops(), loadOrganizations(), loadInvitations(), _registerDevice(email)]);

      // Device's cryptosign key only exists once _registerDevice above completes.
      final privateKey = await DeviceIdentity.privateKey();
      if (privateKey != null) {
        unawaited(DesktopConnectionManager().prefetchTurnCredentials(email, privateKey));
      }

      loggedIn = true;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      session = null;
      account = null;
      desktops.clear();
      loggedIn = false;

      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> initialize() async {
    _setLoading(true);

    try {
      final hasIdentity = await DeviceIdentity.exists();

      if (!hasIdentity) {
        loggedIn = false;
      } else {
        final privateKey = await DeviceIdentity.privateKey();
        final email = await DeviceIdentity.lastEmail();

        if (privateKey != null && email != null) {
          session = await _client.connectCryptoSign(authId: email, privateKey: privateKey, realm: DeskconnConfig.realm);

          final res = await session!.call("io.xconn.deskconn.account.get").timeout(DeskconnConfig.callTimeout);
          if (res.args.isEmpty) throw Exception("Empty account");

          account = Map<String, dynamic>.from(res.args[0]);

          unawaited(DesktopConnectionManager().prefetchTurnCredentials(email, privateKey));
          await Future.wait([loadDesktops(), loadOrganizations(), loadInvitations()]);

          loggedIn = true;
        } else {
          loggedIn = false;
        }
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      session = null;
      account = null;
      desktops.clear();
      loggedIn = false;
    }

    _setLoading(false);
  }

  Future<void> loadDesktops() async {
    if (session == null) return;

    desktopsLoading = true;
    notifyListeners();

    try {
      final s = await _ensureSession();
      final res = await s.call("io.xconn.deskconn.desktop.list").timeout(DeskconnConfig.callTimeout);
      desktops = List<Map<String, dynamic>>.from(res.args);
    } catch (e) {
      error = "Failed to load desktops";
    } finally {
      desktopsLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await DesktopConnectionManager().invalidateAll();

    try {
      final identity = await DeviceIdentity.deviceId();
      if (identity != null) {
        try {
          await session?.call('io.xconn.deskconn.device.delete', args: [identity]).timeout(DeskconnConfig.callTimeout);
        } catch (_) {}
      }
      await session?.close();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await DeviceIdentity.clear();

    session = null;
    account = null;
    desktops.clear();
    organizations.clear();
    invitationsInbox.clear();
    invitationsOutbox.clear();

    loggedIn = false;
    _setLoading(false);

    notifyListeners();
  }

  Future<void> _registerDevice(String email) async {
    if (session == null) {
      throw Exception('Session is not initialized');
    }

    try {
      final hasIdentity = await DeviceIdentity.exists();
      if (hasIdentity) {
        final lastEmail = await DeviceIdentity.lastEmail();
        if (lastEmail == email) {
          return;
        }
      }

      final privateKeyHex = await CryptoSignKeys.generatePrivateKey();
      final publicKeyHex = await CryptoSignKeys.derivePublicKey(privateKeyHex);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = DateTime.now().microsecondsSinceEpoch;
      final deviceName = 'android-$timestamp-$randomSuffix';
      final deviceModel = await _getDeviceModel();

      final res = await session!
          .call('io.xconn.deskconn.device.create', args: [deviceName, publicKeyHex])
          .timeout(DeskconnConfig.callTimeout);

      if (res.args.isEmpty) {
        throw Exception('Device registration failed: empty response');
      }

      final resultData = res.args[0] as Map<String, dynamic>;
      final deviceId = resultData['device_id'] ?? resultData['id'];

      if (deviceId == null) {
        throw Exception('Device ID not found in response');
      }

      await DeviceIdentity.clear();

      await DeviceIdentity.save(
        deviceId: deviceId,
        privateKey: privateKeyHex,
        publicKey: publicKeyHex,
        email: email,
        deviceName: deviceName,
        deviceModel: deviceModel,
      );
    } catch (e) {
      error = 'Device registration failed: $e';
    }
  }

  Future<String> _getDeviceModel() async {
    final deviceInfoPlugin = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        return iosInfo.model;
      }
    } catch (e) {
      error = "Error getting device model";
    }

    return Platform.operatingSystem;
  }

  Future<void> loadOrganizations() async {
    if (session == null) return;

    orgLoading = true;
    notifyListeners();

    try {
      final s = await _ensureSession();
      final res = await s.call("io.xconn.deskconn.organization.list").timeout(DeskconnConfig.callTimeout);

      organizations = List<Map<String, dynamic>>.from(res.args);
    } catch (_) {
      error = "Failed to load organizations";
    }

    orgLoading = false;
    notifyListeners();
  }

  Future<void> loadInvitations() async {
    if (session == null) return;

    invitationLoading = true;
    notifyListeners();

    try {
      final s = await _ensureSession();
      final inboxRes = await s
          .call("io.xconn.deskconn.organization.invitation.inbox.list")
          .timeout(DeskconnConfig.callTimeout);

      final outboxRes = await s
          .call("io.xconn.deskconn.organization.invitation.outbox.list")
          .timeout(DeskconnConfig.callTimeout);

      invitationsInbox = List<Map<String, dynamic>>.from(inboxRes.args);

      invitationsOutbox = List<Map<String, dynamic>>.from(outboxRes.args);
    } catch (_) {
      error = "Failed to load invitations";
    }

    invitationLoading = false;
    notifyListeners();
  }

  Future<void> respondInvitation(String invitationId, String action) async {
    try {
      final s = await _ensureSession();
      await s
          .call("io.xconn.deskconn.organization.invitation.respond", args: [invitationId, action])
          .timeout(DeskconnConfig.callTimeout);

      await loadInvitations();
      await loadOrganizations();
    } catch (_) {
      error = "Failed to respond to invitation";
      notifyListeners();
    }
  }

  Future<void> createInvitation(String orgId, String email, String role) async {
    try {
      final s = await _ensureSession();
      await s
          .call("io.xconn.deskconn.organization.invitation.create", args: [orgId, email, role])
          .timeout(DeskconnConfig.callTimeout);

      await loadInvitations();
    } catch (_) {
      error = "Failed to create invitation";
      notifyListeners();
    }
  }
}
