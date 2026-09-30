import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

class OfflineDialog extends StatefulWidget {
  final Listenable connectivity;
  final bool Function() isOnline;
  final Future<void> Function()? recheck;
  final Duration recheckInterval;

  const OfflineDialog({
    super.key,
    required this.connectivity,
    required this.isOnline,
    this.recheck,
    this.recheckInterval = const Duration(seconds: 2),
  });

  @override
  State<OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<OfflineDialog> {
  Timer? _recheckTimer;

  @override
  void initState() {
    super.initState();
    widget.connectivity.addListener(_maybeClose);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
    if (widget.recheck != null) {
      _recheckTimer = Timer.periodic(widget.recheckInterval, (_) => _recheck());
    }
  }

  @override
  void dispose() {
    _recheckTimer?.cancel();
    widget.connectivity.removeListener(_maybeClose);
    super.dispose();
  }

  Future<void> _recheck() async {
    await widget.recheck?.call();
    _maybeClose();
  }

  void _maybeClose() {
    if (!mounted || !widget.isOnline()) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    Navigator.of(context).removeRoute(route);
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
