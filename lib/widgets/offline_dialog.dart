import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

class OfflineDialog extends StatefulWidget {
  final Listenable connectivity;
  final bool Function() isOnline;

  const OfflineDialog({super.key, required this.connectivity, required this.isOnline});

  @override
  State<OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<OfflineDialog> {
  @override
  void initState() {
    super.initState();
    widget.connectivity.addListener(_maybeClose);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
  }

  @override
  void dispose() {
    widget.connectivity.removeListener(_maybeClose);
    super.dispose();
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
