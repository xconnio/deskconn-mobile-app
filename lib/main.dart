import 'dart:async';
import 'dart:ui';

import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_registry.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_screen.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:deskconn_mobile_app/core/update/update_service.dart';
import 'package:deskconn_mobile_app/widgets/update_dialog.dart';
import 'package:provider/provider.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is StateError && error.message == 'Terminal closed') return true;
    if (error.toString().contains('WebRTC data channel closed')) return true;
    return false;
  };

  const MethodChannel('deskconn/shell_notification').setMethodCallHandler((call) async {
    final realm = (call.arguments as Map?)?.entries
        .firstWhere((e) => e.key == 'realm', orElse: () => const MapEntry('realm', null))
        .value
        ?.toString();

    switch (call.method) {
      case 'closeTerminal':
        if (realm != null) TerminalRegistry().closeTerminal(realm);
      case 'openTerminal':
        if (realm != null) {
          final controller = TerminalRegistry().getActive(realm);
          if (controller != null) {
            navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => TerminalScreen(controller: controller)));
          }
        }
    }
  });

  await initializeDesktopSessionBackgroundService();
  unawaited(FlutterBackgroundService().startService());

  runApp(const DeskconnApp());
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
            home: const AppBootstrap(),
          );
        },
      ),
    );
  }
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _initialization;
  bool _notificationActive = false;

  @override
  void initState() {
    super.initState();
    final completer = Completer<void>();
    _initialization = completer.future;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      try {
        await context.read<SessionProvider>().initialize();
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
      unawaited(_checkForUpdate());
    });
  }

  Future<void> _checkForUpdate() async {
    final release = await UpdateService().checkForUpdate();
    if (release != null && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => UpdateDialog(release: release),
      );
    }
  }

  void _syncNotification(bool loggedIn) {
    if (loggedIn && !_notificationActive) {
      _notificationActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(showAppNotification()));
    } else if (!loggedIn && _notificationActive) {
      _notificationActive = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(hideAppNotification()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        final session = context.watch<SessionProvider>();
        _syncNotification(session.loggedIn);
        return session.loggedIn ? const DesktopListScreen() : const SignInScreen();
      },
    );
  }
}
