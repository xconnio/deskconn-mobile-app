import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';

class OrganizationDetailsScreen extends StatefulWidget {
  final String id;
  final String name;

  const OrganizationDetailsScreen({super.key, required this.id, required this.name});

  @override
  State<OrganizationDetailsScreen> createState() => _OrganizationDetailsScreenState();
}

class _OrganizationDetailsScreenState extends State<OrganizationDetailsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final session = context.read<SessionProvider>();

    try {
      final res = await session.session!.call("io.xconn.deskconn.organization.get", args: [widget.id]);
      if (res.args.isEmpty) throw Exception('Empty response');
      members = List<Map<String, dynamic>>.from(res.args[0]['members'] ?? []);
    } catch (e) {
      error = e.toString();
    }

    setState(() {
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [IconButton(icon: const Icon(Icons.person_add), onPressed: _inviteUser)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            )
          : ListView.builder(
              itemCount: members.length,
              itemBuilder: (_, i) {
                final m = members[i];
                final user = m['user'];

                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user['name']),
                  subtitle: Text(user['email']),
                  trailing: Text(m['role']),
                );
              },
            ),
    );
  }

  Future<void> _inviteUser() async {
    final emailCtrl = TextEditingController();

    final email = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Invite user"),
          content: TextField(
            controller: emailCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: "User email"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, emailCtrl.text.trim()), child: const Text("Send")),
          ],
        );
      },
    );

    if (email == null || email.isEmpty) return;

    if (!mounted) return;
    await context.read<SessionProvider>().createInvitation(widget.id, email, "member");

    await _load();
  }
}
