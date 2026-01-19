import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  final _client = WampClient();

  String? pendingEmail;
  String? _pendingPassword;
  String? error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? get pendingPassword => _pendingPassword;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<bool> createAccount({
    required String email,
    required String name,
    required String role,
    required String password,
  }) async {
    error = null;
    _setLoading(true);

    try {
      await _client.connectCryptoSign();

      await _client.session.call(
        "io.xconn.deskconn.account.create",
        args: [email, name, role, password],
      );

      pendingEmail = email;
      _pendingPassword = password;

      await _client.disconnect();
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
      await _client.connectCryptoSign();

      await _client.session.call(
        "io.xconn.deskconn.account.verify",
        args: [pendingEmail, otp],
      );

      await _client.disconnect();
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
      await _client.connectCryptoSign();

      await _client.session.call(
        "io.xconn.deskconn.account.otp.resend",
        args: [pendingEmail],
      );

      await _client.disconnect();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    error = null;
    notifyListeners();

    try {
      await _client.connectCryptoSign();

      await _client.session.call(
        "io.xconn.deskconn.account.password.forget",
        args: [email],
      );

      pendingEmail = email;
      await _client.disconnect();
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword({
    required String otp,
    required String newPassword,
  }) async {
    if (pendingEmail == null) {
      error = "No pending password reset";
      notifyListeners();
      return false;
    }

    error = null;
    notifyListeners();

    try {
      await _client.connectCryptoSign();

      await _client.session.call(
        "io.xconn.deskconn.account.password.reset",
        args: [
          pendingEmail,
          newPassword,
          otp,
        ],
      );

      await _client.disconnect();
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

}
