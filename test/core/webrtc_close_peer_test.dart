import 'dart:async';
import 'dart:typed_data';

import 'package:deskconn_mobile_app/core/wamp/webrtc_close_peer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xconn/xconn.dart' hide Invocation;
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

class _FakePeer implements Peer {
  final _reads = StreamController<Object>();
  late final StreamIterator<Object> _iterator = StreamIterator(_reads.stream);
  Object? readError;
  final written = <Object>[];
  int closeCalls = 0;

  void deliver(Object data) => _reads.add(data);

  void closeChannel() => _reads.close();

  @override
  Future<Object> read() async {
    final error = readError;
    if (error != null) throw error;
    if (await _iterator.moveNext()) return _iterator.current;
    throw web_rtc.WebRTCPeerClosedException('WebRTC data channel closed');
  }

  @override
  Future<void> write(Object data) async => written.add(data);

  @override
  Future<void> close() async => closeCalls++;
}

class _FakeBase implements BaseSession {
  _FakeBase(this._peer);

  final Peer _peer;

  @override
  Serializer serializer() => CBORSerializer();

  @override
  Future<Object> read() => _peer.read();

  @override
  Future<void> write(Object payload) => _peer.write(payload);

  @override
  Future<void> close() => _peer.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<List<Object>> _uncaughtErrorsWhile(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    await body();
    done.complete();
  }, (error, _) => errors.add(error));
  await done.future;
  return errors;
}

void main() {
  group('WebRTCClosePeer', () {
    test('passes received data through untouched', () async {
      final inner = _FakePeer();
      final peer = WebRTCClosePeer(inner);
      final payload = Uint8List.fromList([1, 2, 3]);

      inner.deliver(payload);

      expect(await peer.read(), same(payload));
    });

    test('delegates writes to the wrapped peer', () async {
      final inner = _FakePeer();
      final peer = WebRTCClosePeer(inner);

      await peer.write('hello');

      expect(inner.written, ['hello']);
    });

    test('delegates close to the wrapped peer', () async {
      final inner = _FakePeer();
      await WebRTCClosePeer(inner).close();
      expect(inner.closeCalls, 1);
    });

    test('translates a closed data channel into a non-WebRTC exception', () async {
      final inner = _FakePeer()..closeChannel();

      await expectLater(
        WebRTCClosePeer(inner).read(),
        throwsA(
          isA<Exception>()
              .having((e) => e is web_rtc.WebRTCPeerClosedException, 'is WebRTCPeerClosedException', isFalse)
              .having((e) => e.runtimeType.toString(), 'type', 'PeerClosedException'),
        ),
      );
    });

    test('lets unrelated read errors through unchanged', () async {
      final boom = StateError('boom');
      final inner = _FakePeer()..readError = boom;

      await expectLater(WebRTCClosePeer(inner).read(), throwsA(same(boom)));
    });
  });

  group('xconn Session over a WebRTC data channel', () {
    test('marks the session disconnected when the channel closes', () async {
      final inner = _FakePeer();
      var disconnects = 0;
      late Session session;

      final errors = await _uncaughtErrorsWhile(() async {
        session = Session(_FakeBase(WebRTCClosePeer(inner)));
        session.onDisconnect(() => disconnects++);
        await _settle();
        expect(session.isConnected(), isTrue);

        inner.closeChannel();
        await _settle();
      });

      expect(errors, isEmpty);
      expect(session.isConnected(), isFalse);
      expect(disconnects, 1);
    });

    test('marks the session disconnected when the channel closes without the adapter', () async {
      final inner = _FakePeer();
      var disconnects = 0;
      late Session session;

      final errors = await _uncaughtErrorsWhile(() async {
        session = Session(_FakeBase(inner));
        session.onDisconnect(() => disconnects++);
        await _settle();

        inner.closeChannel();
        await _settle();
      });

      expect(errors, isEmpty);
      expect(session.isConnected(), isFalse);
      expect(disconnects, 1);
    });
  });
}
