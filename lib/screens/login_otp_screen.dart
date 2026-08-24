import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final otpCtrl = TextEditingController();
  final otpFocus = FocusNode();

  String? submitError;

  bool get _canVerify => otpCtrl.text.length == 6;

  @override
  void dispose() {
    otpCtrl.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_canVerify) return;

    FocusScope.of(context).unfocus();
    setState(() => submitError = null);

    final session = context.read<SessionProvider>();
    final result = await session.verifyLoginOtp(
      email: widget.email,
      otp: otpCtrl.text,
    );

    if (!mounted) return;

    if (result.isSuccess && session.loggedIn) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DesktopListScreen()),
        (_) => false,
      );
    } else {
      setState(() {
        submitError = result.error ?? 'Invalid or expired code';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Verify sign in')),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Enter the 6-digit code sent to ${widget.email}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          OtpCodeField(
                            controller: otpCtrl,
                            focusNode: otpFocus,
                            enabled: !session.isLoading,
                            onChanged: (_) {
                              setState(() {
                                submitError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          if (session.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: _canVerify ? _verify : null,
                              child: const Text('Verify'),
                            ),
                          if (submitError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              submitError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
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
