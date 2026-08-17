import 'package:flutter/material.dart';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/wamp/quic_connection_manager.dart';
import 'package:xconn/xconn.dart';

class AuthProvider extends ChangeNotifier {
  Session? _session;

  String? pendingEmail;
  String? _pendingPassword;
  String? error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? get pendingPassword => _pendingPassword;

  void clearError() {
    error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<Session> _getSession() async {
    if (_session == null || !_session!.isConnected()) {
      _session = await QUICConnectionManager().openSession(
        DeskconnConfig.realm,
        QUICDialerConfig(authenticator: AnonymousAuthenticator(DeskconnConfig.serviceAuthId)),
      );
    }
    return _session!;
  }

  Future<bool> createAccount({required String email, required String name, required String password}) async {
    error = null;
    _setLoading(true);

    try {
      var session = await _getSession();
      await session
          .call("io.xconn.deskconn.account.create", args: [email, name, password])
          .timeout(DeskconnConfig.callTimeout);

      pendingEmail = email;
      _pendingPassword = password;

      _setLoading(false);
      return true;
    } catch (e) {
      error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    if (pendingEmail == null) {
      error = "No pending verification";
      notifyListeners();
      return false;
    }

    error = null;
    notifyListeners();

    try {
      var session = await _getSession();
      await session
          .call("io.xconn.deskconn.account.verify", args: [pendingEmail, otp])
          .timeout(DeskconnConfig.callTimeout);

      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> resendOtp() async {
    if (pendingEmail == null) return;

    try {
      var session = await _getSession();
      await session
          .call("io.xconn.deskconn.account.otp.resend", args: [pendingEmail])
          .timeout(DeskconnConfig.callTimeout);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    error = null;
    notifyListeners();

    try {
      var session = await _getSession();
      await session
          .call("io.xconn.deskconn.account.password.forget", args: [email])
          .timeout(DeskconnConfig.callTimeout);

      pendingEmail = email;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword({required String otp, required String newPassword}) async {
    if (pendingEmail == null) {
      error = "No pending password reset";
      notifyListeners();
      return false;
    }

    error = null;
    notifyListeners();

    try {
      var session = await _getSession();
      await session
          .call("io.xconn.deskconn.account.password.reset", args: [pendingEmail, newPassword, otp])
          .timeout(DeskconnConfig.callTimeout);

      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }
}
