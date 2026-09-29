import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool keepFrameworkHandlingBack(NavigationNotification notification) {
  final state = WidgetsBinding.instance.lifecycleState;
  if (state != null && state != AppLifecycleState.detached) {
    SystemNavigator.setFrameworkHandlesBack(true);
  }
  return true;
}

class ExitGuard extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const ExitGuard({super.key, required this.navigatorKey, required this.child});

  @override
  State<ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<ExitGuard> with WidgetsBindingObserver {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return false;
    if (_asking) return true;

    _asking = true;
    try {
      final close = await showDialog<bool>(
        context: ctx,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close Deskconn?'),
          content: const Text('Do you want to close the app?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Close')),
          ],
        ),
      );
      if (close == true) await SystemNavigator.pop();
    } finally {
      _asking = false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
