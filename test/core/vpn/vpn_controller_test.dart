import 'dart:async';

import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/core/vpn/vpn_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

DesktopSessionLaunchConfig desktop(String realm, {String name = 'office-pc'}) => DesktopSessionLaunchConfig(
  sessionKey: 'vpn:$realm',
  desktopName: name,
  realm: realm,
  authId: 'me@example.com',
  privateKey: 'key',
  webRtcEnabled: true,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeVpnPlatform platform;
  late FakeVpnChannel channel;
  late FakeVpnLink link;
  late int linksOpened;
  late VpnController vpn;

  setUp(() {
    platform = FakeVpnPlatform();
    channel = FakeVpnChannel();
    link = FakeVpnLink(channel);
    linksOpened = 0;
    vpn = VpnController(
      platform: platform,
      openLink: (_) async {
        linksOpened++;
        return link;
      },
    );
  });

  test('connects: permission, tunnel handshake, then the device interface', () async {
    final states = <VpnStatus>[];
    vpn.addListener(() => states.add(vpn.status));

    await vpn.connect(desktop('realm-1'));

    expect(states, [VpnStatus.connecting, VpnStatus.connected]);
    expect(platform.calls, ['prepare', 'start']);
    expect(platform.startArgs, {'address': '10.66.0.2', 'prefix': 24, 'mtu': 1200});
    expect(vpn.isConnectedTo('realm-1'), isTrue);
    expect(vpn.error, isNull);
  });

  test('moves packets both ways once connected', () async {
    await vpn.connect(desktop('realm-1'));

    platform.emitPacket([0x45, 1]);
    channel.receivePacket([0x45, 2]);
    await settle();

    expect(channel.sentBinary.single, [0x45, 1]);
    expect(platform.written.single, [0x45, 2]);
  });

  test('stops before touching the desktop when VPN permission is denied', () async {
    platform.grant = false;

    await vpn.connect(desktop('realm-1'));

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, 'VPN permission was not granted.');
    expect(linksOpened, 0);
    expect(platform.calls, isNot(contains('start')));
  });

  test('explains how to fix it when the desktop is not sharing its connection', () async {
    channel.closeOnOpen = true;

    await vpn.connect(desktop('realm-1', name: 'razer'));

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, contains('razer isn\'t sharing its connection'));
    expect(vpn.error, contains('deskconn vpn start'));
    expect(platform.calls, isNot(contains('start')));
    expect(link.releases, 1);
  });

  test('reports and cleans up when an established tunnel is lost', () async {
    await vpn.connect(desktop('realm-1'));

    channel.remoteClose();
    await settle();
    await settle();

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, 'The VPN connection to office-pc was lost.');
    expect(platform.calls.last, 'stop');
    expect(link.releases, 1);
  });

  test('disconnect tears everything down without an error', () async {
    await vpn.connect(desktop('realm-1'));

    await vpn.disconnect();

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, isNull);
    expect(platform.calls.last, 'stop');
    expect(channel.isClosed, isTrue);
    expect(link.releases, 1);
  });

  test('cancelling while connecting never ends up connected', () async {
    final gate = Completer<void>();
    vpn = VpnController(
      platform: platform,
      openLink: (_) async {
        await gate.future;
        return link;
      },
    );

    final connecting = vpn.connect(desktop('realm-1'));
    await settle();
    await vpn.disconnect();
    gate.complete();
    await connecting;

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, isNull);
    expect(platform.calls, isNot(contains('start')));
  });

  test('the system revoking the VPN disconnects it', () async {
    await vpn.connect(desktop('realm-1'));

    platform.revoke();
    await settle();
    await settle();

    expect(vpn.status, VpnStatus.disconnected);
    expect(link.releases, 1);
  });

  test('a second connect while connected is ignored', () async {
    await vpn.connect(desktop('realm-1'));
    await vpn.connect(desktop('realm-2'));

    expect(linksOpened, 1);
    expect(vpn.isConnectedTo('realm-1'), isTrue);
    expect(vpn.isConnectedTo('realm-2'), isFalse);
  });

  test('a failure opening the link is reported', () async {
    vpn = VpnController(platform: platform, openLink: (_) async => throw const VpnException('no p2p'));

    await vpn.connect(desktop('realm-1'));

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, 'no p2p');
  });

  test('an unexpected failure is reported in plain words', () async {
    vpn = VpnController(platform: platform, openLink: (_) async => throw StateError('peer closed'));

    await vpn.connect(desktop('realm-1'));

    expect(vpn.status, VpnStatus.disconnected);
    expect(vpn.error, 'Could not connect to office-pc. Check that it is online and try again.');
  });
}
