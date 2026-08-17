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
  final passFocus = FocusNode();

  String? emailError;

  bool _otpSent = false;
  bool _loading = false;
  bool _obscurePassword = true;

  bool get _passwordMeetsRequirements =>
      Validators.isPasswordValid(passCtrl.text);

  bool get _canResetPassword =>
      Validators.isOtpValid(otpCtrl.text) && _passwordMeetsRequirements;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AuthProvider>().clearError();
      }
    });
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    otpCtrl.dispose();
    passCtrl.dispose();
    passFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Reset password"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                DeskconnUI.cardRadius,
              ),
            ),
            child: SizedBox(
              width: DeskconnUI.cardWidth,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: DeskconnLogo(),
                    ),
                    const SizedBox(height: 16),

                    if (!_otpSent) ...[
                      const Text(
                        "Enter your email to receive a reset code",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) =>
                            FocusScope.of(context).unfocus(),
                        onChanged: (v) {
                          context.read<AuthProvider>().clearError();

                          if (emailError != null) {
                            setState(() {
                              emailError = null;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Email',
                          errorText: emailError,
                        ),
                      ),

                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () async {
                          setState(() {
                            emailError =
                                Validators.email(emailCtrl.text);
                          });

                          if (emailError != null) {
                            return;
                          }

                          setState(() {
                            _loading = true;
                          });

                          final ok =
                          await auth.requestPasswordReset(
                            emailCtrl.text.trim(),
                          );

                          if (!mounted) return;

                          setState(() {
                            _loading = false;
                          });

                          if (ok) {
                            setState(() {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _otpSent = true;
                              otpCtrl.clear();
                              passCtrl.clear();
                            });
                          }
                        },
                        child: const Text("Send reset code"),
                      ),
                    ] else ...[
                      const Text(
                        "Enter the code and your new password",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: otpCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (_) {
                          context.read<AuthProvider>().clearError();
                          setState(() {});
                        },
                        onSubmitted: (_) => passFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: "OTP",
                          suffixText: '${otpCtrl.text.length}/6',
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: passCtrl,
                        focusNode: passFocus,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          context.read<AuthProvider>().clearError();
                          setState(() {});
                        },
                        onSubmitted: (_) =>
                            FocusScope.of(context).unfocus(),
                        decoration: InputDecoration(
                          labelText: "New password",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword =
                                !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      PasswordRequirementItem(
                        isMet: _passwordMeetsRequirements,
                      ),

                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed:
                        _loading || !_canResetPassword
                            ? null
                            : () async {
                          setState(() {
                            _loading = true;
                          });

                          final ok =
                          await auth.resetPassword(
                            otp: otpCtrl.text.trim(),
                            newPassword: passCtrl.text,
                          );

                          if (!mounted) return;

                          setState(() {
                            _loading = false;
                          });

                          if (ok && context.mounted) {
                            auth.clearError();
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
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .error,
                        ),
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
