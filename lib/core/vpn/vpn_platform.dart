import 'dart:async';

import 'package:flutter/services.dart';

abstract class VpnPlatform {
  Future<bool> prepare();
  Future<void> start({required String address, required int prefix, required int mtu});
  Future<void> stop();
  void write(Uint8List packet);
  Stream<Uint8List> get packets;
  Stream<void> get revoked;
}

class AndroidVpnPlatform implements VpnPlatform {
  AndroidVpnPlatform._() {
    _control.setMethodCallHandler((call) async {
      if (call.method == 'revoked') _revoked.add(null);
    });
  }

  static final AndroidVpnPlatform instance = AndroidVpnPlatform._();

  static const _control = MethodChannel('deskconn/vpn');
  static const _activity = MethodChannel('deskconn/vpn_permission');
  static const _packetEvents = EventChannel('deskconn/vpn_packets');

  final _revoked = StreamController<void>.broadcast();
  final List<Uint8List> _outgoing = [];
  bool _flushScheduled = false;

  @override
  Future<bool> prepare() async => await _activity.invokeMethod<bool>('prepare') ?? false;

  @override
  Future<void> start({required String address, required int prefix, required int mtu}) =>
      _control.invokeMethod('start', {'address': address, 'prefix': prefix, 'mtu': mtu});

  @override
  Future<void> stop() => _control.invokeMethod('stop');

  @override
  void write(Uint8List packet) {
    _outgoing.add(packet);
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      final batch = List<Uint8List>.of(_outgoing);
      _outgoing.clear();
      unawaited(_control.invokeMethod('write', batch).catchError((Object _) {}));
    });
  }

  @override
  Stream<Uint8List> get packets =>
      _packetEvents.receiveBroadcastStream().expand((event) => (event as List).cast<Uint8List>());

  @override
  Stream<void> get revoked => _revoked.stream;
}
