import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> with SingleTickerProviderStateMixin {
  late TabController tabs;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this);
    Future.microtask(() {
      if (!mounted) return;
      context.read<SessionProvider>().loadInvitations();
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return AppShell(
      title: 'Invitations',
      currentSection: AppShellSection.invitations,
      bottom: TabBar(
        controller: tabs,
        tabs: const [
          Tab(text: "Inbox"),
          Tab(text: "Outbox"),
        ],
      ),

      body: session.invitationLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: tabs, children: const [_Inbox(), _Outbox()]),
    );
  }
}

class _Inbox extends StatelessWidget {
  const _Inbox();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    if (session.invitationsInbox.isEmpty) {
      return const Center(child: Text("No invitations"));
    }

    return ListView.builder(
      itemCount: session.invitationsInbox.length,
      itemBuilder: (_, i) {
        final inv = session.invitationsInbox[i];

        return ListTile(
          leading: const Icon(Icons.mail),
          title: Text(inv['organization_id']),
          subtitle: Text("Role: ${inv['role']}"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () {
                  context.read<SessionProvider>().respondInvitation(inv['id'], "accepted");
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () {
                  context.read<SessionProvider>().respondInvitation(inv['id'], "rejected");
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Outbox extends StatelessWidget {
  const _Outbox();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    if (session.invitationsOutbox.isEmpty) {
      return const Center(child: Text("No sent invitations"));
    }

    return ListView.builder(
      itemCount: session.invitationsOutbox.length,
      itemBuilder: (_, i) {
        final inv = session.invitationsOutbox[i];

        return ListTile(
          leading: const Icon(Icons.outbox),
          title: Text(inv['organization_id']),
          subtitle: Text("Status: ${inv['status']}"),
        );
      },
    );
  }
}
