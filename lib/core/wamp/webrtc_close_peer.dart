// ignore: implementation_imports
import 'package:xconn/src/exception.dart' show PeerClosedException;
import 'package:xconn/xconn.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

class WebRTCClosePeer implements Peer {
  WebRTCClosePeer(this._inner);

  final Peer _inner;

  @override
  Future<Object> read() async {
    try {
      return await _inner.read();
    } on web_rtc.WebRTCPeerClosedException catch (e) {
      throw PeerClosedException(e.toString());
    }
  }

  @override
  Future<void> write(Object data) => _inner.write(data);

  @override
  Future<void> close() => _inner.close();
}
