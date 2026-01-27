import 'package:deskconn_mobile_app/screens/account_screen.dart';
import 'package:flutter/material.dart';

import 'package:deskconn_mobile_app/screens/devices_screen.dart';
import 'package:deskconn_mobile_app/screens/organizations_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Account'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Devices'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Organizations'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OrganizationsScreen()));
            },
          ),
        ],
      ),
    );
  }
}
