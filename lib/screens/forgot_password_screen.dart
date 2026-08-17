import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/validators.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();

  String? emailError;
  String? otpError;
  String? passwordError;
  String? confirmPasswordError;

  bool _otpSent = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    emailCtrl.dispose();
    otpCtrl.dispose();
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Reset password")),
      body: Center(
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeskconnUI.cardRadius)),
          child: SizedBox(
            width: DeskconnUI.cardWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: DeskconnLogo()),
                  const SizedBox(height: 16),

                  if (!_otpSent) ...[
                    const Text("Enter your email to receive a reset code", textAlign: TextAlign.center),
                    const SizedBox(height: 16),

                    TextField(
                      controller: emailCtrl,
                      onChanged: (v) {
                        if (emailError != null) {
                          setState(() {
                            emailError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(labelText: 'Email', errorText: emailError),
                    ),

                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() {
                                emailError = Validators.email(emailCtrl.text);
                              });

                              if (emailError != null) {
                                return;
                              }
                              setState(() => _loading = true);
                              final ok = await auth.requestPasswordReset(emailCtrl.text.trim());
                              if (!mounted) return;
                              setState(() => _loading = false);

                              if (ok) {
                                setState(() => _otpSent = true);
                              }
                            },
                      child: const Text("Send reset code"),
                    ),
                  ] else ...[
                    const Text("Enter the code and your new password", textAlign: TextAlign.center),
                    const SizedBox(height: 16),

                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (v) {
                        if (otpError != null) {
                          setState(() {
                            otpError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(labelText: "OTP", errorText: otpError),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: passCtrl,
                      obscureText: _obscurePassword,
                      onChanged: (v) {
                        if (passwordError != null) {
                          setState(() {
                            passwordError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: "New password",
                        errorText: passwordError,
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Validators.passwordRequirement,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: confirmPassCtrl,
                      obscureText: _obscureConfirmPassword,
                      onChanged: (v) {
                        if (confirmPasswordError != null) {
                          setState(() {
                            confirmPasswordError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: "Confirm new password",
                        errorText: confirmPasswordError,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() {
                                otpError = Validators.otp(otpCtrl.text);
                                passwordError = Validators.password(passCtrl.text);
                                confirmPasswordError = confirmPassCtrl.text == passCtrl.text
                                    ? null
                                    : 'Passwords do not match';
                              });

                              if (otpError != null || passwordError != null || confirmPasswordError != null) {
                                return;
                              }

                              setState(() => _loading = true);
                              final ok = await auth.resetPassword(otp: otpCtrl.text.trim(), newPassword: passCtrl.text);
                              if (!mounted) return;
                              setState(() => _loading = false);

                              if (ok && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                      child: const Text("Reset password"),
                    ),
                  ],

                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
