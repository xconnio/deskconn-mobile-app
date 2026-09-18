import 'dart:async';

import 'package:flutter/foundation.dart';

import '../wamp/desktop_connection_manager.dart';
import 'terminal_controller.dart';

class TerminalTab {
  final String id;
  final TerminalController controller;
  final String title;

  TerminalTab({required this.id, required this.controller, required this.title});
}

class TerminalGroup extends ChangeNotifier {
  final String realm;

  TerminalGroup(this.realm);

  final List<TerminalTab> _tabs = [];
  String? _activeId;
  int _nextId = 0;
  int _nextTabNumber = 1;

  List<TerminalTab> get tabs => List.unmodifiable(_tabs);
  String? get activeId => _activeId;
  bool get isEmpty => _tabs.isEmpty;

  TerminalTab addTab(TerminalController controller) {
    final tab = TerminalTab(id: 't${_nextId++}', controller: controller, title: 'Terminal ${_nextTabNumber++}');
    _tabs.add(tab);
    _activeId = tab.id;
    notifyListeners();
    return tab;
  }

  void selectTab(String id) {
    if (_activeId == id || !_tabs.any((t) => t.id == id)) return;
    _activeId = id;
    notifyListeners();
  }

  void closeTab(String id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _tabs.removeAt(index);
    if (_activeId == id) {
      _activeId = _tabs.isEmpty ? null : _tabs[index.clamp(0, _tabs.length - 1)].id;
    }
    notifyListeners();
  }

  void pruneInactive() {
    final before = _tabs.length;
    _tabs.removeWhere((t) => !t.controller.isActive);
    if (_tabs.length == before) return;
    if (_activeId != null && !_tabs.any((t) => t.id == _activeId)) {
      _activeId = _tabs.isEmpty ? null : _tabs.first.id;
    }
    notifyListeners();
  }

  void closeAll() {
    for (final tab in _tabs) {
      tab.controller.dispose();
    }
    _tabs.clear();
    _activeId = null;
    notifyListeners();
  }
}

class TerminalRegistry {
  static final _instance = TerminalRegistry._();
  factory TerminalRegistry() => _instance;
  TerminalRegistry._();

  final Map<String, TerminalGroup> _groups = {};

  TerminalGroup groupFor(String realm) => _groups.putIfAbsent(realm, () => TerminalGroup(realm));

  TerminalGroup? getActive(String realm) {
    final group = _groups[realm];
    if (group == null) return null;
    group.pruneInactive();
    if (group.isEmpty) {
      _groups.remove(realm);
      return null;
    }
    return group;
  }

  void closeTerminal(String realm) {
    final group = _groups.remove(realm);
    group?.closeAll();
    unawaited(DesktopConnectionManager().release(realm));
  }
}
