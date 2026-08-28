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

  // hasConnection only reflects OS radio state (an interface is
  // associated) — a captive portal, a VPN with no route, or the backend
  // simply being down all still read as "connected". Connect attempts
  // (QUICConnectionManager) report their real outcome here so the app can
  // tell "network up, backend unreachable" apart from genuine offline.
  bool backendReachable = true;

  bool get isOnline => hasConnection && backendReachable;

  void reportBackendReachable() {
    if (backendReachable) return;
    backendReachable = true;
    notifyListeners();
  }

  void reportBackendUnreachable() {
    if (!backendReachable) return;
    backendReachable = false;
    notifyListeners();
  }

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
