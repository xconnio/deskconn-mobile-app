import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app_settings/app_settings.dart';
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:deskconn_mobile_app/core/network/connectivity_service.dart';
import 'package:deskconn_mobile_app/core/share/share_service.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_registry.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_screen.dart';
import 'package:deskconn_mobile_app/providers/auth_provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/providers/theme_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_list_screen.dart';
import 'package:deskconn_mobile_app/screens/share_upload_screen.dart';
import 'package:deskconn_mobile_app/screens/sign_in_screen.dart';
import 'package:deskconn_mobile_app/theme/app_theme.dart';
import 'package:deskconn_mobile_app/theme/system_ui.dart';
import 'package:deskconn_mobile_app/theme/typography.dart';
import 'package:deskconn_mobile_app/widgets/logo.dart';
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
    if (error.toString().contains('WebRTC connection failed before data channel opened')) return true;
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

  runApp(const DeskconnApp());

  unawaited(_initializeAppServices());
}

Future<void> _initializeAppServices() async {
  try {
    await initializeDesktopSessionBackgroundService();
    await ShareService.instance.initialize();
    unawaited(FlutterBackgroundService().startService());
  } catch (e) {
    debugPrint('App service initialization failed: $e');
  }
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
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;

              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: DeskconnSystemUi.overlayStyle(brightness),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const AppBootstrap(),
          );
        },
      ),
    );
  }
}

class _OfflineDialog extends StatefulWidget {
  const _OfflineDialog();

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  @override
  void initState() {
    super.initState();
    ConnectivityService().addListener(_maybeClose);
  }

  @override
  void dispose() {
    ConnectivityService().removeListener(_maybeClose);
    super.dispose();
  }

  void _maybeClose() {
    if (mounted && ConnectivityService().hasConnection) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('No internet connection'),
        content: const Text(
          'Deskconn needs an internet connection to reach your desktops. Check your Wi-Fi or mobile data.',
        ),
        actions: [
          FilledButton(
            onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DeskconnLogo(size: 44),
          const SizedBox(height: 16),
          Text('Deskconn', style: DeskconnTypography.title(context)),
          const SizedBox(height: 40),
          const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ],
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
  final Completer<void> _sessionInitCompleter = Completer<void>();
  late final Future<void> _initialization = _sessionInitCompleter.future;
  bool _notificationActive = false;
  bool _wasOffline = false;
  bool _handlingSharedFiles = false;
  bool _connectivityChecked = false;
  bool _launchGatePassed = false;
  bool _sessionStarted = false;

  @override
  void initState() {
    super.initState();
    ConnectivityService().addListener(_handleConnectivityChange);
    ShareService.instance.pendingFiles.addListener(_handlePendingSharedFiles);

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // Waits for the real connectivity reading (ConnectivityService.hasConnection
  // defaults to true until its async check resolves) before deciding whether
  // to gate on _NoConnectionGate or start the session, so a cold launch while
  // offline can't slip through and attempt (and fail) a network session
  // restore, which used to look like the user had been signed out.
  Future<void> _bootstrap() async {
    await ConnectivityService().ready;
    if (!mounted) {
      if (!_sessionInitCompleter.isCompleted) _sessionInitCompleter.complete();
      return;
    }

    final online = ConnectivityService().hasConnection;
    _wasOffline = !online;
    setState(() {
      _connectivityChecked = true;
      _launchGatePassed = online;
    });

    if (online) await _startSession();
  }

  Future<void> _startSession() async {
    if (_sessionStarted) return;
    _sessionStarted = true;

    try {
      await context.read<SessionProvider>().initialize().timeout(DeskconnConfig.callTimeout);
      if (!_sessionInitCompleter.isCompleted) _sessionInitCompleter.complete();
    } catch (e, st) {
      debugPrint('Session initialization failed: $e');
      if (!_sessionInitCompleter.isCompleted) _sessionInitCompleter.completeError(e, st);
    }
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    ConnectivityService().removeListener(_handleConnectivityChange);
    ShareService.instance.pendingFiles.removeListener(_handlePendingSharedFiles);
    super.dispose();
  }

  void _handleConnectivityChange() {
    final online = ConnectivityService().hasConnection;
    if (online && _connectivityChecked && !_launchGatePassed && mounted) {
      setState(() => _launchGatePassed = true);
      unawaited(_startSession());
    }
    if (!online && !_wasOffline && _launchGatePassed) {
      _showOfflineDialog();
    } else if (online && _wasOffline && mounted) {
      final session = context.read<SessionProvider>();
      if (session.loggedIn) unawaited(session.loadDesktops());
    }
    _wasOffline = !online;
  }

  void _showOfflineDialog() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    unawaited(showDialog<void>(context: ctx, barrierDismissible: false, builder: (_) => const _OfflineDialog()));
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

  void _handlePendingSharedFiles() {
    if (!mounted || _handlingSharedFiles) return;
    final session = context.read<SessionProvider>();
    if (!session.loggedIn || ShareService.instance.pendingFiles.value.isEmpty) {
      return;
    }
    _handlingSharedFiles = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() {});
      final files = ShareService.instance.takePendingFiles();
      if (files.isEmpty) {
        _handlingSharedFiles = false;
        if (mounted) setState(() {});
        return;
      }
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        await showDialog<void>(
          context: ctx,
          barrierDismissible: false,
          builder: (_) => ShareUploadScreen(files: files),
        );
      }
      if (ShareService.instance.pendingFiles.value.isEmpty) {
        await ShareService.instance.finishIfShareOnly();
      }
      _handlingSharedFiles = false;
      if (mounted) setState(() {});
      if (ShareService.instance.pendingFiles.value.isNotEmpty) {
        _handlePendingSharedFiles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_connectivityChecked) {
      return const Scaffold(body: Center(child: _SplashContent()));
    }
    if (!_launchGatePassed) {
      return const _NoConnectionGate();
    }
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: _SplashContent()));
        }

        final session = context.watch<SessionProvider>();
        _syncNotification(session.loggedIn);
        if (session.loggedIn) _handlePendingSharedFiles();
        if (_handlingSharedFiles) {
          return const Scaffold(body: Center(child: _SplashContent()));
        }
        return session.loggedIn ? const DesktopListScreen() : const SignInScreen();
      },
    );
  }
}

class _NoConnectionGate extends StatelessWidget {
  const _NoConnectionGate();

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Deskconn?'),
        content: const Text('Deskconn needs an internet connection to work. Do you want to exit the app?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Exit')),
        ],
      ),
    );
    if (confirmed == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DeskconnLogo(size: 72),
                const SizedBox(height: 24),
                const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text('No internet connection', style: DeskconnTypography.title(context), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Deskconn needs an internet connection to work. Enable Wi-Fi or mobile data to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
                  child: const Text('Open Settings'),
                ),
                if (!kIsWeb && Platform.isAndroid) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => _confirmExit(context), child: const Text('Exit')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
