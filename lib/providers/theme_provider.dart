import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  bool _initialized = false;

  ThemeMode get mode => _mode;
  bool get initialized => _initialized;

  ThemeProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);

    if (saved == null) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

      _mode = brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;

      await prefs.setString(_key, _mode.name);
    } else {
      _mode = ThemeMode.values.firstWhere((e) => e.name == saved, orElse: () => ThemeMode.light);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> toggleTheme() async {
    final newMode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(newMode);
  }
}
