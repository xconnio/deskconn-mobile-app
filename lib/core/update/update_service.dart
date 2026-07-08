import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

const bool kUpdateCheckEnabled = false;

class UpdateService {
  static const String repoUrl = 'https://api.github.com/repos/xconnio/deskconn-mobile-app/releases/latest';

  Future<Map<String, dynamic>?> checkForUpdate() async {
    if (!kUpdateCheckEnabled) return null;
    try {
      final response = await http.get(Uri.parse(repoUrl));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final latestTagName = data['tag_name'] as String;
      final latestBuild = int.tryParse(latestTagName.replaceAll(RegExp(r'^v'), ''));
      if (latestBuild == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (latestBuild > currentBuild) {
        return {'version': latestTagName, 'notes': data['body'] ?? '', 'apkUrl': _getApkUrl(data)};
      }
    } catch (_) {}
    return null;
  }

  String? _getApkUrl(Map<String, dynamic> releaseData) {
    final List assets = releaseData['assets'] ?? [];
    final apkAsset = assets.firstWhere((asset) => (asset['name'] as String).endsWith('.apk'), orElse: () => null);
    return apkAsset?['browser_download_url'];
  }

  Future<void> downloadAndInstall(String url, Function(double) onProgress) async {
    final dir = (await getExternalStorageDirectory()) ?? await getTemporaryDirectory();
    final filePath = '${dir.path}/update.apk';
    final file = File(filePath);

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);
    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    final sink = file.openWrite();
    await response.stream.listen((chunk) {
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress(receivedBytes / totalBytes);
      }
      sink.add(chunk);
    }).asFuture();
    await sink.close();
    client.close();

    // Launch Android Package Installer
    await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
  }
}
