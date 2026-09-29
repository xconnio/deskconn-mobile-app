import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final serviceConfig = File('lib/core/terminal/terminal_background_service.dart').readAsStringSync();

  String serviceTag() {
    final match = RegExp(r'<service[^>]*BackgroundService[^>]*/>', dotAll: true).firstMatch(manifest);
    expect(match, isNotNull, reason: 'background service must be declared');
    return match!.group(0)!;
  }

  test('background service is declared as connectedDevice', () {
    expect(serviceTag(), contains('android:foregroundServiceType="connectedDevice"'));
  });

  test('time-limited dataSync type is not used anywhere', () {
    expect(manifest, isNot(contains('dataSync')));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(serviceConfig, isNot(contains('AndroidForegroundType.dataSync')));
  });

  test('connectedDevice permission and its network prerequisite are requested', () {
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'));
    expect(manifest, contains('android.permission.CHANGE_NETWORK_STATE'));
  });

  test('the Dart service configuration matches the manifest type', () {
    expect(serviceConfig, contains('AndroidForegroundType.connectedDevice'));
  });
}
