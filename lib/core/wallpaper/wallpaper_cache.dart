import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WallpaperCache {
  static Future<Uint8List?> load(String realm) async {
    final file = await _file(realm);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<String?> cachedChecksum(String realm) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_checksumKey(realm));
  }

  static Future<void> store(String realm, Uint8List bytes, String checksum) async {
    final file = await _file(realm);
    await file.writeAsBytes(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checksumKey(realm), checksum);
  }

  static String _checksumKey(String realm) => 'wallpaper_checksum_$realm';

  static Future<File> _file(String realm) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeName = realm.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return File('${dir.path}/wallpaper_$safeName.img');
  }
}
