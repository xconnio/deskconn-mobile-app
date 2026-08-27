import 'dart:async';

import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  static const _resendCooldown = Duration(minutes: 1);

  final otpCtrl = TextEditingController();
  final otpFocus = FocusNode();

  Timer? _resendTimer;
  int _resendSecondsRemaining = _resendCooldown.inSeconds;
  bool _loading = false;
  bool _resending = false;
  String? submitError;

  bool get _canVerify => !_loading && !_resending && otpCtrl.text.length == 6;
  bool get _canResend => !_loading && !_resending && _resendSecondsRemaining == 0;

  String get _resendLabel {
    if (_resendSecondsRemaining == 0) return 'Resend code';

    final minutes = _resendSecondsRemaining ~/ 60;
    final seconds = (_resendSecondsRemaining % 60).toString().padLeft(2, '0');
    return 'Resend code in $minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _startResendCooldown(notify: false);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    otpCtrl.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  void _startResendCooldown({bool notify = true}) {
    _resendTimer?.cancel();
    void resetCooldown() {
      _resendSecondsRemaining = _resendCooldown.inSeconds;
    }

    if (notify) {
      setState(resetCooldown);
    } else {
      resetCooldown();
    }

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _resendSecondsRemaining = 0;
        });
        return;
      }

      setState(() {
        _resendSecondsRemaining--;
      });
    });
  }

  Future<void> _verify() async {
    if (!_canVerify) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      submitError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final email = auth.pendingEmail;
      if (email == null) {
        setState(() {
          _loading = false;
          submitError = 'Verification session expired. Please create your account again.';
        });
        return;
      }

      final keys = await DeviceIdentity.ensureKeyPair();
      final result = await auth.verifyOtp(otpCtrl.text.trim(), publicKey: keys['publicKey']!);

      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          _loading = false;
          submitError = result.error ?? 'Verification failed. Please try again.';
        });
        return;
      }

      final principal = result.principal;
      if (principal == null) {
        setState(() {
          _loading = false;
          submitError = 'Verification completed, but sign-in could not be initialized.';
        });
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
          submitError = signInResult.error ?? 'Verification completed, but sign-in failed.';
        });
        return;
      }

      auth.clearPendingVerification();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DesktopListScreen()), (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        submitError = 'Verification failed. Please try again.';
      });
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() {
      _resending = true;
      submitError = null;
    });

    final result = await context.read<AuthProvider>().resendOtp();

    if (!mounted) return;

    setState(() {
      _resending = false;
      submitError = result.isSuccess ? null : result.error;
    });

    if (result.isSuccess) {
      _startResendCooldown();
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
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.48),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const DeskconnLogo(size: 48),
                const SizedBox(height: 12),
                Text('Deskconn', style: DeskconnTypography.title(context)),
                const SizedBox(height: 32),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(instruction, textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          OtpCodeField(
                            controller: otpCtrl,
                            focusNode: otpFocus,
                            enabled: !_loading && !_resending,
                            onChanged: (_) {
                              setState(() {
                                submitError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else
                            ElevatedButton(onPressed: _canVerify ? _verify : null, child: const Text('Verify')),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _canResend ? _resendCode : null,
                            child: _resending
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(_resendLabel),
                          ),
                          if (submitError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              submitError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
