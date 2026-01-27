import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/screens/verify_otp_screen.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/theme_toggle.dart';
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

  String? emailError;
  String? nameError;
  String? passwordError;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, actions: const [ThemeToggleButton()]),
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
                            onChanged: (v) {
                              setState(() {
                                emailError = Validators.email(v);
                              });
                            },
                            decoration: InputDecoration(labelText: 'Email', errorText: emailError),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: nameCtrl,
                            onChanged: (v) {
                              setState(() {
                                nameError = Validators.name(v);
                              });
                            },
                            decoration: InputDecoration(labelText: 'Username', errorText: nameError),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: passCtrl,
                            obscureText: true,
                            onChanged: (v) {
                              setState(() {
                                passwordError = Validators.password(v);
                              });
                            },
                            decoration: InputDecoration(labelText: 'Password', errorText: passwordError),
                          ),

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
                                  onPressed: () async {
                                    FocusScope.of(context).unfocus();

                                    setState(() {
                                      emailError = Validators.email(emailCtrl.text);
                                      nameError = Validators.name(nameCtrl.text);
                                      passwordError = Validators.password(passCtrl.text);
                                    });

                                    if (emailError != null || nameError != null || passwordError != null) {
                                      return;
                                    }

                                    final ok = await auth.createAccount(
                                      email: emailCtrl.text.trim(),
                                      name: nameCtrl.text.trim(),
                                      role: 'user',
                                      password: passCtrl.text,
                                    );

                                    if (ok && context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const VerifyOtpScreen()),
                                      );
                                    }
                                  },
                                  child: const Text('Create account'),
                                ),

                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              auth.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],

                          const Divider(),
                          TextButton(
                            onPressed: auth.isLoading
                                ? null
                                : () {
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
