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
      // Use the same ID and channel as our custom notification so the plugin's
      // startForeground() and our nm.notify() both target the same slot → one notification.
      notificationChannelId: _kNotifChannelId,
      initialNotificationTitle: 'Deskconn',
      initialNotificationContent: 'Deskconn is running',
      foregroundServiceNotificationId: _kNotifId,
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

/// Show the persistent notification with Close button.
/// Promotes the service to foreground first so Android keeps the process alive,
/// then updates the notification slot with our custom content + Close button.
Future<void> showAppNotification() async {
  // 1. Promote service → plugin calls startForeground(1107, ...) on the same slot
  FlutterBackgroundService().invoke('promote');
  // 2. Wait for startForeground to complete before updating the notification
  await Future.delayed(const Duration(milliseconds: 300));
  // 3. Update slot 1107 to add the Close button
  try {
    await const MethodChannel(_kAppNotificationChannel).invokeMethod('show');
  } catch (_) {}
}

/// Remove the notification and demote the service. Call on logout.
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
