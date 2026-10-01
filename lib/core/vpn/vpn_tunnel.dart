import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const String kVpnChannelLabel = 'vpn';
const String kVpnFrameOpen = 'vpn-open';
const String kVpnFrameReady = 'vpn-ready';
const Duration kVpnHandshakeTimeout = Duration(seconds: 15);
const int kVpnSendBufferHigh = 512 * 1024;

class VpnMessage {
  final String? text;
  final Uint8List? binary;

  const VpnMessage.text(String this.text) : binary = null;
  const VpnMessage.binary(Uint8List this.binary) : text = null;
}

abstract class VpnChannel {
  Stream<VpnMessage> get messages;
  Future<void> get closed;
  int get bufferedAmount;
  Future<void> sendText(String text);
  Future<void> sendBinary(Uint8List data);
  Future<void> close();
}

class VpnReady {
  final String serverIp;
  final String clientAddress;
  final int clientPrefix;
  final int mtu;

  const VpnReady({required this.serverIp, required this.clientAddress, required this.clientPrefix, required this.mtu});

  static VpnReady? tryParse(String text) {
    try {
      final frame = jsonDecode(text);
      if (frame is! Map || frame['type'] != kVpnFrameReady) return null;
      final cidr = (frame['client_cidr'] as String).split('/');
      final mtu = frame['mtu'] as int;
      if (cidr.length != 2 || mtu <= 0) return null;
      return VpnReady(
        serverIp: frame['server_ip'] as String,
        clientAddress: cidr[0],
        clientPrefix: int.parse(cidr[1]),
        mtu: mtu,
      );
    } catch (_) {
      return null;
    }
  }
}

class VpnRejectedException implements Exception {
  const VpnRejectedException();

  @override
  String toString() => 'The desktop closed the VPN channel before the tunnel was ready';
}

class VpnTunnel {
  VpnTunnel(this.channel, {this.handshakeTimeout = kVpnHandshakeTimeout});

  final VpnChannel channel;
  final Duration handshakeTimeout;

  final _packets = StreamController<Uint8List>();
  StreamSubscription<VpnMessage>? _subscription;
  bool _ready = false;
  int droppedPackets = 0;

  Stream<Uint8List> get packets => _packets.stream;

  Future<void> get closed => channel.closed;

  Future<VpnReady> open() async {
    final ready = Completer<VpnReady>();
    _subscription = channel.messages.listen((message) {
      final text = message.text;
      if (text != null) {
        if (_ready || ready.isCompleted) return;
        final frame = VpnReady.tryParse(text);
        if (frame != null) ready.complete(frame);
        return;
      }
      if (_ready) _packets.add(message.binary!);
    });

    unawaited(
      channel.closed.then((_) {
        if (!ready.isCompleted) ready.completeError(const VpnRejectedException());
        unawaited(_packets.close());
      }),
    );

    await channel.sendText(jsonEncode({'type': kVpnFrameOpen}));

    try {
      final frame = await ready.future.timeout(handshakeTimeout);
      _ready = true;
      return frame;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  void send(Uint8List packet) {
    if (!_ready) return;
    if (channel.bufferedAmount + packet.length > kVpnSendBufferHigh) {
      droppedPackets++;
      return;
    }
    unawaited(channel.sendBinary(packet).catchError((Object _) {}));
  }

  Future<void> close() async {
    _ready = false;
    await _subscription?.cancel();
    _subscription = null;
    await channel.close();
    if (!_packets.isClosed) await _packets.close();
  }
}
