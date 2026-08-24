import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class TextEditorScreen extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const TextEditorScreen({super.key, required this.bytes, required this.fileName});

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late final TextEditingController _controller = TextEditingController(text: utf8.decode(widget.bytes));
  late final String _initialText = _controller.text;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(context, Uint8List.fromList(utf8.encode(_controller.text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, null);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: Text(widget.fileName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _controller.text == _initialText ? null : _save,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            autofocus: true,
            cursorColor: Colors.white,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2), fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }
}
