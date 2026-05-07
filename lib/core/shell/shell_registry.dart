import 'dart:async';

import '../wamp/desktop_connection_manager.dart';
import 'shell_controller.dart';

class ShellRegistry {
  static final _instance = ShellRegistry._();
  factory ShellRegistry() => _instance;
  ShellRegistry._();

  final Map<String, ShellController> _controllers = {};

  ShellController? getActive(String realm) {
    final c = _controllers[realm];
    if (c == null) return null;
    if (!c.isActive) {
      _controllers.remove(realm);
      return null;
    }
    return c;
  }

  void register(String realm, ShellController controller) {
    final existing = _controllers[realm];
    if (existing != null && existing != controller) {
      existing.dispose();
    }
    _controllers[realm] = controller;
  }

  void remove(String realm) {
    if (_controllers.remove(realm) != null) {}
  }

  void closeShell(String realm) {
    _controllers.remove(realm)?.dispose();
    unawaited(DesktopConnectionManager().release(realm));
  }
}
