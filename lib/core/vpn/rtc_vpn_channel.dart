import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:deskconn_mobile_app/core/vpn/vpn_tunnel.dart';

class RtcVpnChannel implements VpnChannel {
  RtcVpnChannel(this._channel) {
    _stateSubscription = _channel.stateChangeStream.listen((state) {
      if (state == RTCDataChannelState.RTCDataChannelClosing || state == RTCDataChannelState.RTCDataChannelClosed) {
        _markClosed();
      }
    });
    if (_channel.state == RTCDataChannelState.RTCDataChannelClosed) _markClosed();
  }

  final RTCDataChannel _channel;
  final _closed = Completer<void>();
  StreamSubscription<RTCDataChannelState>? _stateSubscription;

  void _markClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Stream<VpnMessage> get messages => _channel.messageStream.map(
    (message) => message.isBinary ? VpnMessage.binary(message.binary) : VpnMessage.text(message.text),
  );

  @override
  Future<void> get closed => _closed.future;

  @override
  int get bufferedAmount => _channel.bufferedAmount ?? 0;

  @override
  Future<void> sendText(String text) => _channel.send(RTCDataChannelMessage(text));

  @override
  Future<void> sendBinary(Uint8List data) => _channel.send(RTCDataChannelMessage.fromBinary(data));

  @override
  Future<void> close() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _markClosed();
    try {
      await _channel.close();
    } catch (_) {}
  }
}
