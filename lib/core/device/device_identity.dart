import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deskconn_mobile_app/core/device/cryptosign_keys.dart';

class DeviceIdentity {
  static const _deviceIdKey = 'device_id';
  static const _privateKey = 'private_key';
  static const _publicKey = 'public_key';
  static const _lastEmail = 'last_email';
  static const _deviceNameKey = 'device_name';
  static const _deviceModelKey = 'device_model';

  static final _secure = const FlutterSecureStorage();

  static Future<void> save({
    required String deviceId,
    required String privateKey,
    required String publicKey,
    String? email,
    String? deviceName,
    String? deviceModel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
    await prefs.setString(_publicKey, publicKey);

    if (email != null) await prefs.setString(_lastEmail, email);
    if (deviceName != null) await prefs.setString(_deviceNameKey, deviceName);
    if (deviceModel != null) await prefs.setString(_deviceModelKey, deviceModel);

    await _secure.write(key: _privateKey, value: privateKey);
  }

  static Future<String?> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  static Future<String?> lastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastEmail);
  }

  static Future<String?> privateKey() async {
    return await _secure.read(key: _privateKey);
  }

  static Future<String?> publicKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_publicKey);
  }

  static Future<bool> hasKeyPair() async {
    final privateKey = await DeviceIdentity.privateKey();
    final publicKey = await DeviceIdentity.publicKey();
    return privateKey != null && publicKey != null;
  }

  static Future<Map<String, String>> ensureKeyPair() async {
    final privateKey = await DeviceIdentity.privateKey();
    final publicKey = await DeviceIdentity.publicKey();

    if (privateKey != null && publicKey != null) {
      return {'privateKey': privateKey, 'publicKey': publicKey};
    }

    final privateKeyHex = await CryptoSignKeys.generatePrivateKey();
    final publicKeyHex = await CryptoSignKeys.derivePublicKey(privateKeyHex);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_publicKey, publicKeyHex);
    await _secure.write(key: _privateKey, value: privateKeyHex);

    return {'privateKey': privateKeyHex, 'publicKey': publicKeyHex};
  }

  static Future<String?> deviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceNameKey);
  }

  static Future<String?> deviceModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceModelKey);
  }

  static Future<Map<String, String?>> getAllDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'deviceId': prefs.getString(_deviceIdKey),
      'email': prefs.getString(_lastEmail),
      'deviceName': prefs.getString(_deviceNameKey),
      'deviceModel': prefs.getString(_deviceModelKey),
      'publicKey': prefs.getString(_publicKey),
    };
  }

  static Future<bool> exists() async {
    final deviceId = await DeviceIdentity.deviceId();
    final privateKey = await DeviceIdentity.privateKey();
    return deviceId != null && privateKey != null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_publicKey);
    await prefs.remove(_lastEmail);
    await prefs.remove(_deviceNameKey);
    await prefs.remove(_deviceModelKey);
    await _secure.delete(key: _privateKey);
  }
}
