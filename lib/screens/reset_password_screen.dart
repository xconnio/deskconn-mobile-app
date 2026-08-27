import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/widgets/app_snack_bar.dart';
import 'package:deskconn_mobile_app/widgets/auth_card_layout.dart';
import 'package:deskconn_mobile_app/widgets/password_requirement_item.dart';
import 'package:deskconn_mobile_app/widgets/validators.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.otp});

  final String otp;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  final confirmPassFocus = FocusNode();

  String? submitError;

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _passwordMeetsRequirements =>
      Validators.isPasswordValid(passCtrl.text);
  bool get _passwordsMatch =>
      passCtrl.text.isNotEmpty && passCtrl.text == confirmPassCtrl.text;
  bool get _canChangePassword => _passwordMeetsRequirements && _passwordsMatch;

  @override
  void dispose() {
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    confirmPassFocus.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_canChangePassword) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      submitError = null;
    });

    final result = await context.read<AuthProvider>().resetPassword(
      otp: widget.otp,
      newPassword: passCtrl.text,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (result.isSuccess) {
      AppSnackBar.showSuccess(context, 'Password changed successfully');
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    setState(() {
      submitError = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Change password")),
      body: AuthCardLayout(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Create a new password for your account",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {
                  submitError = null;
                });
              },
              onSubmitted: (_) => confirmPassFocus.requestFocus(),
              decoration: InputDecoration(
                labelText: "Password",
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
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
                  submitError = null;
                });
              },
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: "Confirm password",
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
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
              onPressed: _loading || !_canChangePassword
                  ? null
                  : _changePassword,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Change password"),
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
