import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';
import 'shell_background_service.dart';
import 'toolbar.dart';

class ShellScreen extends StatefulWidget {
  final ShellLaunchConfig config;

  const ShellScreen({super.key, required this.config});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late final ShellBackgroundController _controller;
  double _fontSize = 14;
  double _fontSizeOnScaleStart = 14;
  bool _connecting = true;

  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;

  @override
  void initState() {
    super.initState();
    _controller = ShellBackgroundController(widget.config);
    _controller.onStarted = () {
      if (mounted) setState(() => _connecting = false);
    };
    _controller.onExit = () {
      if (mounted) Navigator.pop(context);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.start();
    });
  }

  @override
  void dispose() {
    stopShellBackgroundService(widget.config.sessionKey);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    onScaleStart: (_) => _fontSizeOnScaleStart = _fontSize,
                    onScaleUpdate: (details) {
                      if (details.pointerCount < 2) return;
                      final newSize = (_fontSizeOnScaleStart * details.scale).clamp(_minFontSize, _maxFontSize);
                      if ((newSize - _fontSize).abs() >= 0.5) {
                        setState(() => _fontSize = newSize);
                      }
                    },
                    child: TerminalView(
                      _controller.terminal,
                      autofocus: true,
                      textStyle: TerminalStyle(fontSize: _fontSize),
                    ),
                  ),
                  if (_connecting)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
            if (!_connecting)
              Toolbar(controller: _controller)
            else
              const SizedBox(
                height: 48,
                child: Center(
                  child: Text('Connecting shell...', style: TextStyle(color: Colors.white70)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
