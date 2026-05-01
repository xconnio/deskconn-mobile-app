import 'package:deskconn_mobile_app/screens/organization_details_screen.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';

class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> orgs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionProvider>();

    try {
      final res = await session.session!.call('io.xconn.deskconn.organization.list');
      setState(() {
        orgs = List<Map<String, dynamic>>.from(res.args);
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Organizations',
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            )
          : orgs.isEmpty
          ? const Center(child: Text('No organizations'))
          : ListView.builder(
              itemCount: orgs.length,
              itemBuilder: (context, i) {
                final o = orgs[i];
                return ListTile(
                  leading: const Icon(Icons.business),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrganizationDetailsScreen(id: o['id'], name: o['name']),
                      ),
                    );
                  },
                  title: Text(o['name'] ?? ''),
                );
              },
            ),
    );
  }
}
