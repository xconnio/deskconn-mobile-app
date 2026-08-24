import 'dart:async';
import 'dart:io';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/operation_result.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/wamp/quic_connection_manager.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionProvider extends ChangeNotifier {
  final _client = WampClient();

  Session? session;
  Session? _loginSession;
  Map<String, dynamic>? account;
  String? error;

  Future<Session>? _reconnecting;

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

  bool _isLoading = false;
  bool loggedIn = false;

  bool get isLoading => _isLoading;

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

  Future<Session> _openLoginSession({required String email, required String password}) async {
    await _loginSession?.close();
    _loginSession = await _client.connectCra(email: email, password: password, realm: DeskconnConfig.realm);
    return _loginSession!;
  }

  Future<OperationResult> requestLoginOtp(String email, String password) async {
    error = null;
    _setLoading(true);

    try {
      final authSession = await _openLoginSession(email: email, password: password);
      debugPrint(
        'Login OTP request: procedure=${DeskconnProcedures.accountLogin}, '
        'authMethod=wampcra, authId=$email',
      );
      await authSession.call(DeskconnProcedures.accountLogin, args: [email]).timeout(DeskconnConfig.callTimeout);
      debugPrint('Login OTP request succeeded for email=$email');

      return const OperationResult.success();
    } catch (e) {
      debugPrint('Login OTP request failed for email=$email: $e');
      await _loginSession?.close();
      _loginSession = null;
      return OperationResult.failure(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<OperationResult> verifyLoginOtp({required String email, required String otp}) async {
    error = null;
    _setLoading(true);

    try {
      final keys = await DeviceIdentity.ensureKeyPair();
      final authSession = _loginSession;
      if (authSession == null || !authSession.isConnected()) {
        throw Exception('Sign-in session expired. Please sign in again.');
      }

      final publicKey = keys['publicKey']!;

      debugPrint(
        'Login OTP verify: procedure=${DeskconnProcedures.accountLoginVerify}, '
        'authMethod=wampcra, authId=$email, email=$email, '
        'otpLength=${otp.length}, publicKey=${_shortKey(publicKey)}',
      );

      final principalRes = await authSession
          .call(DeskconnProcedures.accountLoginVerify, args: [email, otp, publicKey])
          .timeout(DeskconnConfig.callTimeout);

      if (principalRes.args.isEmpty) {
        throw Exception("Empty login verification response");
      }

      final principal = Map<String, dynamic>.from(principalRes.args[0] as Map);
      final principalId = principal['id']?.toString();
      debugPrint('Login OTP verify returned principalId=$principalId for email=$email');
      if (principalId == null || principalId.isEmpty) {
        throw Exception("Principal ID not found in response");
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = DateTime.now().microsecondsSinceEpoch;
      final deviceName = 'android-$timestamp-$randomSuffix';
      final deviceModel = await _getDeviceModel();

      await DeviceIdentity.save(
        deviceId: principalId,
        privateKey: keys['privateKey']!,
        publicKey: keys['publicKey']!,
        email: email,
        deviceName: deviceName,
        deviceModel: deviceModel,
      );

      await _loginSession?.close();
      _loginSession = null;

      session = await _client.connectCryptoSign(
        authId: email,
        privateKey: keys['privateKey']!,
        realm: DeskconnConfig.realm,
      );

      final accountRes = await session!.call(DeskconnProcedures.accountGet).timeout(DeskconnConfig.callTimeout);

      if (accountRes.args.isEmpty) {
        throw Exception("Empty account response");
      }

      account = Map<String, dynamic>.from(accountRes.args[0] as Map);

      await loadDesktops();

      loggedIn = true;
      debugPrint('Login OTP flow completed for email=$email');
      notifyListeners();
      return const OperationResult.success();
    } catch (e) {
      debugPrint('Login OTP verify failed for email=$email: $e');
      session = null;
      account = null;
      desktops.clear();
      loggedIn = false;

      notifyListeners();
      return OperationResult.failure(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  String _shortKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 6)}...${key.substring(key.length - 6)}';
  }

  Future<void> initialize() async {
    _setLoading(true);

    try {
      await DeviceIdentity.ensureKeyPair();
      final hasIdentity = await DeviceIdentity.exists();

      if (!hasIdentity) {
        loggedIn = false;
      } else {
        final privateKey = await DeviceIdentity.privateKey();
        final email = await DeviceIdentity.lastEmail();

        if (privateKey != null && email != null) {
          session = await _client.connectCryptoSign(authId: email, privateKey: privateKey, realm: DeskconnConfig.realm);

          final res = await session!.call(DeskconnProcedures.accountGet).timeout(DeskconnConfig.callTimeout);
          if (res.args.isEmpty) throw Exception("Empty account");

          account = Map<String, dynamic>.from(res.args[0] as Map);

          await loadDesktops();

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
      final res = await s.call(DeskconnProcedures.desktopList).timeout(DeskconnConfig.callTimeout);
      desktops = res.args.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      error = "Failed to load desktops";
    } finally {
      desktopsLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await DesktopConnectionManager().invalidateAll();
    } catch (_) {}

    try {
      final publicKey = await DeviceIdentity.publicKey();
      if (publicKey != null) {
        try {
          await session
              ?.call(DeskconnProcedures.accountPrincipalDelete, args: [publicKey])
              .timeout(DeskconnConfig.callTimeout);
        } catch (_) {}
      }
      await session?.close();
      await _loginSession?.close();
    } catch (_) {}

    try {
      await QUICConnectionManager().close();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    try {
      await DeviceIdentity.clear();
    } catch (_) {}

    session = null;
    _loginSession = null;
    account = null;
    desktops.clear();

    loggedIn = false;
    _setLoading(false);

    notifyListeners();
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
}
