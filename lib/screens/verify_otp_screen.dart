import 'package:deskconn_mobile_app/core/auth/otp_resend_cooldown.dart';
import 'package:deskconn_mobile_app/core/errors/deskconn_error_messages.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/widgets/app_snack_bar.dart';
import 'package:deskconn_mobile_app/widgets/auth_card_layout.dart';
import 'package:deskconn_mobile_app/widgets/otp_code_field.dart';
import 'package:deskconn_mobile_app/widgets/otp_resend_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final otpCtrl = TextEditingController();
  final otpFocus = FocusNode();
  final _resendCooldown = OtpResendCooldown();

  bool _loading = false;
  bool _resending = false;

  bool get _canVerify => !_loading && !_resending && otpCtrl.text.length == 6;
  bool get _canResend => !_loading && !_resending && _resendCooldown.canResend;

  @override
  void initState() {
    super.initState();
    _resendCooldown.start(onChanged: _refreshCooldown, notifyImmediately: false);
  }

  @override
  void dispose() {
    _resendCooldown.dispose();
    otpCtrl.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  void _refreshCooldown() {
    if (mounted) setState(() {});
  }

  Future<void> _verify() async {
    if (!_canVerify) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
    });

    try {
      final auth = context.read<AuthProvider>();
      final email = auth.pendingEmail;
      if (email == null) {
        setState(() {
          _loading = false;
        });
        AppSnackBar.showError(context, DeskconnErrorMessages.verificationSessionExpired);
        return;
      }

      final keys = await DeviceIdentity.ensureKeyPair();
      final result = await auth.verifyOtp(otpCtrl.text.trim(), publicKey: keys['publicKey']!);

      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          _loading = false;
        });
        AppSnackBar.showError(context, result.error ?? DeskconnErrorMessages.verificationFailed);
        return;
      }

      final principal = result.principal;
      if (principal == null) {
        setState(() {
          _loading = false;
        });
        AppSnackBar.showError(context, DeskconnErrorMessages.verificationSignInNotInitialized);
        return;
      }

      final signInResult = await context.read<SessionProvider>().completeRegistrationSignIn(
        email: email,
        keys: keys,
        principal: principal,
      );

      if (!mounted) return;

      if (!signInResult.isSuccess) {
        setState(() {
          _loading = false;
        });
        AppSnackBar.showError(context, signInResult.error ?? DeskconnErrorMessages.verificationSignInFailed);
        return;
      }

      auth.clearPendingVerification();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DesktopListScreen()), (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      AppSnackBar.showError(context, DeskconnErrorMessages.verificationFailed);
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() {
      _resending = true;
    });

    final result = await context.read<AuthProvider>().resendOtp();

    if (!mounted) return;

    setState(() {
      _resending = false;
    });

    if (result.isSuccess) {
      otpCtrl.clear();
      _resendCooldown.start(onChanged: _refreshCooldown);
    } else {
      AppSnackBar.showError(context, result.error ?? DeskconnErrorMessages.resendVerificationCodeFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingEmail = context.select<AuthProvider, String?>((auth) => auth.pendingEmail);
    final instruction = pendingEmail == null
        ? 'Enter the 6-digit code sent to your email'
        : 'Enter the 6-digit code sent to $pendingEmail';

    return Scaffold(
      appBar: AppBar(title: const Text('Verify email')),
      body: AuthCardLayout(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(instruction, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OtpCodeField(
              controller: otpCtrl,
              focusNode: otpFocus,
              enabled: !_loading && !_resending,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              ElevatedButton(onPressed: _canVerify ? _verify : null, child: const Text('Verify')),
            const SizedBox(height: 12),
            OtpResendButton(
              label: _resendCooldown.label,
              isLoading: _resending,
              onPressed: _canResend ? _resendCode : null,
            ),
          ],
        ),
      ),
    );
  }
}
