import 'package:shared_preferences/shared_preferences.dart';

class LastUsedRealmStore {
  static const _key = 'last_used_realm';

  static Future<void> set(String realm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, realm);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
