import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/password_requirement_item.dart';
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
  final passFocus = FocusNode();
  final confirmPassFocus = FocusNode();

  String? emailError;
  String? confirmPasswordError;
  String? submitError;

  bool _otpSent = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _passwordMeetsRequirements => Validators.isPasswordValid(passCtrl.text);

  bool get _passwordsMatch => confirmPassCtrl.text == passCtrl.text;

  bool get _canResetPassword =>
      Validators.isOtpValid(otpCtrl.text) && _passwordMeetsRequirements && _passwordsMatch;

  @override
  void dispose() {
    emailCtrl.dispose();
    otpCtrl.dispose();
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    passFocus.dispose();
    confirmPassFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Reset password")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
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
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (v) {
                          if (emailError != null) {
                            setState(() {
                              emailError = null;
                              submitError = null;
                            });
                          } else if (submitError != null) {
                            setState(() => submitError = null);
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
                                  submitError = null;
                                });

                                if (emailError != null) {
                                  return;
                                }

                                setState(() {
                                  _loading = true;
                                });

                                final result = await auth.requestPasswordReset(emailCtrl.text.trim());

                                if (!mounted) return;

                                setState(() {
                                  _loading = false;
                                });

                                if (result.isSuccess) {
                                  setState(() {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    _otpSent = true;
                                    otpCtrl.clear();
                                    passCtrl.clear();
                                    confirmPassCtrl.clear();
                                  });
                                } else {
                                  setState(() {
                                    submitError = result.error;
                                  });
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
                        textInputAction: TextInputAction.next,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        onChanged: (_) {
                          setState(() {
                            submitError = null;
                          });
                        },
                        onSubmitted: (_) => passFocus.requestFocus(),
                        decoration: InputDecoration(labelText: "OTP", suffixText: '${otpCtrl.text.length}/6'),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: passCtrl,
                        focusNode: passFocus,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          setState(() {
                            submitError = null;
                          });
                        },
                        onSubmitted: (_) => confirmPassFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: "New password",
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

                      const SizedBox(height: 12),

                      PasswordRequirementItem(isMet: _passwordMeetsRequirements),

                      const SizedBox(height: 16),

                      TextField(
                        controller: confirmPassCtrl,
                        focusNode: confirmPassFocus,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          setState(() {
                            confirmPasswordError = null;
                            submitError = null;
                          });
                        },
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
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
                        onPressed: _loading || !_canResetPassword
                            ? null
                            : () async {
                                setState(() {
                                  confirmPasswordError = _passwordsMatch ? null : 'Passwords do not match';
                                });

                                if (confirmPasswordError != null) {
                                  return;
                                }

                                setState(() {
                                  _loading = true;
                                });

                                final result = await auth.resetPassword(
                                  otp: otpCtrl.text.trim(),
                                  newPassword: passCtrl.text,
                                );

                                if (!mounted) return;

                                setState(() {
                                  _loading = false;
                                });

                                if (result.isSuccess && context.mounted) {
                                  Navigator.pop(context);
                                } else {
                                  setState(() {
                                    submitError = result.error;
                                  });
                                }
                              },
                        child: const Text("Reset password"),
                      ),
                    ],

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
        ),
      ),
    );
  }
}
