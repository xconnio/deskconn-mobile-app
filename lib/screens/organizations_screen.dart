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
  List<Map<String, dynamic>> orgs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionProvider>();

    final res = await session.session!.call('io.xconn.deskconn.organization.list');

    setState(() {
      orgs = List<Map<String, dynamic>>.from(res.args);
      loading = false;
    });
  }

  Future<void> _createOrg() async {
    final ctrl = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create organization'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Organization name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Create')),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final session = context.read<SessionProvider>();

    await session.session!.call('io.xconn.deskconn.organization.create', args: [name]);

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizations'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _createOrg)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : orgs.isEmpty
              ? const Center(child: Text('No organizations'))
              : ListView.builder(
                  itemCount: orgs.length,
                  itemBuilder: (context, i) {
                    final o = orgs[i];
                    return ListTile(leading: const Icon(Icons.business), title: Text(o['name'] ?? ''));
                  },
                ),
    );
  }
}
