import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';
import 'shell_background_service.dart';
import 'shell_controller.dart';
import 'toolbar.dart';

void _log(String msg) => debugPrint('[ShellScreen ${DateTime.now().millisecondsSinceEpoch}] $msg');

class ShellScreen extends StatefulWidget {
  final ShellController controller;

  const ShellScreen({super.key, required this.controller});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  double _fontSize = 14;
  double _fontSizeOnScaleStart = 14;
  bool _isLoading = false;

  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _isLoading = !widget.controller.isReady;
    widget.controller.onStarted = () {
      if (mounted) setState(() => _isLoading = false);
    };
    widget.controller.onExit = () {
      if (mounted) Navigator.pop(context);
    };

    _log('attached realm=${widget.controller.config.realm} isReady=${widget.controller.isReady}');
  }

  @override
  void dispose() {
    _log('dispose — detaching callbacks');
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.onStarted = null;
    widget.controller.onExit = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      setShellAppStatus(true);
    } else if (state == AppLifecycleState.resumed) {
      setShellAppStatus(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
