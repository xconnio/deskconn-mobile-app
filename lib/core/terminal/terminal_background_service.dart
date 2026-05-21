import 'package:flutter_background_service/flutter_background_service.dart';

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
      isForegroundMode: true,
      initialNotificationTitle: 'Deskconn',
      initialNotificationContent: 'Desktop session service is idle',
      foregroundServiceNotificationId: 1107,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

Future<void> startDesktopSessionBackgroundService(DesktopSessionLaunchConfig config) async {
  await syncDesktopSessionService(activeConnections: 1, appInBackground: true);
}

void setDesktopSessionAppStatus(bool isBackground) {
  FlutterBackgroundService().invoke(isBackground ? 'setAsForeground' : 'setAsBackground');
}

Future<void> dismissDesktopSessionNotification() async {
  await syncDesktopSessionService(activeConnections: 0, appInBackground: false);
}

Future<void> syncDesktopSessionService({required int activeConnections, required bool appInBackground}) async {
  final service = FlutterBackgroundService();

  if (activeConnections <= 0) {
    service.invoke('stopService');
    return;
  }

  if (!(await service.isRunning())) {
    await service.startService();
    await Future.delayed(const Duration(milliseconds: 500));
  }

  final label = activeConnections == 1 ? '1 desktop session ready' : '$activeConnections desktop sessions ready';

  service.invoke('updateNotification', {'title': 'Deskconn', 'content': label});
  service.invoke(appInBackground ? 'setAsForeground' : 'setAsBackground');
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
    service.on('updateNotification').listen((event) {
      if (event == null) return;
      service.setForegroundNotificationInfo(
        title: event['title'] as String? ?? 'Deskconn',
        content: event['content'] as String? ?? '',
      );
    });
  }
  service.on('stopService').listen((_) => service.stopSelf());
}
