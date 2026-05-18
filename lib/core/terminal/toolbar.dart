import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Toolbar extends StatefulWidget {
  final dynamic controller;

  const Toolbar({super.key, required this.controller});

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.onModifierChanged = () => setState(() {});
  }

  void send(String key) {
    widget.controller.sendSpecialKey(key);
    setState(() {});
  }

  Widget key(String label, VoidCallback onTap, {Color? color, bool active = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
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
              key("DEL", () => widget.controller.sendDel()),
              key("HOME", () => widget.controller.sendHome()),
              key("↑", () => widget.controller.sendArrowUp()),
              key("END", () => widget.controller.sendEnd()),
              key("PGUP", () => send("\x1b[5~")),
            ],
          ),
          Row(
            children: [
              key("TAB", () => widget.controller.sendTab()),
              key(
                "CTRL",
                () => setState(() => widget.controller.ctrl = !widget.controller.ctrl),
                active: widget.controller.ctrl,
              ),
              key(
                "ALT",
                () => setState(() => widget.controller.alt = !widget.controller.alt),
                active: widget.controller.alt,
              ),
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
