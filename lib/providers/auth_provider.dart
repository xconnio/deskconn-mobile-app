import 'package:flutter/material.dart';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/operation_result.dart';
import 'package:deskconn_mobile_app/core/wamp/quic_connection_manager.dart';
import 'package:xconn/xconn.dart';

class AuthProvider extends ChangeNotifier {
  Session? _session;

  String? pendingEmail;
  String? _pendingPassword;
  String? get pendingPassword => _pendingPassword;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<Session> _getSession() async {
    if (_session == null || !_session!.isConnected()) {
      _session = await QUICConnectionManager().openSession(
        DeskconnConfig.realm,
        QUICDialerConfig(
          authenticator: CryptoSignAuthenticator(DeskconnConfig.mobileAppAuthID, DeskconnConfig.servicePrivateKey),
        ),
      );
    }
    return _session!;
  }

  Future<OperationResult> createAccount({required String email, required String name, required String password}) async {
    _setLoading(true);

    try {
      var session = await _getSession();
      await session
          .call(DeskconnProcedures.accountCreate, args: [email, name, password])
          .timeout(DeskconnConfig.callTimeout);

      pendingEmail = email;
      _pendingPassword = password;

      return const OperationResult.success();
    } catch (e) {
      return OperationResult.failure(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<OperationResult> verifyOtp(String otp) async {
    if (pendingEmail == null) {
      return const OperationResult.failure("No pending verification");
    }

    try {
      var session = await _getSession();
      await session
          .call(DeskconnProcedures.accountVerify, args: [pendingEmail, otp])
          .timeout(DeskconnConfig.callTimeout);

      return const OperationResult.success();
    } catch (e) {
      return OperationResult.failure(e.toString());
    }
  }

  Future<OperationResult> resendOtp() async {
    if (pendingEmail == null) {
      return const OperationResult.failure("No pending verification");
    }

    try {
      var session = await _getSession();
      await session.call(DeskconnProcedures.accountOtpResend, args: [pendingEmail]).timeout(DeskconnConfig.callTimeout);
      return const OperationResult.success();
    } catch (e) {
      return OperationResult.failure(e.toString());
    }
  }

  Future<OperationResult> requestPasswordReset(String email) async {
    try {
      var session = await _getSession();
      await session.call(DeskconnProcedures.accountPasswordForget, args: [email]).timeout(DeskconnConfig.callTimeout);

      pendingEmail = email;
      notifyListeners();
      return const OperationResult.success();
    } catch (e) {
      return OperationResult.failure(e.toString());
    }
  }

  Future<OperationResult> resetPassword({required String otp, required String newPassword}) async {
    if (pendingEmail == null) {
      return const OperationResult.failure("No pending password reset");
    }

    try {
      var session = await _getSession();
      await session
          .call(DeskconnProcedures.accountPasswordReset, args: [pendingEmail, newPassword, otp])
          .timeout(DeskconnConfig.callTimeout);

      return const OperationResult.success();
    } catch (e) {
      return OperationResult.failure(e.toString());
    }
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }
}
