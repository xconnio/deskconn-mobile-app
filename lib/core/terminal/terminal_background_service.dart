import 'package:flutter_background_service/flutter_background_service.dart';

class TerminalLaunchConfig {
  final String sessionKey;
  final String desktopName;
  final String realm;
  final String authId;
  final String privateKey;
  final bool webRtcEnabled;
  final Map<String, dynamic>? turnCredentials;

  TerminalLaunchConfig({
    required this.sessionKey,
    required this.desktopName,
    required this.realm,
    required this.authId,
    required this.privateKey,
    required this.webRtcEnabled,
    this.turnCredentials,
  });
}

Future<void> initializeTerminalBackgroundService() async {
  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      initialNotificationTitle: 'Deskconn Terminal',
      initialNotificationContent: 'Terminal service is idle',
      foregroundServiceNotificationId: 1107,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: _onStart, onBackground: (instance) => true),
  );
}

Future<void> startTerminalBackgroundService(TerminalLaunchConfig config) async {
  final service = FlutterBackgroundService();
  if (!(await service.isRunning())) {
    await service.startService();
    await Future.delayed(const Duration(milliseconds: 500));
  }
  service.invoke('updateNotification', {
    'title': 'Deskconn Terminal',
    'content': 'connected to ${config.desktopName}...',
  });
  service.invoke('setAsBackground');
}

void setTerminalAppStatus(bool isBackground) {
  FlutterBackgroundService().invoke(isBackground ? 'setAsForeground' : 'setAsBackground');
}

Future<void> dismissTerminalNotification() async {
  FlutterBackgroundService().invoke('stopService');
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
    service.on('updateNotification').listen((event) {
      if (event == null) return;
      service.setForegroundNotificationInfo(
        title: event['title'] as String? ?? 'Deskconn Terminal',
        content: event['content'] as String? ?? '',
      );
    });
  }
  service.on('stopService').listen((_) => service.stopSelf());
}
