import 'package:deskconn_mobile_app/widgets/exit_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MethodCall> calls;

  Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester) async {
    calls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        onNavigationNotification: keepFrameworkHandlingBack,
        builder: (context, child) => ExitGuard(navigatorKey: key, child: child!),
        home: const Scaffold(body: Text('root')),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Iterable<Object?> handlesBackArgs() =>
      calls.where((c) => c.method == 'SystemNavigator.setFrameworkHandlesBack').map((c) => c.arguments);

  bool popped() => calls.any((c) => c.method == 'SystemNavigator.pop');

  testWidgets('back on a pushed screen pops it without asking to close', (tester) async {
    final key = await pumpApp(tester);
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('terminal'))));
    await tester.pumpAndSettle();

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('root'), findsOneWidget);
    expect(find.text('terminal'), findsNothing);
    expect(find.text('Close Deskconn?'), findsNothing);
    expect(popped(), isFalse);
  });

  testWidgets('back on the root screen asks before closing', (tester) async {
    await pumpApp(tester);

    final result = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Close Deskconn?'), findsOneWidget);
    expect(find.text('Do you want to close the app?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(popped(), isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel keeps the app open on the root screen', (tester) async {
    await pumpApp(tester);

    final result = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.text('Close Deskconn?'), findsNothing);
    expect(find.text('root'), findsOneWidget);
    expect(popped(), isFalse);
  });

  testWidgets('close sends the app to the background via SystemNavigator.pop', (tester) async {
    await pumpApp(tester);

    final result = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(popped(), isTrue);
    expect(find.text('Close Deskconn?'), findsNothing);
  });

  testWidgets('back while the dialog is open dismisses only the dialog', (tester) async {
    await pumpApp(tester);

    final first = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Close Deskconn?'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(await first, isTrue);
    expect(find.text('Close Deskconn?'), findsNothing);
    expect(find.text('root'), findsOneWidget);
    expect(popped(), isFalse);
  });

  testWidgets('framework always keeps handling back so Android never exits on its own', (tester) async {
    final key = await pumpApp(tester);
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('terminal'))));
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();

    expect(handlesBackArgs(), isNotEmpty);
    expect(handlesBackArgs(), everyElement(isTrue));
  });

  testWidgets('handles-back is not sent while the app is detached', (tester) async {
    await pumpApp(tester);
    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);

    keepFrameworkHandlingBack(const NavigationNotification(canHandlePop: false));

    expect(handlesBackArgs(), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('non-Android platforms keep the default back behavior', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpApp(tester);

    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text('Close Deskconn?'), findsNothing);
    expect(popped(), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
