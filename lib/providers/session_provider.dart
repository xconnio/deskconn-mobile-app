import 'package:deskconn_mobile_app/core/device/cryptosign_keys.dart';
import 'package:deskconn_mobile_app/core/device/device_identity.dart';
import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionProvider extends ChangeNotifier {
  final _client = WampClient();

  Session? session;
  Map<String, dynamic>? account;
  String? error;

  List<Map<String, dynamic>> organizations = [];
  List<Map<String, dynamic>> invitationsInbox = [];
  List<Map<String, dynamic>> invitationsOutbox = [];

  bool _isLoading = false;
  bool loggedIn = false;

  bool get isLoading => _isLoading;

  bool orgLoading = false;
  bool invitationLoading = false;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void updateAccount(Map<String, dynamic> newAccountData) {
    account = newAccountData;
    notifyListeners();
  }

  List<Map<String, dynamic>> desktops = [];
  bool desktopsLoading = false;

  Future<void> login(String email, String password) async {
    error = null;
    _setLoading(true);

    try {
      session = await _client.connectCra(email: email, password: password);

      final res = await session!.call("io.xconn.deskconn.account.get");

      if (res.args.isEmpty) {
        throw Exception("Empty account response");
      }

      account = Map<String, dynamic>.from(res.args[0]);

      await loadDesktops();
      await loadOrganizations();
      await loadInvitations();

      loggedIn = true;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_email', email);
      await _registerDeviceIfNeeded();
    } catch (e) {
      error = e.toString();
      _setLoading(false);
      session = null;
      account = null;
      desktops.clear();
      notifyListeners();
    }
    _setLoading(false);
  }

  Future<void> loadDesktops() async {
    if (session == null) return;

    desktopsLoading = true;
    notifyListeners();

    try {
      final res = await session!.call("io.xconn.deskconn.desktop.list");
      desktops = List<Map<String, dynamic>>.from(res.args);
    } catch (e) {
      error = "Failed to load desktops";
    } finally {
      desktopsLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      final identity = await DeviceIdentity.deviceId();

      if (identity != null) {
        try {
          await session?.call('io.xconn.deskconn.device.delete', args: [identity]);
        } catch (_) {}
      }

      await session?.close();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await DeviceIdentity.clear();

    session = null;
    account = null;
    desktops.clear();
    organizations.clear();
    invitationsInbox.clear();
    invitationsOutbox.clear();

    loggedIn = false;
    _setLoading(false);

    notifyListeners();
  }

  Future<void> _registerDeviceIfNeeded() async {
    final exists = await DeviceIdentity.exists();
    if (exists) return;

    final privateKey = CryptoSignKeys.generatePrivateKey();
    final publicKey = CryptoSignKeys.derivePublicKey(privateKey);

    final deviceId = 'mobile-${DateTime.now().millisecondsSinceEpoch}';

    final res = await session!.call('io.xconn.deskconn.device.create', args: [deviceId, publicKey]);

    if (res.args.isEmpty) {
      throw Exception('Device registration failed');
    }

    await DeviceIdentity.save(deviceId: deviceId, privateKey: privateKey);
  }

  Future<void> loadOrganizations() async {
    if (session == null) return;

    orgLoading = true;
    notifyListeners();

    try {
      final res = await session!.call("io.xconn.deskconn.organization.list");

      organizations = List<Map<String, dynamic>>.from(res.args);
    } catch (_) {
      error = "Failed to load organizations";
    }

    orgLoading = false;
    notifyListeners();
  }

  Future<void> loadInvitations() async {
    if (session == null) return;

    invitationLoading = true;
    notifyListeners();

    try {
      final inboxRes = await session!.call("io.xconn.deskconn.organization.invitation.inbox.list");

      final outboxRes = await session!.call("io.xconn.deskconn.organization.invitation.outbox.list");

      invitationsInbox = List<Map<String, dynamic>>.from(inboxRes.args);

      invitationsOutbox = List<Map<String, dynamic>>.from(outboxRes.args);
    } catch (_) {
      error = "Failed to load invitations";
    }

    invitationLoading = false;
    notifyListeners();
  }

  Future<void> respondInvitation(String invitationId, String action) async {
    await session!.call("io.xconn.deskconn.organization.invitation.respond", args: [invitationId, action]);

    await loadInvitations();
    await loadOrganizations();
  }

  Future<void> createInvitation(String orgId, String email, String role) async {
    await session!.call("io.xconn.deskconn.organization.invitation.create", args: [orgId, email, role]);

    await loadInvitations();
  }
}
