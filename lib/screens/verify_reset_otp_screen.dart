import 'package:deskconn_mobile_app/screens/reset_password_screen.dart';
import 'package:deskconn_mobile_app/widgets/auth_card_layout.dart';
import 'package:deskconn_mobile_app/widgets/otp_code_field.dart';
import 'package:flutter/material.dart';

class VerifyResetOtpScreen extends StatefulWidget {
  const VerifyResetOtpScreen({super.key});

  @override
  State<VerifyResetOtpScreen> createState() => _VerifyResetOtpScreenState();
}

class _VerifyResetOtpScreenState extends State<VerifyResetOtpScreen> {
  final otpCtrl = TextEditingController();
  final otpFocus = FocusNode();

  bool get _canVerify => otpCtrl.text.length == 6;

  @override
  void dispose() {
    otpCtrl.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  void _verify() {
    if (!_canVerify) return;

    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordScreen(otp: otpCtrl.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify reset code')),
      body: AuthCardLayout(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter the 6-digit reset code sent to your email', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OtpCodeField(controller: otpCtrl, focusNode: otpFocus, onChanged: (_) => setState(() {})),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _canVerify ? _verify : null, child: const Text('Verify')),
          ],
        ),
      ),
    );
  }
}
