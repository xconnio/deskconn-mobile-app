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
  List<Map<String, dynamic>> devices = [];
  String? currentDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    currentDeviceId = await DeviceIdentity.deviceId();
    if (!mounted) return;
    final session = context.read<SessionProvider>();

    final res = await session.session!.call('io.xconn.deskconn.device.key.list');

    setState(() {
      devices = List<Map<String, dynamic>>.from(res.args);
      loading = false;
    });
  }

  Future<void> _revoke(String deviceId) async {
    final session = context.read<SessionProvider>();

    await session.session!.call('io.xconn.deskconn.device.delete', args: [deviceId]);

    if (deviceId == currentDeviceId) {
      await session.logout();
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AppShell(
      title: 'Devices',
      body: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (context, i) {
          final d = devices[i];
          final isThis = d['device_id'] == currentDeviceId;

          return ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(d['name'] ?? d['device_id']),
            subtitle: isThis ? const Text('This device') : null,
            trailing: TextButton(onPressed: () => _revoke(d['device_id']), child: const Text('Revoke')),
          );
        },
      ),
    );
  }
}
