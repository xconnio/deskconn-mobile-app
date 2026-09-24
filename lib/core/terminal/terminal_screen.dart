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

  static const int _maxLiveTabs = 2;

  Future<void> _addTab() async {
    if (_addingTab) return;
    if (_group.tabs.length >= _maxLiveTabs) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Only $_maxLiveTabs terminal tabs per desktop are supported right now.')),
      );
      return;
    }
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

  Future<void> _showSwitcher(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => _TabSwitcherSheet(
        tabs: tabs,
        activeId: activeId,
        onSelect: (id) {
          Navigator.of(sheetContext).pop();
          onSelect(id);
        },
        onClose: (id) {
          Navigator.of(sheetContext).pop();
          onClose(id);
        },
        onAdd: () {
          Navigator.of(sheetContext).pop();
          onAdd();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return _TabChip(
                  title: tab.title,
                  active: tab.id == activeId,
                  onSelect: () => onSelect(tab.id),
                  onClose: () => onClose(tab.id),
                );
              },
            ),
          ),
          SizedBox(
            width: 34,
            height: 34,
            child: addingTab
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                    tooltip: 'New tab',
                    onPressed: onAdd,
                  ),
          ),
          GestureDetector(
            onTap: () => _showSwitcher(context),
            child: Container(
              width: 40,
              height: 34,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grid_view_rounded, color: Colors.white70, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '${tabs.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
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
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _TabChip({required this.title, required this.active, required this.onSelect, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.only(left: 12, right: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: active ? Colors.white24 : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 13, color: active ? Colors.white : Colors.white38),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 13, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSwitcherSheet extends StatelessWidget {
  final List<TerminalTab> tabs;
  final String? activeId;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;
  final VoidCallback onAdd;

  const _TabSwitcherSheet({
    required this.tabs,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  static const _previewLines = 6;

  String _previewOf(TerminalTab tab) {
    final lines = tab.controller.preview.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.length <= _previewLines) return lines.join('\n');
    return lines.sublist(lines.length - _previewLines).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Tabs',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text('${tabs.length}', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                  label: const Text('New tab', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [for (final tab in tabs) _card(tab)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(TerminalTab tab) {
    final active = tab.id == activeId;
    return GestureDetector(
      onTap: () => onSelect(tab.id),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0B0B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.white54 : Colors.white12, width: active ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _previewOf(tab),
                  maxLines: _previewLines,
                  style: const TextStyle(color: Colors.white54, fontSize: 8, fontFamily: 'monospace', height: 1.35),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 12, color: Colors.white54),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: () => onClose(tab.id),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, size: 13, color: Colors.white38),
                    ),
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
      if (!mounted) return;
      setState(() => _isLoading = false);
      // The PTY is created with the client's size at that moment and only
      // corrected once the view has laid out, so its first output is drawn at
      // the wrong width. Wipe that and ask the shell to repaint instead of
      // leaving wrapped/overlapping lines behind.
      widget.controller.clearScreen();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.requestRedraw();
      });
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
