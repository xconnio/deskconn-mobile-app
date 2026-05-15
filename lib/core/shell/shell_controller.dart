import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/core.dart';
// ignore: implementation_imports
import 'package:xconn/src/types.dart';

import 'blocking_queue.dart';
import 'shell_background_service.dart';
import 'shell_encryption.dart';
import '../wamp/desktop_connection_manager.dart';

class ShellController {
  final Terminal terminal = Terminal();
  final ShellLaunchConfig config;

  void Function()? onStarted;
  void Function()? onExit;
  void Function()? onClosed;
  void Function()? onModifierChanged;

  bool ctrl = false;
  bool alt = false;
  bool _running = false;
  bool _keyReceived = false;
  bool _clientKeySent = false;
  bool _disposed = false;
  Timer? _resizeTimer;
  String _inputBuffer = '';
  Encryption? _encryption;

  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue();

  bool get isActive => _running;
  bool get isReady => _keyReceived;

  ShellController({required this.config});

  Future<void> start() async {
    if (_running) return;

    final connection =
        DesktopConnectionManager().get(config.realm) ??
        await DesktopConnectionManager().connect(
          realm: config.realm,
          authId: config.authId,
          privateKey: config.privateKey,
          webRtcEnabled: config.webRtcEnabled,
          turnCredentials: config.turnCredentials,
        );

    _encryption = await Encryption.create();
    _running = true;
    _sendSize();

    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), _sendSize);
    };
    _attachInput();

    await startShellBackgroundService(config);

    try {
      await connection.session.callProgressiveProgress('io.xconn.deskconn.deskconnd.shell', _sender, _receiver);
    } catch (e) {
      if (!_disposed) terminal.write('\r\nShell error: $e\r\n');
    } finally {
      _running = false;
      _cleanup();
      unawaited(dismissShellNotification());
      onClosed?.call();
      final exit = onExit;
      onExit = null;
      exit?.call();
    }
  }

  void _sendSize() {
    if (!_running) return;
    if (!_keyReceived && _clientKeySent) return;
    final payload = _encodeOutboundText('SIZE:${terminal.viewWidth}:${terminal.viewHeight}', encrypt: _keyReceived);
    _clientKeySent = true;
    _outgoingQueue.put(Progress(args: [payload], options: {'progress': true}));
  }

  void _attachInput() {
    terminal.onOutput = (String data) {
      if (!_running || data.isEmpty) return;

      String output = data;
      if (ctrl) {
        output = _applyCtrl(output);
        ctrl = false;
        onModifierChanged?.call();
      }
      if (alt) {
        output = '\x1b$output';
        alt = false;
        onModifierChanged?.call();
      }

      if (_keyReceived) {
        _outgoingQueue.put(Progress(args: [_encodeOutboundText(output)], options: {'progress': true}));
      }

      for (final rune in output.runes) {
        final char = String.fromCharCode(rune);
        if (char == '\r' || char == '\n') {
          final cmd = _inputBuffer.trim();
          if (cmd == 'exit' || cmd == 'logout') onExit?.call();
          _inputBuffer = '';
        } else if (rune == 4) {
          if (_inputBuffer.isEmpty) onExit?.call();
          _inputBuffer = '';
        } else if (rune >= 32) {
          _inputBuffer += char;
        } else {
          _inputBuffer = '';
        }
      }
    };
  }

  String _applyCtrl(String data) {
    return data.runes.map((code) {
      if (code >= 97 && code <= 122) return String.fromCharCode(code - 96);
      return String.fromCharCode(code);
    }).join();
  }

  Future<Progress> _sender() async {
    if (_disposed) throw StateError('Shell closed');
    try {
      return await _outgoingQueue.take();
    } catch (_) {
      throw StateError('Shell closed');
    }
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
        text = utf8.decode(_coerceBytes(raw));
      } catch (_) {
        text = raw.toString();
      }
    }
    if (text.isNotEmpty) terminal.write(text);
  }

  void _cleanup() {
    _resizeTimer?.cancel();
  }

  Uint8List _encodeOutboundText(String text, {bool encrypt = true}) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final enc = _encryption!;
    if (!encrypt) return enc.buildClientFirstMessage(bytes);
    return enc.encrypt(bytes);
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is String) return Uint8List.fromList(base64.decode(raw));
    throw FormatException('Unsupported shell payload type: ${raw.runtimeType}');
  }

  void sendSpecialKey(String sequence) {
    if (!_running || !_keyReceived) return;
    _outgoingQueue.put(Progress(args: [_encodeOutboundText(sequence)], options: {'progress': true}));
  }

  void sendTab() => sendSpecialKey('\t');
  void sendEsc() => sendSpecialKey('\x1b');
  void sendCtrlC() => sendSpecialKey('\x03');
  void sendCtrlD() => sendSpecialKey('\x04');
  void sendArrowUp() => sendSpecialKey('\x1b[A');
  void sendArrowDown() => sendSpecialKey('\x1b[B');
  void sendArrowRight() => sendSpecialKey('\x1b[C');
  void sendArrowLeft() => sendSpecialKey('\x1b[D');
  void sendHome() => sendSpecialKey('\x1b[H');
  void sendEnd() => sendSpecialKey('\x1b[F');
  void sendDel() => sendSpecialKey('\x1b[3~');

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _cleanup();
    _outgoingQueue.cancelPending(StateError('Shell closed'));
    unawaited(dismissShellNotification());
    final exit = onExit;
    onExit = null;
    exit?.call();
  }
}
