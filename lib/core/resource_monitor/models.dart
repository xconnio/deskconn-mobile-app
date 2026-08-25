double _numToDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _numToInt(dynamic v) => (v as num?)?.toInt() ?? 0;

class NetworkInterface {
  final String name;
  final double bytesSentPs;
  final double bytesRecvPs;

  const NetworkInterface({required this.name, required this.bytesSentPs, required this.bytesRecvPs});

  factory NetworkInterface.fromJson(Map<String, dynamic> json) => NetworkInterface(
    name: json['name'] as String? ?? '',
    bytesSentPs: _numToDouble(json['bytes_sent_ps']),
    bytesRecvPs: _numToDouble(json['bytes_recv_ps']),
  );
}

class DeviceInfo {
  final String cpuModel;
  final int cpuPhysical;
  final int cpuLogical;
  final List<double> cpuUsages;
  final double ramTotal;
  final double ramFree;
  final double ramUsed;
  final double ramBuffCache;
  final double ramAvailable;
  final double swapTotal;
  final double swapFree;
  final double swapUsed;
  final double diskUsed;
  final double diskFree;
  final double diskTotal;
  final List<NetworkInterface> networkInterfaces;

  const DeviceInfo({
    required this.cpuModel,
    required this.cpuPhysical,
    required this.cpuLogical,
    required this.cpuUsages,
    required this.ramTotal,
    required this.ramFree,
    required this.ramUsed,
    required this.ramBuffCache,
    required this.ramAvailable,
    required this.swapTotal,
    required this.swapFree,
    required this.swapUsed,
    required this.diskUsed,
    required this.diskFree,
    required this.diskTotal,
    required this.networkInterfaces,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    cpuModel: json['cpu_model'] as String? ?? '',
    cpuPhysical: _numToInt(json['cpu_physical']),
    cpuLogical: _numToInt(json['cpu_logical']),
    cpuUsages: ((json['cpu_usages'] as List?) ?? const []).map(_numToDouble).toList(),
    ramTotal: _numToDouble(json['ram_total']),
    ramFree: _numToDouble(json['ram_free']),
    ramUsed: _numToDouble(json['ram_used']),
    ramBuffCache: _numToDouble(json['ram_buff_cache']),
    ramAvailable: _numToDouble(json['ram_available']),
    swapTotal: _numToDouble(json['swap_total']),
    swapFree: _numToDouble(json['swap_free']),
    swapUsed: _numToDouble(json['swap_used']),
    diskUsed: _numToDouble(json['disk_used']),
    diskFree: _numToDouble(json['disk_free']),
    diskTotal: _numToDouble(json['disk_total']),
    networkInterfaces: ((json['network_interfaces'] as List?) ?? const [])
        .map((e) => NetworkInterface.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  double get cpuOverall {
    if (cpuUsages.isEmpty) return 0;
    return cpuUsages.reduce((a, b) => a + b) / cpuUsages.length;
  }

  double get ramUsedPercent => ramTotal <= 0 ? 0 : ((ramTotal - ramAvailable) / ramTotal) * 100;

  double get swapUsedPercent => swapTotal <= 0 ? 0 : (swapUsed / swapTotal) * 100;

  double get diskUsedPercent => diskTotal <= 0 ? 0 : (diskUsed / diskTotal) * 100;

  double get networkTotalBps =>
      networkInterfaces.fold(0.0, (sum, iface) => sum + iface.bytesSentPs + iface.bytesRecvPs);
}

class ProcessInfo {
  final int pid;
  final String name;
  final String user;
  final double cpuPercent;
  final double memRss;
  final double memPercent;

  const ProcessInfo({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpuPercent,
    required this.memRss,
    required this.memPercent,
  });

  factory ProcessInfo.fromJson(Map<String, dynamic> json) => ProcessInfo(
    pid: _numToInt(json['pid']),
    name: json['name'] as String? ?? '',
    user: json['user'] as String? ?? '',
    cpuPercent: _numToDouble(json['cpu_percent']),
    memRss: _numToDouble(json['mem_rss']),
    memPercent: _numToDouble(json['mem_percent']),
  );
}

class AppInfo {
  final String id;
  final String name;
  final String iconName;
  final List<int> pids;
  final double cpuPercent;
  final double memRss;

  const AppInfo({
    required this.id,
    required this.name,
    required this.iconName,
    required this.pids,
    required this.cpuPercent,
    required this.memRss,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    iconName: json['icon_name'] as String? ?? '',
    pids: ((json['pids'] as List?) ?? const []).map(_numToInt).toList(),
    cpuPercent: _numToDouble(json['cpu_percent']),
    memRss: _numToDouble(json['mem_rss']),
  );
}
