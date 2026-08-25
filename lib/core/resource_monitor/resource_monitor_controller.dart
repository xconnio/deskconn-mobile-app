import 'dart:convert';
import 'dart:typed_data';

import 'package:xconn/xconn.dart';
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/resource_monitor/models.dart';

Uint8List _coerceBytes(dynamic raw) {
  if (raw is Uint8List) return raw;
  if (raw is List<int>) return Uint8List.fromList(raw);
  if (raw is List) return Uint8List.fromList(raw.map((v) => (v as num).toInt()).toList());
  if (raw is String) return Uint8List.fromList(base64.decode(raw));
  throw FormatException('Unsupported payload type: ${raw.runtimeType}');
}

class AppIcon {
  final String mime;
  final String data;

  const AppIcon({required this.mime, required this.data});

  String get dataUri => 'data:$mime;base64,$data';
}

class ResourceMonitorController {
  final Session session;

  ResourceMonitorController(this.session);

  Future<DeviceInfo> fetchInfo() async {
    final res = await session.call(DeskconnProcedures.deskconndDeviceInfo).timeout(DeskconnConfig.callTimeout);
    if (res.args.isEmpty) throw Exception('device.info failed: empty response');
    final decoded = jsonDecode(utf8.decode(_coerceBytes(res.args[0]))) as Map<String, dynamic>;
    return DeviceInfo.fromJson(decoded);
  }

  Future<List<ProcessInfo>> fetchProcesses() async {
    final res = await session.call(DeskconnProcedures.deskconndProcessList).timeout(DeskconnConfig.callTimeout);
    if (res.args.isEmpty) return const [];
    final decoded = jsonDecode(utf8.decode(_coerceBytes(res.args[0]))) as List;
    return decoded.map((e) => ProcessInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AppInfo>> fetchApps() async {
    final res = await session.call(DeskconnProcedures.deskconndAppList).timeout(DeskconnConfig.callTimeout);
    if (res.args.isEmpty) return const [];
    final decoded = jsonDecode(utf8.decode(_coerceBytes(res.args[0]))) as List;
    return decoded.map((e) => AppInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppIcon> fetchIcon(String iconName) async {
    final res = await session
        .call(DeskconnProcedures.deskconndAppIcon, args: [iconName])
        .timeout(DeskconnConfig.callTimeout);
    if (res.args.isEmpty) throw Exception('app.icon failed: empty response');
    final decoded = jsonDecode(utf8.decode(_coerceBytes(res.args[0]))) as Map<String, dynamic>;
    return AppIcon(mime: decoded['mime'] as String? ?? 'image/png', data: decoded['data'] as String? ?? '');
  }

  Future<void> signalPids(List<int> pids, String signal) async {
    if (pids.isEmpty) return;
    await session
        .call(DeskconnProcedures.deskconndProcessSignal, args: [pids, signal])
        .timeout(DeskconnConfig.callTimeout);
  }
}
