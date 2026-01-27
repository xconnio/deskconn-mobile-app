import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const _deviceIdKey = 'device_id';
  static const _privateKeyKey = 'cryptosign_private_key';

  static final _secure = const FlutterSecureStorage();

  static Future<void> save({required String deviceId, required String privateKey}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
    await _secure.write(key: _privateKeyKey, value: privateKey);
  }

  static Future<String?> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  static Future<String?> privateKey() async {
    return _secure.read(key: _privateKeyKey);
  }

  static Future<bool> exists() async {
    return (await deviceId()) != null && (await privateKey()) != null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await _secure.delete(key: _privateKeyKey);
  }
}
