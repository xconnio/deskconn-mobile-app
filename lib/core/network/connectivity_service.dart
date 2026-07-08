import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

// App-wide network reachability signal. Nothing in this app previously knew
// whether the device had any connectivity at all — every failure (no signal,
// Wi-Fi with no internet, server down, desktop offline) looked identical to
// the user, and nothing reconnected automatically when connectivity came back.
//
// Lives for the app's lifetime like the other singletons in core/ (e.g.
// DesktopConnectionManager), so the underlying stream subscription is never
// cancelled — that's intentional, not a leak.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._() {
    _init();
  }

  bool hasConnection = true;

  Future<void> _init() async {
    try {
      hasConnection = _hasAny(await Connectivity().checkConnectivity());
    } catch (_) {}
    Connectivity().onConnectivityChanged.listen((results) {
      final next = _hasAny(results);
      if (next == hasConnection) return;
      hasConnection = next;
      notifyListeners();
    });
  }

  bool _hasAny(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);
}
