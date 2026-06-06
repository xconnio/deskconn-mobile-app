import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

const _kAppNotificationChannel = 'deskconn/notification';
const _kNotifId = 1107;
const _kNotifChannelId = 'deskconn_session';

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
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

Future<void> showAppNotification() async {
  try {
    await const MethodChannel(_kAppNotificationChannel).invokeMethod('show');
  } catch (_) {}
  FlutterBackgroundService().invoke('promote');
}

Future<void> hideAppNotification() async {
  try {
    await const MethodChannel(_kAppNotificationChannel).invokeMethod('hide');
  } catch (_) {}
  FlutterBackgroundService().invoke('demote');
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.on('promote').listen((_) => service.setAsForegroundService());
    service.on('demote').listen((_) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((_) => service.stopSelf());
}
