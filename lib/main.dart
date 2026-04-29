import 'dart:async';

import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/splash_screen.dart';
import 'package:deskconn_mobile_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/shell/shell_background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeskconnApp());
  unawaited(initializeShellBackgroundService());
}

class DeskconnApp extends StatelessWidget {
  const DeskconnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DeskconnTheme.light(),
            darkTheme: DeskconnTheme.dark(),
            themeMode: theme.mode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
