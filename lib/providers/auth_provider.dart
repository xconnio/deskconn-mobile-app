import 'dart:async';

import 'package:flutter/material.dart';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/network/connectivity_service.dart';
import 'package:deskconn_mobile_app/core/operation_result.dart';
import 'package:deskconn_mobile_app/core/wamp/quic_connection_manager.dart';
import 'package:xconn/xconn.dart';

// The backend raises ApplicationError(uri, "human-readable message") for
// expected failures (email already registered, OTP invalid, etc.) — the
// message ends up in args[0] over the wire. Falling back to e.toString()
// instead leaks the raw wamp.error.* uri to the user.
String _describeAuthError(Object e) {
  if (!ConnectivityService().hasConnection) {
    return 'No internet connection. Check your Wi-Fi or mobile data.';
  }
  if (e is ApplicationError) {
    final args = e.args;
    if (args != null && args.isNotEmpty && args.first is String && (args.first as String).trim().isNotEmpty) {
      return args.first as String;
    }
  }
  if (e is TimeoutException) {
    return 'Request timed out. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

class AuthProvider extends ChangeNotifier {
  Session? _session;

  String? pendingEmail;
  String? _pendingPassword;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? get pendingPassword => _pendingPassword;

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
      return OperationResult.failure(_describeAuthError(e));
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
      return OperationResult.failure(_describeAuthError(e));
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
      return OperationResult.failure(_describeAuthError(e));
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
      return OperationResult.failure(_describeAuthError(e));
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
      return OperationResult.failure(_describeAuthError(e));
    }
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }
}
