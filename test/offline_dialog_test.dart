import 'package:deskconn_mobile_app/widgets/offline_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnectivity extends ChangeNotifier {
  bool online = false;

  void set(bool value) {
    online = value;
    notifyListeners();
  }

  bool get listening => hasListeners;
}

void main() {
  late _FakeConnectivity connectivity;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    connectivity = _FakeConnectivity();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
  }

  void showOffline() {
    showDialog<void>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (_) => OfflineDialog(connectivity: connectivity, isOnline: () => connectivity.online),
    );
  }

  testWidgets('shows the offline message with a settings shortcut', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();

    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.textContaining('Check your Wi-Fi or mobile data'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('closes when connectivity comes back', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();

    connectivity.set(true);
    await tester.pumpAndSettle();

    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('closes on its own when connectivity returned before it was built', (tester) async {
    await pumpHome(tester);
    showOffline();
    connectivity.set(true);
    await tester.pumpAndSettle();

    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('stays open while still offline', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();

    connectivity.set(false);
    await tester.pumpAndSettle();

    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('back does not dismiss it while offline', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('closes only itself when another route is above it', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('above'))));
    await tester.pumpAndSettle();

    connectivity.set(true);
    await tester.pumpAndSettle();

    expect(find.text('above'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('stops listening once closed', (tester) async {
    await pumpHome(tester);
    showOffline();
    await tester.pumpAndSettle();
    connectivity.set(true);
    await tester.pumpAndSettle();

    expect(connectivity.listening, isFalse);
  });
}
