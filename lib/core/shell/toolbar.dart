import 'package:flutter/material.dart';
import 'shell_controller.dart';

class Toolbar extends StatefulWidget {
  final ShellController controller;

  const Toolbar({super.key, required this.controller});

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  bool ctrl = false;
  bool alt = false;

  void send(String key) {
    String output = key;

    if (ctrl) {
      output = _applyCtrl(key);
      ctrl = false;
    }

    if (alt) {
      output = "\x1b$output";
      alt = false;
    }

    widget.controller.sendSpecialKey(output);
    setState(() {});
  }

  String _applyCtrl(String key) {
    if (key.isEmpty) return key;

    final code = key.codeUnitAt(0);

    if (code >= 97 && code <= 122) {
      return String.fromCharCode(code - 96);
    }

    return key;
  }

  Widget key(String label, VoidCallback onTap, {Color? color, bool active = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.green : (color ?? Colors.black87),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              key("ESC", () => send("\x1b")),
              key("/", () => send("/")),
              key("-", () => send("-")),
              key("HOME", () => widget.controller.sendHome()),
              key("↑", () => widget.controller.sendArrowUp()),
              key("END", () => widget.controller.sendEnd()),
              key("PGUP", () => send("\x1b[5~")),
            ],
          ),
          Row(
            children: [
              key("TAB", () => widget.controller.sendTab()),
              key("CTRL", () => setState(() => ctrl = !ctrl), active: ctrl),
              key("ALT", () => setState(() => alt = !alt), active: alt),
              key("←", () => widget.controller.sendArrowLeft()),
              key("↓", () => widget.controller.sendArrowDown()),
              key("→", () => widget.controller.sendArrowRight()),
              key("PGDN", () => send("\x1b[6~")),
            ],
          ),
        ],
      ),
    );
  }
}
