import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

import 'terminal_encryption.dart';

const int _kindControl = 0;
const int _kindData = 1;
const Duration _requestTimeout = Duration(seconds: 15);
const Duration _pingInterval = Duration(seconds: 10);
const String shellChannelLabel = 'shell';

class ShellStreamException implements Exception {
  ShellStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ShellChannelUnavailableException extends ShellStreamException {
  ShellChannelUnavailableException() : super('shell channel is not open');
}

class ShellHandle {
  ShellHandle({
    required this.shellId,
    required void Function(Uint8List bytes) send,
    required void Function(int cols, int rows) resize,
    required Future<void> Function() close,
  }) : _send = send,
       _resize = resize,
       _close = close;

  final String shellId;
  final void Function(Uint8List bytes) _send;
  final void Function(int cols, int rows) _resize;
  final Future<void> Function() _close;

  void send(Uint8List bytes) => _send(bytes);
  void resize(int cols, int rows) => _resize(cols, rows);
  Future<void> close() => _close();
}

Future<ShellHandle> openShell(
  web_rtc.WebRTCSession session,
  int cols,
  int rows,
  void Function(Uint8List data) onData,
  void Function() onClose,
) async {
  final channel = await session.extraChannel(shellChannelLabel);
  if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
    throw ShellChannelUnavailableException();
  }
  final enc = await Encryption.create();
  final peerKeyCompleter = Completer<Uint8List>();
  final ackCompleter = Completer<Map<String, dynamic>>();
  var closedByUs = false;
  Timer? pingTimer;

  Uint8List envelope(int kind, List<int> plaintext) {
    return Uint8List.fromList([kind, ...enc.encrypt(plaintext)]);
  }

  void sendControl(Map<String, dynamic> msg) {
    try {
      channel.send(RTCDataChannelMessage.fromBinary(envelope(_kindControl, utf8.encode(jsonEncode(msg)))));
    } catch (_) {}
  }

  Future<void> closeChannel() async {
    if (closedByUs) return;
    closedByUs = true;
    pingTimer?.cancel();
    try {
      await channel.close();
    } catch (_) {}
  }

  channel.onMessage = (RTCDataChannelMessage msg) {
    if (!peerKeyCompleter.isCompleted) {
      if (msg.isBinary) {
        peerKeyCompleter.completeError(ShellStreamException('expected plaintext key-exchange frame first'));
        return;
      }
      try {
        final peerKeyB64 = (jsonDecode(msg.text) as Map<String, dynamic>)['public_key'] as String;
        peerKeyCompleter.complete(base64Decode(peerKeyB64));
      } catch (e) {
        peerKeyCompleter.completeError(e);
      }
      return;
    }

    if (!msg.isBinary || msg.binary.isEmpty) return;
    final kind = msg.binary[0];
    final Uint8List plaintext;
    try {
      plaintext = enc.decrypt(msg.binary.sublist(1));
    } catch (_) {
      return;
    }

    if (kind == _kindControl) {
      if (!ackCompleter.isCompleted) {
        ackCompleter.complete(jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>);
      }
      return;
    }
    if (kind == _kindData) onData(plaintext);
  };

  channel.onDataChannelState = (state) {
    if (state == RTCDataChannelState.RTCDataChannelClosing || state == RTCDataChannelState.RTCDataChannelClosed) {
      pingTimer?.cancel();
      if (!peerKeyCompleter.isCompleted) {
        peerKeyCompleter.completeError(ShellStreamException('shell channel closed before key exchange'));
      }
      if (!ackCompleter.isCompleted) {
        ackCompleter.completeError(ShellStreamException('shell channel closed before it started'));
      }
      if (closedByUs) return;
      closedByUs = true;
      onClose();
    }
  };

  await channel.send(RTCDataChannelMessage(jsonEncode({'public_key': base64Encode(enc.clientPublicKey)})));
  final peerKey = await peerKeyCompleter.future.timeout(_requestTimeout);
  await enc.acceptServerKey(Uint8List.fromList([...utf8.encode('KEY:'), ...peerKey]));

  sendControl({'op': 'size', 'cols': cols, 'rows': rows});

  final ack = await ackCompleter.future.timeout(_requestTimeout);
  final error = ack['error'] as String?;
  if (error != null) {
    await closeChannel();
    throw ShellStreamException(error);
  }

  pingTimer = Timer.periodic(_pingInterval, (_) => sendControl({'op': 'ping'}));

  return ShellHandle(
    shellId: ack['shell_id'] as String? ?? '',
    send: (bytes) {
      try {
        channel.send(RTCDataChannelMessage.fromBinary(envelope(_kindData, bytes)));
      } catch (_) {}
    },
    resize: (c, r) => sendControl({'op': 'size', 'cols': c, 'rows': r}),
    close: closeChannel,
  );
}
