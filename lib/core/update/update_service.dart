import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class UpdateService {
  static const String repoUrl = 'https://api.github.com/repos/xconnio/deskconn-mobile-app/releases/latest';

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await http.get(Uri.parse(repoUrl));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final latestTagName = data['tag_name'] as String;
      // Extract version digits (e.g. "v25" -> "25", "1.2.0" -> "1.2.0")
      final latestVersion = latestTagName.replaceAll(RegExp(r'^v'), '');
      
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isNewerVersion(currentVersion, latestVersion)) {
        return {
          'version': latestTagName,
          'notes': data['body'] ?? '',
          'apkUrl': _getApkUrl(data),
        };
      }
    } catch (e) {
      // Avoid printing in production or log gracefully
      print("Check update failed: $e");
    }
    return null;
  }

  bool _isNewerVersion(String current, String latest) {
    // Standardize: remove non-numeric parts at the start if any
    final cleanCurrent = current.replaceAll(RegExp(r'^v'), '');
    final cleanLatest = latest.replaceAll(RegExp(r'^v'), '');

    // Try parsing as simple integers (e.g., build numbers/version tags like "25" vs "24")
    final currInt = int.tryParse(cleanCurrent);
    final lateInt = int.tryParse(cleanLatest);

    if (currInt != null && lateInt != null) {
      return lateInt > currInt;
    }

    // Fall back to semantic version splitting (e.g. "1.2.0" vs "1.3.0")
    try {
      List<int> currParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> lateParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      int maxLength = currParts.length > lateParts.length ? currParts.length : lateParts.length;
      for (int i = 0; i < maxLength; i++) {
        int currPart = i < currParts.length ? currParts[i] : 0;
        int latePart = i < lateParts.length ? lateParts[i] : 0;

        if (latePart > currPart) return true;
        if (currPart > latePart) return false;
      }
    } catch (_) {
      // If parsing fails, do a simple string comparison
      return cleanLatest != cleanCurrent;
    }
    return false;
  }

  String? _getApkUrl(Map<String, dynamic> releaseData) {
    final List assets = releaseData['assets'] ?? [];
    final apkAsset = assets.firstWhere(
      (asset) => (asset['name'] as String).endsWith('.apk'),
      orElse: () => null,
    );
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
