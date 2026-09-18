import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/ui.dart' hide TerminalController;
import 'terminal_controller.dart';
import 'terminal_launcher.dart';
import 'terminal_registry.dart';
import 'toolbar.dart';

void _log(String msg) => debugPrint('[TerminalScreen ${DateTime.now().millisecondsSinceEpoch}] $msg');

class TerminalScreen extends StatelessWidget {
  final String realm;
  final String desktopName;
  final bool webRtcEnabled;

  const TerminalScreen({super.key, required this.realm, required this.desktopName, required this.webRtcEnabled});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: TerminalTabsView(realm: realm, desktopName: desktopName, webRtcEnabled: webRtcEnabled),
    );
  }
}

class TerminalTabsView extends StatefulWidget {
  final String realm;
  final String desktopName;
  final bool webRtcEnabled;
  final bool embedded;
  final VoidCallback? onRequestClose;

  const TerminalTabsView({
    super.key,
    required this.realm,
    required this.desktopName,
    required this.webRtcEnabled,
    this.embedded = false,
    this.onRequestClose,
  });

  @override
  State<TerminalTabsView> createState() => _TerminalTabsViewState();
}

class _TerminalTabsViewState extends State<TerminalTabsView> {
  late final TerminalGroup _group;
  bool _addingTab = false;

  @override
  void initState() {
    super.initState();
    _group = TerminalRegistry().groupFor(widget.realm);
    _group.pruneInactive();
    _group.addListener(_onGroupChanged);
    if (_group.isEmpty) unawaited(_addTab());
  }

  @override
  void dispose() {
    _group.removeListener(_onGroupChanged);
    super.dispose();
  }

  void _onGroupChanged() {
    if (!mounted) return;
    if (_group.isEmpty) {
      _close();
      return;
    }
    setState(() {});
  }

  void _close() {
    if (widget.embedded) {
      widget.onRequestClose?.call();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _addTab() async {
    if (_addingTab) return;
    setState(() => _addingTab = true);
    try {
      final controller = await startNewTerminalTab(
        realm: widget.realm,
        desktopName: widget.desktopName,
        webRtcEnabled: widget.webRtcEnabled,
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      _group.addTab(controller);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Could not open a new tab: $e')));
      }
    } finally {
      if (mounted) setState(() => _addingTab = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _group.tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();

    final activeIndex = tabs.indexWhere((t) => t.id == _group.activeId).clamp(0, tabs.length - 1);

    return SafeArea(
      top: !widget.embedded,
      bottom: false,
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            _TerminalTabBar(
              tabs: tabs,
              activeId: _group.activeId,
              addingTab: _addingTab,
              onSelect: _group.selectTab,
              onClose: _group.closeTab,
              onAdd: _addTab,
            ),
            Expanded(
              child: IndexedStack(
                index: activeIndex,
                children: [
                  for (final tab in tabs)
                    TerminalPane(
                      key: ValueKey(tab.id),
                      controller: tab.controller,
                      embedded: true,
                      onRequestClose: () => _group.closeTab(tab.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalTabBar extends StatelessWidget {
  final List<TerminalTab> tabs;
  final String? activeId;
  final bool addingTab;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;
  final VoidCallback onAdd;

  const _TerminalTabBar({
    required this.tabs,
    required this.activeId,
    required this.addingTab,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final tab in tabs)
                  _TabChip(
                    key: ValueKey(tab.id),
                    title: tab.title,
                    active: tab.id == activeId,
                    onTap: () => onSelect(tab.id),
                    onClose: () => onClose(tab.id),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: addingTab
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  )
                : IconButton(
                    icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                    tooltip: 'New tab',
                    onPressed: onAdd,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({super.key, required this.title, required this.active, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal, size: 14, color: active ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 13, color: active ? Colors.white70 : Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TerminalPane extends StatefulWidget {
  final TerminalController controller;
  final bool embedded;
  final VoidCallback? onRequestClose;

  const TerminalPane({super.key, required this.controller, this.embedded = false, this.onRequestClose});

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> with WidgetsBindingObserver {
  double _fontSize = 14;
  double _fontSizeOnScaleStart = 14;
  bool _isLoading = false;
  Object? _startError;

  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _isLoading = !widget.controller.isReady;
    if (widget.controller.isReady) {
      widget.controller.clearScreen();
      // Post-frame: send a resize signal so the server-side shell redraws its
      // prompt after we wiped the xterm buffer. Without this the cursor sits
      // idle because the shell has no reason to repaint.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.requestRedraw();
      });
    }
    widget.controller.onStarted = () {
      if (mounted) setState(() => _isLoading = false);
    };
    widget.controller.onExit = _close;
    widget.controller.onError = (e) {
      if (mounted) setState(() => _startError = e);
    };

    _log('attached realm=${widget.controller.config.realm} isReady=${widget.controller.isReady}');
  }

  @override
  void dispose() {
    _log('dispose — detaching callbacks');
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.onStarted = null;
    widget.controller.onExit = null;
    widget.controller.onError = null;
    widget.controller.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    if (widget.embedded) {
      widget.onRequestClose?.call();
    } else {
      Navigator.pop(context);
    }
  }

  AppBar _launchAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(widget.controller.config.desktopName, style: const TextStyle(fontSize: 15)),
    );
  }

  Widget _chrome({PreferredSizeWidget? appBar, required Widget body}) {
    if (widget.embedded) return Container(color: Colors.black, child: body);
    return Scaffold(backgroundColor: Colors.black, appBar: appBar, body: body);
  }

  @override
  Widget build(BuildContext context) {
    if (_startError != null) {
      return _chrome(
        appBar: _launchAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                const Text('Could not open terminal', style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  _startError.toString(),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _close,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return _chrome(
        appBar: _launchAppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal, color: Colors.white24, size: 48),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.white70),
              const SizedBox(height: 20),
              Text(
                'Connecting to ${widget.controller.config.desktopName}…',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return _chrome(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onScaleStart: (_) => _fontSizeOnScaleStart = _fontSize,
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2) return;
                  final newSize = (_fontSizeOnScaleStart * details.scale).clamp(_minFontSize, _maxFontSize);
                  if ((newSize - _fontSize).abs() >= 0.5) {
                    setState(() => _fontSize = newSize);
                  }
                },
                child: TerminalView(
                  widget.controller.terminal,
                  autofocus: true,
                  textStyle: TerminalStyle(fontSize: _fontSize),
                ),
              ),
            ),
            Toolbar(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}
