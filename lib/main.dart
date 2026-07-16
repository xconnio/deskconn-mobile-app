import 'dart:async';
import 'dart:ui';

import 'package:app_settings/app_settings.dart';
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
  await ShareService.instance.initialize();
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

// Auto-dismisses itself the moment connectivity comes back, so there's no
// separate reconnect-tracking logic needed at the call site.
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
    return AlertDialog(
      title: const Text('No internet connection'),
      content: const Text(
        'Deskconn needs an internet connection to reach your desktops. Check your Wi-Fi or mobile data.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Dismiss')),
        FilledButton(
          onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
          child: const Text('Open Settings'),
        ),
      ],
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
          const DeskconnLogo(size: 88),
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
  late final Future<void> _initialization;
  bool _notificationActive = false;
  bool _wasOffline = false;
  bool _handlingSharedFiles = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService().hasConnection;
    ConnectivityService().addListener(_handleConnectivityChange);
    ShareService.instance.pendingFiles.addListener(_handlePendingSharedFiles);

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

  @override
  void dispose() {
    ConnectivityService().removeListener(_handleConnectivityChange);
    ShareService.instance.pendingFiles.removeListener(_handlePendingSharedFiles);
    super.dispose();
  }

  // Nothing previously told the user the device had no connectivity at all,
  // let alone offered a way to fix it, and nothing refreshed after a drop —
  // the user had to manually pull-to-refresh or reopen a screen. This shows
  // a dialog (with a shortcut to Wi-Fi settings) on loss, and on restore
  // re-triggers desktop list loading, which itself reconnects the account
  // session (see SessionProvider._ensureSession).
  void _handleConnectivityChange() {
    final online = ConnectivityService().hasConnection;
    if (!online && !_wasOffline) {
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
    unawaited(showDialog<void>(context: ctx, barrierDismissible: true, builder: (_) => const _OfflineDialog()));
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
    // Set synchronously (not via setState) so a call made from build() itself
    // is reflected in that same build pass without violating Flutter's
    // no-setState-during-build rule; the deferred setState below only
    // matters for calls triggered outside of build (e.g. the pendingFiles
    // listener) and for reverting the flag once the dialog closes.
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
