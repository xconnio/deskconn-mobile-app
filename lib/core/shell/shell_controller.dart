import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:xterm/core.dart";
import "package:xconn/xconn.dart";
// ignore: implementation_imports
import "package:xconn/src/types.dart";

import "blocking_queue.dart";
import "shell_encryption.dart";

class ShellController {
  final Terminal terminal = Terminal();
  final Session session;

  void Function()? onStarted;
  void Function()? onExit;
  void Function()? onModifierChanged;

  bool ctrl = false;
  bool alt = false;
  bool _running = false;
  bool _keyReceived = false;
  bool _clientKeySent = false;
  bool _disposed = false;
  Timer? _resizeTimer;
  String _inputBuffer = "";
  Encryption? _encryption;

  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue();

  ShellController(this.session);

  Future<void> start() async {
    _encryption = await Encryption.create();
    _running = true;
    _sendSize();

    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), _sendSize);
    };

    attachInput();

    try {
      await session.callProgressiveProgress("io.xconn.deskconn.deskconnd.shell", _sender, _receiver);
    } catch (e) {
      if (!_disposed) {
        terminal.write("\r\nShell error: $e\r\n");
      }
    } finally {
      _running = false;
      _cleanup();
      if (!_disposed) {
        onExit?.call();
      }
    }
  }

  void _sendSize() {
    if (_running) {
      if (!_keyReceived && _clientKeySent) {
        return;
      }
      final payload = _encodeOutboundText("SIZE:${terminal.viewWidth}:${terminal.viewHeight}", encrypt: _keyReceived);
      _clientKeySent = true;
      var progress = Progress(args: [payload], options: {"progress": true});
      _outgoingQueue.put(progress);
    }
  }

  String _applyCtrl(String data) {
    return data.runes.map((code) {
      if (code >= 97 && code <= 122) return String.fromCharCode(code - 96);
      return String.fromCharCode(code);
    }).join();
  }

  void attachInput() {
    terminal.onOutput = (String data) {
      if (!_running || data.isEmpty) return;
      if (!_keyReceived) return;

      String output = data;

      if (ctrl) {
        output = _applyCtrl(output);
        ctrl = false;
        onModifierChanged?.call();
      }

      if (alt) {
        output = "\x1b$output";
        alt = false;
        onModifierChanged?.call();
      }

      _outgoingQueue.put(Progress(args: [_encodeOutboundText(output)], options: {"progress": true}));

      for (final rune in output.runes) {
        final char = String.fromCharCode(rune);
        if (char == "\r" || char == "\n") {
          final cmd = _inputBuffer.trim();
          if (cmd == "exit" || cmd == "logout") onExit?.call();
          _inputBuffer = "";
        } else if (rune == 4) {
          if (_inputBuffer.isEmpty) onExit?.call();
          _inputBuffer = "";
        } else if (rune >= 32) {
          _inputBuffer += char;
        } else {
          _inputBuffer = "";
        }
      }
    };
  }

  Future<Progress> _sender() async {
    if (!_running || _disposed) {
      throw StateError('Shell closed');
    }
    return await _outgoingQueue.take();
  }

  Future<void> _receiver(Result result) async {
    if (result.args.isEmpty) return;
    final raw = result.args.first;
    String text;
    try {
      final bytes = _coerceBytes(raw);
      if (!_keyReceived) {
        await _encryption!.acceptServerKey(bytes);
        _keyReceived = true;
        onStarted?.call();
        return;
      }

      text = utf8.decode(_encryption!.decrypt(bytes));
    } catch (_) {
      try {
        final bytes = _coerceBytes(raw);
        text = utf8.decode(bytes);
      } catch (_) {
        text = raw.toString();
      }
    }
    if (text.isNotEmpty) terminal.write(text);
  }

  void _cleanup() {
    _resizeTimer?.cancel();
  }

  void dispose() {
    _disposed = true;
    _running = false;
    _cleanup();
    _outgoingQueue.cancelPending(StateError('Shell closed'));
  }

  void sendSpecialKey(String sequence) {
    if (_running && _keyReceived) {
      var progress = Progress(args: [_encodeOutboundText(sequence)], options: {"progress": true});
      _outgoingQueue.put(progress);
    }
  }

  void sendTab() => sendSpecialKey("\t");
  void sendEsc() => sendSpecialKey("\x1b");
  void sendCtrlC() => sendSpecialKey("\x03");
  void sendCtrlD() => sendSpecialKey("\x04");
  void sendArrowUp() => sendSpecialKey("\x1b[A");
  void sendArrowDown() => sendSpecialKey("\x1b[B");
  void sendArrowRight() => sendSpecialKey("\x1b[C");
  void sendArrowLeft() => sendSpecialKey("\x1b[D");
  void sendHome() => sendSpecialKey("\x1b[H");
  void sendEnd() => sendSpecialKey("\x1b[F");
  void sendDel() => sendSpecialKey("\x1b[3~");

  Uint8List _encodeOutboundText(String text, {bool encrypt = true}) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final encryption = _encryption;
    if (encryption == null) {
      throw StateError('Shell encryption is not initialized');
    }
    if (!encrypt) {
      return encryption.buildClientFirstMessage(bytes);
    }
    if (!_keyReceived) {
      throw StateError('Shell encryption handshake is not complete');
    }
    return encryption.encrypt(bytes);
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    if (raw is String) {
      return Uint8List.fromList(base64.decode(raw));
    }
    throw FormatException('Unsupported shell payload type: ${raw.runtimeType}');
  }
}
