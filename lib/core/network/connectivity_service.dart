import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

// App-wide network reachability signal. Nothing in this app previously knew
// whether the device had any connectivity at all — every failure (no signal,
// Wi-Fi with no internet, server down, desktop offline) looked identical to
// the user, and nothing reconnected automatically when connectivity came back.
//
// Lives for the app's lifetime like the other singletons in core/ (e.g.
// DesktopConnectionManager), so the underlying stream subscription is never
// cancelled — that's intentional, not a leak.
class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;
  ConnectivityService._() {
    WidgetsBinding.instance.addObserver(this);
    ready = _refresh();
    Connectivity().onConnectivityChanged.listen((results) => _apply(_hasAny(results)));
    // connectivity_plus's change stream is known to miss transitions on some
    // Android OEMs/versions (most visibly a fast airplane-mode toggle while
    // the app stays in the foreground, so didChangeAppLifecycleState never
    // fires either). This poll is the backstop that guarantees we notice
    // within a bounded time even if both the stream and the lifecycle hook
    // stay silent.
    Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_refresh()));
  }

  bool hasConnection = true;

  // Callers that need an accurate reading at startup (not the optimistic
  // `true` default above) should await this before checking hasConnection.
  late final Future<void> ready;

  // The connectivity-changed stream is unreliable while backgrounded (Android
  // Doze / iOS background limits can suppress the broadcast), so a device
  // that went offline mid-background can resume showing a stale "online"
  // reading. Re-checking on every resume closes that gap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      _apply(_hasAny(await Connectivity().checkConnectivity()));
    } catch (_) {}
  }

  void _apply(bool next) {
    if (next == hasConnection) return;
    hasConnection = next;
    notifyListeners();
  }

  bool _hasAny(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);
}
