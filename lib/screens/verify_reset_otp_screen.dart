import 'package:deskconn_mobile_app/core/auth/otp_resend_cooldown.dart';
import 'package:deskconn_mobile_app/core/errors/deskconn_error_messages.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/screens/reset_password_screen.dart';
import 'package:deskconn_mobile_app/widgets/app_snack_bar.dart';
import 'package:deskconn_mobile_app/widgets/auth_card_layout.dart';
import 'package:deskconn_mobile_app/widgets/otp_code_field.dart';
import 'package:deskconn_mobile_app/widgets/otp_resend_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VerifyResetOtpScreen extends StatefulWidget {
  const VerifyResetOtpScreen({super.key});

  @override
  State<VerifyResetOtpScreen> createState() => _VerifyResetOtpScreenState();
}

class _VerifyResetOtpScreenState extends State<VerifyResetOtpScreen> {
  final otpCtrl = TextEditingController();
  final otpFocus = FocusNode();
  final _resendCooldown = OtpResendCooldown();

  bool _resending = false;

  bool get _canVerify => !_resending && otpCtrl.text.length == 6;
  bool get _canResend => !_resending && _resendCooldown.canResend;

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

  void _verify() {
    if (!_canVerify) return;

    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordScreen(otp: otpCtrl.text.trim())));
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    final auth = context.read<AuthProvider>();
    final email = auth.pendingEmail;
    if (email == null) {
      AppSnackBar.showError(context, DeskconnErrorMessages.pendingPasswordResetMissing);
      return;
    }

    setState(() {
      _resending = true;
    });

    final result = await auth.requestPasswordReset(email);

    if (!mounted) return;

    setState(() {
      _resending = false;
    });

    if (result.isSuccess) {
      otpCtrl.clear();
      _resendCooldown.start(onChanged: _refreshCooldown);
    } else {
      AppSnackBar.showError(context, result.error ?? DeskconnErrorMessages.resetCodeSendFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify reset code')),
      body: AuthCardLayout(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter the 6-digit reset code sent to your email', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OtpCodeField(
              controller: otpCtrl,
              focusNode: otpFocus,
              enabled: !_resending,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
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
