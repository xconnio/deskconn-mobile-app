import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Toolbar extends StatefulWidget {
  final dynamic controller;
  final VoidCallback? onPaste;

  const Toolbar({super.key, required this.controller, this.onPaste});

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

  Widget key(String label, VoidCallback onTap, {bool active = false}) {
    return Expanded(
      child: _KeyButton(label: label, onTap: onTap, active: active),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onPaste = widget.onPaste;
    return Container(
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
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
          ),
          if (onPaste != null)
            SizedBox(
              width: 48,
              child: Semantics(
                label: 'Paste',
                button: true,
                child: _KeyButton(icon: Icons.content_paste, onTap: onPaste),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool active;

  const _KeyButton({this.label, this.icon, required this.onTap, this.active = false})
    : assert(label != null || icon != null, 'A key needs a label or an icon.');

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _pressed = false;

  Color get _bgColor {
    if (widget.active) return _pressed ? const Color(0xFFCCCCCC) : Colors.white;
    return _pressed ? const Color(0xFFBABABA) : Colors.black87;
  }

  Color get _textColor => widget.active ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(6)),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 16, color: _textColor)
              : Text(widget.label!, style: TextStyle(color: _textColor, fontSize: 13)),
        ),
      ),
    );
  }
}
