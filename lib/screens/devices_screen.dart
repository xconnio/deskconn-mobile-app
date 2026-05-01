import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool loading = true;
  bool revoking = false;
  List<Map<String, dynamic>> devices = [];
  String? currentDeviceId;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    currentDeviceId = await DeviceIdentity.deviceId();
    if (!mounted) return;
    final session = context.read<SessionProvider>();

    try {
      final res = await session.session!.call('io.xconn.deskconn.device.key.list');
      setState(() {
        devices = List<Map<String, dynamic>>.from(res.args);
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _revoke(String deviceId) async {
    if (revoking) return;
    setState(() => revoking = true);

    final session = context.read<SessionProvider>();

    try {
      await session.session!.call('io.xconn.deskconn.device.delete', args: [deviceId]);
    } catch (e) {
      if (mounted) {
        setState(() => revoking = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }

    if (deviceId == currentDeviceId) {
      await session.logout();
      return;
    }

    await _load();
    if (mounted) setState(() => revoking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AppShell(
        title: 'Devices',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return AppShell(
        title: 'Devices',
        body: Center(
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    return AppShell(
      title: 'Devices',
      body: devices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smartphone_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No authorized devices yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                ],
              ),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, i) {
                final d = devices[i];
                final isThis = d['device_id'] == currentDeviceId;

                return ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: Text(d['name'] ?? d['device_id']),
                  subtitle: isThis ? const Text('This device') : null,
                  trailing: isThis
                      ? null
                      : TextButton(
                          onPressed: revoking ? null : () => _revoke(d['device_id']),
                          child: const Text('Revoke'),
                        ),
                );
              },
            ),
    );
  }
}
