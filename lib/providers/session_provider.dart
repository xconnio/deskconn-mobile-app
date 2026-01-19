import 'package:deskconn_mobile_app/core/wamp/wamp_client.dart';
import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';

import '../screens/sign_in_screen.dart';

class SessionProvider extends ChangeNotifier {
  final _client = WampClient();

  Session? session;
  Map<String, dynamic>? account;
  String? error;


  bool _isLoading = false;
  bool loggedIn = false;


  bool get isLoading => _isLoading;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  List<Map<String, dynamic>> desktops = [];
  bool desktopsLoading = false;


  Future<void> login(String email, String password) async {
    error = null;
    _setLoading(true);
    notifyListeners();

    try {
      session = await _client.connectCra(
        email: email,
        password: password,
      );

      final res = await session!.call(
        "io.xconn.deskconn.account.get",
      );

      if (res.args == null || res.args!.isEmpty) {
        throw Exception("Empty account response");
      }

      account = Map<String, dynamic>.from(res.args![0]);

      await loadDesktops();

      notifyListeners();
      loggedIn = true;
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
      final res = await session!.call(
        "io.xconn.deskconn.desktop.list",
      );

      desktops = List<Map<String, dynamic>>.from(res.args ?? []);
    } catch (e) {
      error = "Failed to load desktops";
    } finally {
      desktopsLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      await session?.close();
    } catch (_) {}

    session = null;
    loggedIn = false;
    _setLoading(false);


    notifyListeners();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SignInScreen(),
      ),
          (route) => false,
    );
  }
}
