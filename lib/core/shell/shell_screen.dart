import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';
import 'package:xterm/ui.dart';
import 'shell_controller.dart';
import 'toolbar.dart';

class ShellScreen extends StatefulWidget {
  final Session session;

  const ShellScreen({super.key, required this.session});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late final ShellController _controller;
  double _fontSize = 14;
  double _fontSizeOnScaleStart = 14;

  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;

  @override
  void initState() {
    super.initState();
    _controller = ShellController(widget.session);
    _controller.onExit = () {
      if (mounted) Navigator.pop(context);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.session.close().catchError((_) {});
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
                  _controller.terminal,
                  autofocus: true,
                  textStyle: TerminalStyle(fontSize: _fontSize),
                ),
              ),
            ),
            Toolbar(controller: _controller),
          ],
        ),
      ),
    );
  }
}
