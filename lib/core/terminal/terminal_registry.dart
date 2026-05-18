import 'dart:async';

import '../wamp/desktop_connection_manager.dart';
import 'terminal_controller.dart';

class TerminalRegistry {
  static final _instance = TerminalRegistry._();
  factory TerminalRegistry() => _instance;
  TerminalRegistry._();

  final Map<String, TerminalController> _controllers = {};

  TerminalController? getActive(String realm) {
    final c = _controllers[realm];
    if (c == null) return null;
    if (!c.isActive) {
      _controllers.remove(realm);
      return null;
    }
    return c;
  }

  void register(String realm, TerminalController controller) {
    final existing = _controllers[realm];
    if (existing != null && existing != controller) {
      existing.dispose();
    }
    _controllers[realm] = controller;
  }

  void remove(String realm) {
    if (_controllers.remove(realm) != null) {}
  }

  void closeTerminal(String realm) {
    _controllers.remove(realm)?.dispose();
    unawaited(DesktopConnectionManager().release(realm));
  }
}
