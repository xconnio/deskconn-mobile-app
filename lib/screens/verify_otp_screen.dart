import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/validators.dart';
import 'package:deskconn_mobile_app/screens/dashboard_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final otpCtrl = TextEditingController();
  bool _loading = false;

  String? requiredError;
  String? submitError;

  @override
  void dispose() {
    otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
        appBar: AppBar(title: const Text("Verify email")),
        body: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeskconnUI.cardRadius)),
            child: SizedBox(
              width: DeskconnUI.cardWidth,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DeskconnLogo(),
                    const SizedBox(height: 16),

                    const Text("Enter the 6-digit code sent to your email", textAlign: TextAlign.center),

                    const SizedBox(height: 16),

                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      enabled: !_loading,
                      onChanged: (v) {
                        if (requiredError != null) {
                          setState(() {
                            requiredError = null;
                            submitError = null;
                          });
                        } else if (submitError != null) {
                          setState(() => submitError = null);
                        }
                      },
                      decoration: InputDecoration(labelText: 'OTP', errorText: requiredError),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() {
                                requiredError = Validators.otp(otpCtrl.text);
                                submitError = null;
                              });

                              if (requiredError != null) return;

                              FocusScope.of(context).unfocus();

                              setState(() {
                                _loading = true;
                              });

                              try {
                                final result = await auth.verifyOtp(otpCtrl.text.trim());

                                if (!context.mounted) return;

                                if (result.isSuccess) {
                                  final email = auth.pendingEmail;
                                  final password = auth.pendingPassword;

                                  if (email == null || password == null) {
                                    setState(() {
                                      _loading = false;
                                    });
                                    return;
                                  }

                                  final loginResult = await context.read<SessionProvider>().login(email, password);

                                  if (!context.mounted) return;

                                  if (loginResult.isSuccess) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(builder: (_) => const DashboardScreen()),
                                      (_) => false,
                                    );
                                  } else {
                                    setState(() {
                                      _loading = false;
                                      submitError = loginResult.error;
                                    });
                                  }
                                } else {
                                  setState(() {
                                    _loading = false;
                                    submitError = result.error;
                                  });
                                }
                              } catch (_) {
                                if (mounted) {
                                  setState(() {
                                    _loading = false;
                                  });
                                }
                              }
                            },
                      child: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("Verify"),
                    ),

                    TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              final result = await auth.resendOtp();
                              if (!mounted || result.isSuccess) return;
                              setState(() {
                                submitError = result.error;
                              });
                            },
                      child: const Text("Resend code"),
                    ),

                    if (submitError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}
