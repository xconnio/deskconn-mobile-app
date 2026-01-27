import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/forgot_password_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_up_screen.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:deskconn_mobile_app/widgets/theme_toggle.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/widgets/validators.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String? emailError;
  String? passwordError;

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  Future<void> _restoreEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('last_email');
    if (email != null) {
      if (mounted) {
        setState(() {
          emailCtrl.text = email;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

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
                          if (session.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: () async {
                                FocusScope.of(context).unfocus();

                                setState(() {
                                  emailError = Validators.email(emailCtrl.text);
                                  passwordError = Validators.password(passCtrl.text);
                                });

                                if (emailError != null || passwordError != null) {
                                  return;
                                }

                                await session.login(emailCtrl.text.trim(), passCtrl.text);

                                if (!context.mounted) return;

                                if (session.loggedIn) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (_) => const DesktopListScreen()),
                                  );
                                }
                              },
                              child: const Text('Sign in'),
                            ),
                          if (session.error != null) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Invalid email or password',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: session.isLoading
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                      );
                                    },
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const Divider(),
                          TextButton(
                            onPressed: session.isLoading
                                ? null
                                : () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
                                  },
                            child: const Text('Create account'),
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
