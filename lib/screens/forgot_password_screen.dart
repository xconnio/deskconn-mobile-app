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

  String? emailError;

  bool _otpSent = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: DeskconnUI.background,
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
                        setState(() {
                          emailError = Validators.email(v);
                        });
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
                      decoration: const InputDecoration(labelText: "OTP"),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "New password"),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() => _loading = true);
                              final ok = await auth.resetPassword(otp: otpCtrl.text.trim(), newPassword: passCtrl.text);
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
                      style: const TextStyle(color: Colors.red),
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
