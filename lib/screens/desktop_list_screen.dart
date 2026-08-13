import 'dart:async';

import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/screens/desktop_details_screen.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:deskconn_mobile_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/providers/session_provider.dart';

enum _RowStatus { connecting, p2p, routed, offline }

class DesktopListScreen extends StatefulWidget {
  const DesktopListScreen({super.key});

  @override
  State<DesktopListScreen> createState() => _DesktopListScreenState();
}

class _DesktopListScreenState extends State<DesktopListScreen> {
  final Set<String> _prewarmedRealms = {};
  final Set<String> _connectingRealms = {};
  Timer? _livenessTimer;

  _RowStatus _statusFor(String realm) {
    final connection = DesktopConnectionManager().get(realm);
    if (connection != null) {
      return connection.isP2P ? _RowStatus.p2p : _RowStatus.routed;
    }
    return _connectingRealms.contains(realm) ? _RowStatus.connecting : _RowStatus.offline;
  }

  @override
  void initState() {
    super.initState();
    _livenessTimer = Timer.periodic(const Duration(seconds: 15), (_) => _verifyAllLiveness());
  }

  @override
  void dispose() {
    _livenessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final desktops = context.read<SessionProvider>().desktops;
    final toPrewarm = <Map<String, dynamic>>[];
    for (final d in desktops) {
      final realm = d['realm']?.toString();
      if (realm != null && realm.isNotEmpty && _prewarmedRealms.add(realm)) {
        toPrewarm.add(d);
      }
    }
    if (toPrewarm.isNotEmpty) {
      unawaited(_prewarmAll(toPrewarm));
    }
  }

