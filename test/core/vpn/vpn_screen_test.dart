import 'package:deskconn_mobile_app/core/vpn/vpn_controller.dart';
import 'package:deskconn_mobile_app/screens/vpn_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'vpn_controller_test.dart' show desktop;

Future<void> settleReal(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  late FakeVpnChannel channel;
  late VpnController vpn;

  setUp(() {
    channel = FakeVpnChannel();
    vpn = VpnController(platform: FakeVpnPlatform(), openLink: (_) async => FakeVpnLink(channel));
  });

  Future<void> pumpScreen(WidgetTester tester, String realm) => tester.pumpWidget(
    MaterialApp(
      home: VpnScreen(config: desktop(realm), controller: vpn),
    ),
  );

  testWidgets('starts disconnected with a connect button and the setup hint', (tester) async {
    await pumpScreen(tester, 'realm-1');

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.textContaining('deskconn vpn start'), findsOneWidget);
  });

  testWidgets('connect shows the connected state and a disconnect button', (tester) async {
    await pumpScreen(tester, 'realm-1');

    await tester.tap(find.text('Connect'));
    await settleReal(tester);

    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('10.66.0.2'), findsOneWidget);
    expect(find.textContaining('deskconn vpn start'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await settleReal(tester);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('shows the reason when the desktop rejects the tunnel', (tester) async {
    channel.closeOnOpen = true;
    await pumpScreen(tester, 'realm-1');

    await tester.tap(find.text('Connect'));
    await settleReal(tester);

    expect(find.textContaining('isn\'t sharing its connection'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('another desktop sees that the VPN is busy elsewhere', (tester) async {
    await tester.runAsync(() => vpn.connect(desktop('realm-1')));
    await pumpScreen(tester, 'realm-2');

    expect(find.textContaining('currently connected through office-pc'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);
  });
}
