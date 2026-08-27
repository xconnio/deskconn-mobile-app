import 'dart:async';
import 'dart:typed_data';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/wallpaper/wallpaper_cache.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/wamp/last_used_realm_store.dart';
import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/desktop_details_screen.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _RowStatus { connecting, p2p, routed, offline }

class MachineGrid extends StatefulWidget {
  final String? currentRealm;

  const MachineGrid({super.key, this.currentRealm});

  @override
  State<MachineGrid> createState() => _MachineGridState();
}

class _MachineGridState extends State<MachineGrid> {
  final Set<String> _connectingRealms = {};
  final Map<String, Uint8List?> _wallpapers = {};
  Timer? _livenessTimer;

  void _ensureWallpaperLoaded(String realm) {
    if (_wallpapers.containsKey(realm)) return;
    _wallpapers[realm] = null;
    WallpaperCache.load(realm).then((value) {
      if (!mounted || value == null) return;
      setState(() => _wallpapers[realm] = value);
    });
  }

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
          .call(DeskconnProcedures.deskconndKeyExchange, args: [enc.clientPublicKey])
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      await DesktopConnectionManager().release(realm);
      if (mounted) setState(() {});
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
          .call(DeskconnProcedures.deskconndKeyExchange, args: [enc.clientPublicKey])
          .timeout(const Duration(seconds: 5));
      connection.isAgentOnline = true;
      await LastUsedRealmStore.set(realm);
      return true;
    } catch (_) {
      return false;
    }
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

    if (realm == widget.currentRealm) {
      Navigator.of(context).pop();
      return;
    }

    final connected = await _ensureConnected(realm);
    if (!context.mounted) return;

    if (connected) {
      await _enterDesktop(context, desktop);
      return;
    }

    final retried = await _showConnectionDialog(context, desktop);
    if (retried && context.mounted) {
      await _enterDesktop(context, desktop);
    }
  }

  Future<void> _enterDesktop(BuildContext context, Map<String, dynamic> desktop) {
    return Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => DesktopDetailsScreen(desktop: desktop)), (route) => false);
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

    return RefreshIndicator(
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
          : GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.5,
              ),
              itemCount: session.desktops.length,
              itemBuilder: (context, i) {
                final d = session.desktops[i];
                final name = d['name'] as String? ?? 'Unnamed Desktop';
                final realm = d['realm']?.toString() ?? '';
                final status = _statusFor(realm);
                _ensureWallpaperLoaded(realm);
                final wallpaper = _wallpapers[realm];

                return _MachineCard(
                  name: name,
                  status: status,
                  wallpaper: wallpaper,
                  onTap: () => _openDesktop(context, d),
                  onStatusTap: () => _showConnectionDialog(context, d),
                );
              },
            ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  final String name;
  final _RowStatus status;
  final Uint8List? wallpaper;
  final VoidCallback onTap;
  final VoidCallback onStatusTap;

  const _MachineCard({
    required this.name,
    required this.status,
    required this.wallpaper,
    required this.onTap,
    required this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wallpaperBytes = wallpaper;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: wallpaperBytes != null
                      ? Image.memory(wallpaperBytes, fit: BoxFit.cover)
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.desktop_windows, size: 18, color: colorScheme.primary),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    _ConnectionChip(status: status, onTap: onStatusTap),
                  ],
                ),
              ),
            ],
          ),
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
      _RowStatus.connecting => (colorScheme.secondary, 'Connecting'),
      _RowStatus.p2p => (palette.statusOnline, 'P2P'),
      _RowStatus.routed => (palette.statusRouted, 'Routed'),
      _RowStatus.offline => (palette.statusOffline, 'Offline'),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
