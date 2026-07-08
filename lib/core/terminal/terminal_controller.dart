import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/core.dart';
// ignore: implementation_imports
import 'package:xconn/src/types.dart';

import 'blocking_queue.dart';
import 'terminal_background_service.dart';
import 'terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';

class TerminalController {
  final Terminal terminal = Terminal();
  final DesktopSessionLaunchConfig config;

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
  Encryption? _encryption;
  bool _closeFrameSent = false;
  bool _exitFired = false;

  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue();

  bool get isActive => _running;
  bool get isReady => _keyReceived;

  TerminalController({required this.config});

  void _log(String message) {
    debugPrint('[Terminal ${config.realm} ${DateTime.now().toIso8601String()}] $message');
  }

  void _fireExit() {
    if (_exitFired) return;
    _exitFired = true;
    final exit = onExit;
    onExit = null;
    exit?.call();
  }

  Future<void> start() async {
    if (_running) return;
    _log('start requested');

    final connection =
        DesktopConnectionManager().get(config.realm) ??
        await DesktopConnectionManager().connect(
          realm: config.realm,
          authId: config.authId,
          privateKey: config.privateKey,
          webRtcEnabled: config.webRtcEnabled,
          turnCredentials: config.turnCredentials,
        );
    _log('session ready p2p=${connection.isP2P}');

    _encryption = await Encryption.create();
    _running = true;
    _sendSize();

    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), _sendSize);
    };
    _attachInput();

    try {
      await connection.session.callProgressiveProgress('io.xconn.deskconn.deskconnd.shell', _sender, _receiver);
    } catch (e) {
      // Mirrors what a real ssh client prints on a dropped connection —
      // a clean disconnect notice, not a raw exception dump — then exits
      // the session the same way a normal shell exit does.
      if (!_disposed) terminal.write('\r\nConnection to ${config.desktopName} closed.\r\n');
      _log('shell stream error=$e');
    } finally {
      _running = false;
      _cleanup();
      _log('shell stream finished disposed=$_disposed');
      onClosed?.call();
      _fireExit();
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
    };
  }

  String _applyCtrl(String data) {
    return data.runes.map((code) {
      if (code >= 97 && code <= 122) return String.fromCharCode(code - 96);
      return String.fromCharCode(code);
    }).join();
  }

  Future<Progress> _sender() async {
    if (_disposed) throw StateError('Terminal closed');
    try {
      return await _outgoingQueue.take();
    } catch (_) {
      throw StateError('Terminal closed');
    }
  }

  Future<void> _receiver(Result result) async {
    if (result.args.isEmpty) {
      _log('shell process exited (empty frame)');
      _fireExit();
      return;
    }
    final raw = result.args.first;
    String text;
    try {
      final bytes = _coerceBytes(raw);
      if (!_keyReceived) {
        await _encryption!.acceptServerKey(bytes);
        _keyReceived = true;
        _log('key exchange complete');
        // Send correct terminal dimensions now that key exchange is done.
        // The initial _sendSize() in start() may have sent SIZE:0:0 if the
        // terminal widget had not rendered yet, and the 100ms resize timer
        // is skipped while waiting for the key. This ensures the server PTY
        // gets the real size before the shell writes its first prompt.
        _sendSize();
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

  void _requestShellClose() {
    if (_closeFrameSent) return;
    _closeFrameSent = true;
    _log('send terminal close frame');
    _outgoingQueue.put(Progress(args: const [], options: const {}));
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
    throw FormatException('Unsupported terminal payload type: ${raw.runtimeType}');
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

  void clearScreen() {
    terminal.write('\x1b[2J\x1b[3J\x1b[H');
  }

  // Called when resuming an already-active session to force the server-side
  // shell to redraw its prompt via SIGWINCH.
  void requestRedraw() {
    if (!_running || !_keyReceived) return;
    _log('request redraw');
    _sendSize();
  }

  void dispose() {
    if (_disposed) return;
    _log('dispose');
    _requestShellClose();
    _disposed = true;
    _running = false;
    _cleanup();
    _fireExit();
  }
}
