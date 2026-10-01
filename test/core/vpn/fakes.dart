import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:deskconn_mobile_app/core/vpn/vpn_controller.dart';
import 'package:deskconn_mobile_app/core/vpn/vpn_platform.dart';
import 'package:deskconn_mobile_app/core/vpn/vpn_tunnel.dart';

const readyFrame = '{"type":"vpn-ready","server_ip":"10.66.0.1","client_cidr":"10.66.0.2/24","mtu":1200}';

class FakeVpnChannel implements VpnChannel {
  final incoming = StreamController<VpnMessage>.broadcast();
  final _closed = Completer<void>();
  final sentText = <String>[];
  final sentBinary = <Uint8List>[];
  int buffered = 0;
  bool replyReady = true;
  bool closeOnOpen = false;

  void receiveText(String text) => incoming.add(VpnMessage.text(text));
  void receivePacket(List<int> bytes) => incoming.add(VpnMessage.binary(Uint8List.fromList(bytes)));
  void remoteClose() {
    if (!_closed.isCompleted) _closed.complete();
  }

  bool get isClosed => _closed.isCompleted;

  @override
  Stream<VpnMessage> get messages => incoming.stream;

  @override
  Future<void> get closed => _closed.future;

  @override
  int get bufferedAmount => buffered;

  @override
  Future<void> sendText(String text) async {
    sentText.add(text);
    final frame = jsonDecode(text) as Map;
    if (frame['type'] != 'vpn-open') return;
    if (closeOnOpen) {
      scheduleMicrotask(remoteClose);
    } else if (replyReady) {
      scheduleMicrotask(() => receiveText(readyFrame));
    }
  }

  @override
  Future<void> sendBinary(Uint8List data) async => sentBinary.add(data);

  @override
  Future<void> close() async => remoteClose();
}

class FakeVpnPlatform implements VpnPlatform {
  bool grant = true;
  final calls = <String>[];
  Map<String, Object>? startArgs;
  final written = <Uint8List>[];
  final outgoing = StreamController<Uint8List>.broadcast();
  final _revoked = StreamController<void>.broadcast();

  void emitPacket(List<int> bytes) => outgoing.add(Uint8List.fromList(bytes));
  void revoke() => _revoked.add(null);

  @override
  Future<bool> prepare() async {
    calls.add('prepare');
    return grant;
  }

  @override
  Future<void> start({required String address, required int prefix, required int mtu}) async {
    calls.add('start');
    startArgs = {'address': address, 'prefix': prefix, 'mtu': mtu};
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  void write(Uint8List packet) => written.add(packet);

  @override
  Stream<Uint8List> get packets => outgoing.stream;

  @override
  Stream<void> get revoked => _revoked.stream;
}

class FakeVpnLink implements VpnLink {
  FakeVpnLink(this.channel);

  @override
  final FakeVpnChannel channel;
  int releases = 0;

  @override
  Future<void> release() async => releases++;
}
