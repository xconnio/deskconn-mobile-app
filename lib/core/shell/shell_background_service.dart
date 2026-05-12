import 'package:flutter_background_service/flutter_background_service.dart';

class ShellLaunchConfig {
  final String sessionKey;
  final String desktopName;
  final String realm;
  final String authId;
  final String privateKey;
  final bool webRtcEnabled;
  final Map<String, dynamic>? turnCredentials;

  ShellLaunchConfig({
    required this.sessionKey,
    required this.desktopName,
    required this.realm,
    required this.authId,
    required this.privateKey,
    required this.webRtcEnabled,
    this.turnCredentials,
  });
}

Future<void> initializeShellBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      initialNotificationTitle: 'Deskconn Shell',
      initialNotificationContent: 'Shell service is idle',
      foregroundServiceNotificationId: 1107,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

Future<void> startShellBackgroundService(ShellLaunchConfig config, {bool wait = false}) async {
  final service = FlutterBackgroundService();
  if (!(await service.isRunning())) {
    await service.startService();
    if (wait) await Future.delayed(const Duration(milliseconds: 500));
  }
  service.invoke('updateNotification', {
    'title': 'Deskconn Shell',
    'content': 'Connecting to ${config.desktopName}...',
  });
}

void setShellAppStatus(bool isBackground) {
  FlutterBackgroundService().invoke(isBackground ? 'setAsForeground' : 'setAsBackground');
}

Future<void> showShellNotification(String desktopName, String realm) async {
  FlutterBackgroundService().invoke('updateNotification', {
    'title': 'Deskconn Shell',
    'content': 'Terminal is running on $desktopName',
  });
}

Future<void> dismissShellNotification() async {
  FlutterBackgroundService().invoke('updateNotification', {
    'title': 'Deskconn Shell',
    'content': 'Shell service is idle',
  });
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
    service.on('updateNotification').listen((event) {
      if (event == null) return;
      (service).setForegroundNotificationInfo(
        title: event['title'] as String? ?? 'Deskconn Shell',
        content: event['content'] as String? ?? '',
      );
    });
  }
  service.on('stopService').listen((_) => service.stopSelf());
}