  Future<void> _verifyAllLiveness() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    final desktops = context.read<SessionProvider>().desktops;
    await Future.wait(
      desktops.map((d) async {
        final realm = d['realm']?.toString();
        if (realm == null) return;
        await _verifyLiveness(realm);
      }),
    );
  }

  Future<void> _verifyLiveness(String realm) async {
    final connection = DesktopConnectionManager().get(realm);
    if (connection == null) return;

    try {
      final enc = await Encryption.create();
      await connection.session
          .call('io.xconn.deskconn.deskconnd.key.exchange', args: [enc.clientPublicKey])
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      await DesktopConnectionManager().release(realm);
      if (mounted) setState(() {});
    }
  }

  static const int _maxConcurrentPrewarms = 2;
  static const Duration _prewarmBatchGap = Duration(milliseconds: 500);

  Future<void> _prewarmAll(List<Map<String, dynamic>> desktops) async {
    for (var i = 0; i < desktops.length; i += _maxConcurrentPrewarms) {
      if (!mounted) return;
      final batch = desktops.skip(i).take(_maxConcurrentPrewarms);
      await Future.wait(batch.map(_prewarm));
      if (i + _maxConcurrentPrewarms < desktops.length) {
        await Future.delayed(_prewarmBatchGap);
      }
    }
  }

  Future<bool> _connect(String realm, bool webRtcEnabled) async {
    final authId = await DeviceIdentity.lastEmail();
    final privateKey = await DeviceIdentity.privateKey();
    if (authId == null || privateKey == null) return false;

    try {
      final connection = await DesktopConnectionManager().acquire(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
      );
      final enc = await Encryption.create();
      await connection.session
          .call('io.xconn.deskconn.deskconnd.key.exchange', args: [enc.clientPublicKey])
          .timeout(const Duration(seconds: 5));
      connection.isAgentOnline = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _prewarm(Map<String, dynamic> desktop) async {
    final realm = desktop['realm']?.toString();
    if (realm == null || realm.isEmpty) return;
    if (DesktopConnectionManager().get(realm) != null) return;

    if (mounted) setState(() => _connectingRealms.add(realm));
    final prefs = await SharedPreferences.getInstance();
    final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? true;
    await _connect(realm, webRtcEnabled);
    if (mounted) setState(() => _connectingRealms.remove(realm));
  }

  Future<bool> _ensureConnected(String realm) async {
    final cached = DesktopConnectionManager().get(realm);
    if (cached != null && cached.isAgentOnline) return true;

    if (mounted) setState(() => _connectingRealms.add(realm));
    final prefs = await SharedPreferences.getInstance();
    final webRtcEnabled = prefs.getBool(prefKeyWebRtcEnabled) ?? true;
    final success = await _connect(realm, webRtcEnabled);
    if (mounted) setState(() => _connectingRealms.remove(realm));
    return success;
  }

  Future<void> _openDesktop(BuildContext context, Map<String, dynamic> desktop) async {
    final realm = desktop['realm']?.toString();
    if (realm == null) return;

    final connected = await _ensureConnected(realm);
    if (!context.mounted) return;

    if (connected) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DesktopDetailsScreen(desktop: desktop)));
      return;
    }

    final retried = await _showConnectionDialog(context, desktop);
    if (retried && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DesktopDetailsScreen(desktop: desktop)));
    }
  }

  Future<bool> _showConnectionDialog(BuildContext context, Map<String, dynamic> desktop) async {
    final realm = desktop['realm']?.toString();
    if (realm == null) return false;

    final status = _statusFor(realm);
    if (status == _RowStatus.connecting) return false;

    final (title, description) = switch (status) {
      _RowStatus.p2p => ('Connected (P2P)', 'Using a direct peer-to-peer connection.'),
      _RowStatus.routed => ('Connected (Routed)', 'Using a routed connection through the server.'),
      _RowStatus.offline => ('Offline', 'Could not reach this desktop.'),
      _RowStatus.connecting => ('Connecting', ''),
    };

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            if (status != _RowStatus.p2p)
              TextButton(onPressed: () => Navigator.of(dialogContext).pop('p2p'), child: const Text('Retry P2P')),
            if (status != _RowStatus.routed)
              TextButton(onPressed: () => Navigator.of(dialogContext).pop('routed'), child: const Text('Use Routed')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
          ],
        );
      },
    );

    if (action == null || !mounted) return false;
    return _forceReconnect(realm, action == 'p2p');
  }

  Future<bool> _forceReconnect(String realm, bool webRtcEnabled) async {
    if (mounted) setState(() => _connectingRealms.add(realm));
    await DesktopConnectionManager().release(realm);
    final success = await _connect(realm, webRtcEnabled);
    if (mounted) setState(() => _connectingRealms.remove(realm));

    if (!mounted) return success;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not connect to desktop.')));
    } else if (webRtcEnabled && _statusFor(realm) == _RowStatus.routed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('P2P unavailable, connected via routed instead.')));
    }
    return success;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return AppShell(
      title: 'Desktops',
      currentSection: AppShellSection.desktops,
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<SessionProvider>().loadDesktops();
          await _verifyAllLiveness();
        },
        child: session.desktopsLoading || session.desktops.isEmpty
            ? CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    child: session.desktopsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.desktop_windows_outlined,
                                    size: 80,
                                    color: Theme.of(context).disabledColor.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'No desktop attached yet',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Connected desktops will appear here',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Theme.of(context).hintColor.withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: session.desktops.length,
                itemBuilder: (context, i) {
                  final d = session.desktops[i];
                  final name = d['name'] as String?;
                  final authId = d['authid']?.toString() ?? '';
                  final shortId = authId.length > 4 ? authId.substring(authId.length - 4) : authId;
                  final realm = d['realm']?.toString() ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.desktop_windows, color: colorScheme.primary),
                      ),
                      title: Text(name ?? 'Unnamed Desktop', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('• $shortId', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ConnectionChip(status: _statusFor(realm), onTap: () => _showConnectionDialog(context, d)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                      onTap: () => _openDesktop(context, d),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final _RowStatus status;
  final VoidCallback onTap;

  const _ConnectionChip({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = DeskconnPalette.of(context);
    final (dotColor, label) = switch (status) {
      _RowStatus.connecting => (colorScheme.secondary, 'connecting'),
      _RowStatus.p2p => (palette.statusOnline, 'p2p'),
      _RowStatus.routed => (palette.statusRouted, 'routed'),
      _RowStatus.offline => (palette.statusOffline, 'offline'),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              '($label)',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
