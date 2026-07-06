import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

const _kAppNotificationChannel = 'deskconn/notification';
const _kNotifId = 1107;
const _kNotifChannelId = 'deskconn_session_v2';

class DesktopSessionLaunchConfig {
  final String sessionKey;
  final String desktopName;
  final String realm;
  final String authId;
  final String privateKey;
  final bool webRtcEnabled;
  final Map<String, dynamic>? turnCredentials;

  DesktopSessionLaunchConfig({
    required this.sessionKey,
    required this.desktopName,
    required this.realm,
    required this.authId,
    required this.privateKey,
    required this.webRtcEnabled,
    this.turnCredentials,
  });
}

Future<void> initializeDesktopSessionBackgroundService() async {
  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: false,
      notificationChannelId: _kNotifChannelId,
      initialNotificationTitle: 'Deskconn',
      initialNotificationContent: 'Deskconn is running',
      foregroundServiceNotificationId: _kNotifId,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

Future<void> showAppNotification() async {
  final service = FlutterBackgroundService();
  final promoted = service.on('promoted').first.timeout(const Duration(seconds: 3), onTimeout: () => {});
  service.invoke('promote');
  await promoted;

  try {
    await const MethodChannel(_kAppNotificationChannel).invokeMethod('show');
  } catch (_) {}
}

Future<void> hideAppNotification() async {
  FlutterBackgroundService().invoke('demote');
  try {
    await const MethodChannel(_kAppNotificationChannel).invokeMethod('hide');
  } catch (_) {}
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.on('promote').listen((_) async {
      await service.setAsForegroundService();
      service.invoke('promoted');
    });
    service.on('demote').listen((_) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((_) => service.stopSelf());
}
