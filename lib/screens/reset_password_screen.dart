import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/core/wamp/ui.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/password_requirement_item.dart';
import 'package:deskconn_mobile_app/widgets/validators.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final otpCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final passFocus = FocusNode();

  String? submitError;

  bool _loading = false;
  bool _obscurePassword = true;

  bool get _passwordMeetsRequirements => Validators.isPasswordValid(passCtrl.text);

  bool get _canResetPassword => Validators.isOtpValid(otpCtrl.text) && _passwordMeetsRequirements;

  @override
  void dispose() {
    otpCtrl.dispose();
    passCtrl.dispose();
    passFocus.dispose();
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
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        setState(() {
                          submitError = null;
                        });
                      },
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
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

                    ElevatedButton(
                      onPressed: _loading || !_canResetPassword
                          ? null
                          : () async {
                              FocusScope.of(context).unfocus();

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
                                final navigator = Navigator.of(context);
                                navigator.pop();
                                navigator.pop();
                              } else {
                                setState(() {
                                  submitError = result.error;
                                });
                              }
                            },
                      child: const Text("Reset password"),
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
        ),
      ),
    );
  }
}
