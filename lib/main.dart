import 'dart:async';
import 'dart:ui';

import 'package:deskconn_mobile_app/core/shell/shell_registry.dart';
import 'package:deskconn_mobile_app/core/shell/shell_screen.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/splash_screen.dart';
import 'package:deskconn_mobile_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/shell/shell_background_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is StateError && error.message == 'Shell closed') return true;
    if (error.toString().contains('WebRTC data channel closed')) return true;
    return false;
  };

  const MethodChannel('deskconn/shell_notification').setMethodCallHandler((call) async {
    final realm = (call.arguments as Map?)?.entries
        .firstWhere((e) => e.key == 'realm', orElse: () => const MapEntry('realm', null))
        .value
        ?.toString();

    switch (call.method) {
      case 'closeShell':
        if (realm != null) ShellRegistry().closeShell(realm);
      case 'openShell':
        if (realm != null) {
          final controller = ShellRegistry().getActive(realm);
          if (controller != null) {
            navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ShellScreen(controller: controller)));
          }
        }
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
            navigatorKey: navigatorKey,
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
