import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/screens/verify_otp_screen.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/password_requirement_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deskconn_mobile_app/widgets/validators.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final emailCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final nameFocus = FocusNode();
  final passFocus = FocusNode();

  String? emailError;
  String? nameError;
  bool _obscurePassword = true;

  bool get _passwordMeetsRequirements => Validators.isPasswordValid(passCtrl.text);
  bool get _canCreateAccount =>
      Validators.email(emailCtrl.text) == null && Validators.name(nameCtrl.text) == null && _passwordMeetsRequirements;

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
    nameCtrl.dispose();
    passCtrl.dispose();
    nameFocus.dispose();
    passFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => nameFocus.requestFocus(),
                            onChanged: (v) {
                              setState(() {
                                emailError = null;
                              });
                            },
                            decoration: InputDecoration(labelText: 'Email', errorText: emailError),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: nameCtrl,
                            focusNode: nameFocus,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => passFocus.requestFocus(),
                            onChanged: (v) {
                              setState(() {
                                nameError = null;
                              });
                            },
                            decoration: InputDecoration(labelText: 'Username', errorText: nameError),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: passCtrl,
                            focusNode: passFocus,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => FocusScope.of(context).unfocus(),
                            onChanged: (v) {
                              setState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
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

                          const SizedBox(height: 24),

                          auth.isLoading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _canCreateAccount
                                      ? () async {
                                          FocusScope.of(context).unfocus();

                                          setState(() {
                                            emailError = Validators.email(emailCtrl.text);
                                            nameError = Validators.name(nameCtrl.text);
                                          });

                                          if (emailError != null || nameError != null || !_passwordMeetsRequirements) {
                                            return;
                                          }

                                          final ok = await auth.createAccount(
                                            email: emailCtrl.text.trim(),
                                            name: nameCtrl.text.trim(),
                                            password: passCtrl.text,
                                          );

                                          if (ok && context.mounted) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => const VerifyOtpScreen()),
                                            );
                                          }
                                        }
                                      : null,
                                  child: const Text('Create account'),
                                ),

                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              auth.error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],

                          const Divider(),
                          TextButton(
                            onPressed: auth.isLoading
                                ? null
                                : () {
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context);
                                      return;
                                    }

                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (_) => const SignInScreen()),
                                    );
                                  },
                            child: const Text('Already have an account? Sign in'),
                          ),
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
