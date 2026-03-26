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

  @override
  void initState() {
    super.initState();
    _controller = ShellController(widget.session);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.session.close().catchError((e) {});
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
              child: TerminalView(_controller.terminal, autofocus: true, textStyle: const TerminalStyle(fontSize: 14)),
            ),
            Toolbar(controller: _controller),
          ],
        ),
      ),
    );
  }
}
