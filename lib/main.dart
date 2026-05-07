import 'dart:async';
import 'dart:ui';

import 'package:deskconn_mobile_app/core/shell/shell_registry.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/splash_screen.dart';
import 'package:deskconn_mobile_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/shell/shell_background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is StateError && error.message == 'Shell closed') return true;
    if (error.toString().contains('WebRTC data channel closed')) return true;
    return false;
  };

  // Handle close-shell signal from the notification Close button.
  const MethodChannel('deskconn/shell_notification').setMethodCallHandler((call) async {
    if (call.method == 'closeShell') {
      final realm = (call.arguments as Map?)?.entries
          .firstWhere((e) => e.key == 'realm', orElse: () => const MapEntry('realm', null))
          .value
          ?.toString();
      if (realm != null) ShellRegistry().closeShell(realm);
    }
  });

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
