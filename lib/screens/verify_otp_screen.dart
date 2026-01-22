import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/wamp/ui.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/logo.dart';
import '../widgets/validators.dart';
import 'dashboard_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final otpCtrl = TextEditingController();
  bool _loading = false;

  String? requiredError;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: DeskconnUI.background,
      appBar: AppBar(title: const Text("Verify email")),
      body: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeskconnUI.cardRadius),
          ),
          child: SizedBox(
            width: DeskconnUI.cardWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DeskconnLogo(),
                  const SizedBox(height: 16),
                  const Text(
                    "Enter the 6-digit code sent to your email",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !_loading,
                    decoration: const InputDecoration(labelText: "OTP"),
                  ),

                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !_loading,
                    onChanged: (v) {
                      setState(() {
                        requiredError = Validators.required(v);
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'OTP',
                      errorText: requiredError,
                    ),
                  ),


                  const SizedBox(height: 12),

                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () async {
                      setState(() {
                        requiredError = Validators.required(otpCtrl.text);
                      });

                      if (requiredError != null ) {
                        return;
                      }

                      if (otpCtrl.text.length != 6) return;

                      FocusScope.of(context).unfocus(); // ✅ close keyboard
                      setState(() => _loading = true);


                      final ok =
                      await auth.verifyOtp(otpCtrl.text.trim());

                      if (ok && mounted) {
                        await context
                            .read<SessionProvider>()
                            .login(
                          auth.pendingEmail!,
                          auth.pendingPassword!,
                        );

                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                            const DashboardScreen(),
                          ),
                              (_) => false,
                        );
                      }

                      if (mounted) {
                        setState(() => _loading = false);
                      }
                    },
                    child: _loading
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text("Verify"),
                  ),

                  TextButton(
                    onPressed: _loading ? null : auth.resendOtp,
                    child: const Text("Resend code"),
                  ),

                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        auth.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
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
