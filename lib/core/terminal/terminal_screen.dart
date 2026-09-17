import 'package:flutter/material.dart';
import 'package:xterm/ui.dart' hide TerminalController;
import 'terminal_controller.dart';
import 'toolbar.dart';

void _log(String msg) => debugPrint('[TerminalScreen ${DateTime.now().millisecondsSinceEpoch}] $msg');

class TerminalScreen extends StatelessWidget {
  final TerminalController controller;

  const TerminalScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: TerminalPane(controller: controller),
    );
  }
}

/// Embeddable content for a live terminal session. Used standalone inside
/// [TerminalScreen] (mobile full-screen push) and directly as
/// [DesktopWindowEntry.content] inside a [FloatingWindow] on desktop, where
/// [onRequestClose] closes the window instead of popping the (unrelated)
/// enclosing route.
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
