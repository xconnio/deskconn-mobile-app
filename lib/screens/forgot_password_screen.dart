import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/screens/verify_reset_otp_screen.dart';
import 'package:deskconn_mobile_app/widgets/auth_card_layout.dart';
import 'package:deskconn_mobile_app/widgets/validators.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailCtrl = TextEditingController();

  String? emailError;
  String? submitError;

  bool _loading = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Forgot password")),
      body: AuthCardLayout(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Enter your email to receive a reset code",
              textAlign: TextAlign.center,
            ),
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
                      FocusScope.of(context).unfocus();

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

                      final navigator = Navigator.of(context);
                      final result = await auth.requestPasswordReset(
                        emailCtrl.text.trim(),
                      );

                      if (!mounted) return;

                      setState(() {
                        _loading = false;
                      });

                      if (result.isSuccess) {
                        await navigator.push(
                          MaterialPageRoute(
                            builder: (_) => const VerifyResetOtpScreen(),
                          ),
                        );
                      } else {
                        setState(() {
                          submitError = result.error;
                        });
                      }
                    },
              child: const Text("Send reset code"),
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
    );
  }
}
