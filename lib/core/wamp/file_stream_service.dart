import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

// Number of "file-stream-N" data channels pre-negotiated at WebRTC offer time
// (see desktop_connection_manager.dart's OfferConfig.additionalChannels).
// deskconnd closes each one after replying to a single range request (see
// filestreamchannel.go's serveFileStreamChannel), and channels can only be
// created reliably as part of the initial offer on some clients (observed on
// Android) — so this bounds how many byte-range reads a single connection can
// serve for its whole lifetime, not just per file: FileStreamServer maps each
// distinct HTTP Range request to its own openRange call, and a single video
// preview alone can easily use half a dozen (an initial probe, an MP4 "moov"
// atom probe near the end of the file, then further reads as playback
// buffers or seeks). Sized generously so reopening/seeking a few previews in
// one connection session doesn't exhaust it; once it does, further range
// reads fail and the player errors out for that stream. The complete fix is
// deskconnd wiring up its already-written persistent "file-stream" session
// channel (HandleSessionReady in filestreamchannel.go, currently dead code)
// so a connection isn't capped at a fixed number of range reads at all.
const int kFileStreamChannelPoolSize = 48;

List<String> fileStreamChannelLabels() => List.generate(kFileStreamChannelPoolSize, (i) => 'file-stream-$i');

class FileStreamPoolExhaustedException implements Exception {
  @override
  String toString() => 'file-stream channel pool exhausted for this connection';
}

class FileStreamRangeResult {
  FileStreamRangeResult({required this.size, required this.offset, required this.length, required this.chunks});

  final int size;
  final int offset;
  final int length;
  final Stream<Uint8List> chunks;
}

// Reads byte ranges from deskconnd over pre-negotiated raw WebRTC data
// channels (see filestreamchannel.go for the wire protocol: a JSON request,
// a JSON header frame, then binary chunks until the channel closes).
class FileStreamService {
  FileStreamService(this._session);

  final web_rtc.WebRTCSession _session;
  int _nextChannel = 0;

  Future<FileStreamRangeResult> openRange(String path, int offset, int length) async {
    if (_nextChannel >= kFileStreamChannelPoolSize) {
      throw FileStreamPoolExhaustedException();
    }
    final label = 'file-stream-${_nextChannel++}';
    final channel = await _session.extraChannel(label);

    final headerCompleter = Completer<Map<String, dynamic>>();
    final chunkController = StreamController<Uint8List>();

    channel.onMessage = (RTCDataChannelMessage msg) {
      if (!headerCompleter.isCompleted) {
        if (msg.isBinary) {
          headerCompleter.completeError(Exception('expected header text frame first'));
          return;
        }
        try {
          headerCompleter.complete(jsonDecode(msg.text) as Map<String, dynamic>);
        } catch (e) {
          headerCompleter.completeError(e);
        }
        return;
      }
      if (msg.isBinary && !chunkController.isClosed) {
        chunkController.add(msg.binary);
      }
    };

    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosing || state == RTCDataChannelState.RTCDataChannelClosed) {
        if (!headerCompleter.isCompleted) {
          headerCompleter.completeError(Exception('file-stream channel closed before header'));
        }
        if (!chunkController.isClosed) {
          unawaited(chunkController.close());
        }
      }
    };

    await channel.send(RTCDataChannelMessage(jsonEncode({'path': path, 'offset': offset, 'length': length})));

    final header = await headerCompleter.future.timeout(const Duration(seconds: 15));
    return FileStreamRangeResult(
      size: header['size'] as int,
      offset: header['offset'] as int,
      length: header['length'] as int,
      chunks: chunkController.stream,
    );
  }
}
