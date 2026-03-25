import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    final sessionProvider = context.read<SessionProvider>();

    await Future.wait([Future.delayed(const Duration(milliseconds: 900)), sessionProvider.initialize()]);

    if (!mounted) return;

    if (sessionProvider.loggedIn) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DesktopListScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ScaleTransition(scale: _scale, child: const DeskconnLogo(size: 72)),
      ),
    );
  }
}
