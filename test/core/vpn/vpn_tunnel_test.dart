import 'dart:async';
import 'dart:convert';

import 'package:deskconn_mobile_app/core/vpn/vpn_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'fakes.dart';

Uint8List vpnBytes(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('VpnReady.tryParse', () {
    test('parses the frame the desktop sends', () {
      final ready = VpnReady.tryParse(readyFrame)!;
      expect(ready.serverIp, '10.66.0.1');
      expect(ready.clientAddress, '10.66.0.2');
      expect(ready.clientPrefix, 24);
      expect(ready.mtu, 1200);
    });

    test('rejects other frame types, malformed json and bad values', () {
      expect(VpnReady.tryParse('{"type":"vpn-open"}'), isNull);
      expect(VpnReady.tryParse('not json'), isNull);
      expect(VpnReady.tryParse('{"type":"vpn-ready","server_ip":"x","client_cidr":"10.66.0.2","mtu":1200}'), isNull);
      expect(VpnReady.tryParse('{"type":"vpn-ready","server_ip":"x","client_cidr":"10.66.0.2/24","mtu":0}'), isNull);
    });
  });

  group('VpnTunnel.open', () {
    test('sends the open frame first, as text', () async {
      final channel = FakeVpnChannel();
      await VpnTunnel(channel).open();

      expect(channel.sentText, hasLength(1));
      expect(jsonDecode(channel.sentText.single), {'type': 'vpn-open'});
    });

    test('completes with the desktop ready frame', () async {
      final ready = await VpnTunnel(FakeVpnChannel()).open();
      expect(ready.clientAddress, '10.66.0.2');
      expect(ready.mtu, 1200);
    });

    test('is rejected when the desktop closes the channel instead of answering', () async {
      final channel = FakeVpnChannel()..closeOnOpen = true;
      await expectLater(VpnTunnel(channel).open(), throwsA(isA<VpnRejectedException>()));
    });

    test('times out and closes the channel when no ready frame arrives', () async {
      final channel = FakeVpnChannel()..replyReady = false;
      final tunnel = VpnTunnel(channel, handshakeTimeout: const Duration(milliseconds: 50));

      await expectLater(tunnel.open(), throwsA(isA<TimeoutException>()));
      expect(channel.isClosed, isTrue);
    });

    test('skips unrelated text frames until the real ready frame', () async {
      final channel = FakeVpnChannel()..replyReady = false;
      final opening = VpnTunnel(channel).open();
      await Future<void>.delayed(Duration.zero);
      channel.receiveText('{"type":"something-else"}');
      channel.receiveText(readyFrame);

      expect((await opening).mtu, 1200);
    });
  });

  group('packet forwarding', () {
    test('forwards binary messages as packets only after the tunnel is ready', () async {
      final channel = FakeVpnChannel()..replyReady = false;
      final tunnel = VpnTunnel(channel);
      final received = <List<int>>[];
      tunnel.packets.listen(received.add);
      final opening = tunnel.open();
      await Future<void>.delayed(Duration.zero);

      channel.receivePacket([0x45, 1]);
      channel.receiveText(readyFrame);
      await opening;
      channel.receivePacket([0x45, 2]);
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        [0x45, 2],
      ]);
    });

    test('does not treat text frames after ready as packets', () async {
      final channel = FakeVpnChannel();
      final tunnel = VpnTunnel(channel);
      final received = <List<int>>[];
      tunnel.packets.listen(received.add);
      await tunnel.open();

      channel.receiveText(readyFrame);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('sends packets as binary messages', () async {
      final channel = FakeVpnChannel();
      final tunnel = VpnTunnel(channel);
      await tunnel.open();

      tunnel.send(vpnBytes([0x45, 9]));
      await Future<void>.delayed(Duration.zero);

      expect(channel.sentBinary.single, [0x45, 9]);
    });

    test('ignores packets sent before the tunnel is ready', () async {
      final channel = FakeVpnChannel();
      VpnTunnel(channel).send(vpnBytes([0x45]));
      await Future<void>.delayed(Duration.zero);

      expect(channel.sentBinary, isEmpty);
    });

    test('drops packets instead of queueing when the channel is backed up', () async {
      final channel = FakeVpnChannel();
      final tunnel = VpnTunnel(channel);
      await tunnel.open();

      channel.buffered = kVpnSendBufferHigh;
      tunnel.send(vpnBytes([0x45, 1]));
      channel.buffered = 0;
      tunnel.send(vpnBytes([0x45, 2]));
      await Future<void>.delayed(Duration.zero);

      expect(tunnel.droppedPackets, 1);
      expect(channel.sentBinary.single, [0x45, 2]);
    });

    test('ends the packet stream when the desktop closes the channel', () async {
      final channel = FakeVpnChannel();
      final tunnel = VpnTunnel(channel);
      final done = Completer<void>();
      tunnel.packets.listen(null, onDone: done.complete);
      await tunnel.open();

      channel.remoteClose();

      await expectLater(done.future.timeout(const Duration(seconds: 1)), completes);
    });
  });
}
