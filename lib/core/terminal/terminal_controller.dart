import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/core.dart';
// ignore: implementation_imports
import 'package:xconn/src/types.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;

import 'blocking_queue.dart';
import 'shell_stream.dart';
import 'terminal_background_service.dart';
import 'terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/network/connectivity_service.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';

enum _StreamShellResult { started, channelUnavailable, unsupported }

class TerminalController {
  final Terminal terminal = Terminal();
  final DesktopSessionLaunchConfig config;

  void Function()? onStarted;
  void Function()? onExit;
  void Function()? onClosed;
  void Function()? onModifierChanged;
  void Function(Object error)? onError;
  void Function()? onReconnecting;
  void Function()? onReconnected;

  bool ctrl = false;
  bool alt = false;
  bool _running = false;
  bool _keyReceived = false;
  bool _clientKeySent = false;
  bool _disposed = false;
  bool _shellExited = false;
  bool _reconnecting = false;
  Timer? _resizeTimer;
  Encryption? _encryption;
  bool _closeFrameSent = false;
  bool _exitFired = false;
  ShellHandle? _shellHandle;

  static bool _streamShellSupported = true;
  static web_rtc.WebRTCSession? _consumedShellSession;
  static const _reconnectDelay = Duration(seconds: 2);

  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue();

  bool get isActive => _running;
  bool get isReady => _shellHandle != null || _keyReceived;

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
    await _connectAndRun();
  }

  Future<void> _connectAndRun() async {
    final prewarm = _shellPrewarm;
    if (prewarm != null) await prewarm;

    final DesktopConnection connection;
    try {
      connection =
          DesktopConnectionManager().get(config.realm) ??
          await DesktopConnectionManager().connect(
            realm: config.realm,
            authId: config.authId,
            privateKey: config.privateKey,
            webRtcEnabled: config.webRtcEnabled,
          );
    } catch (e) {
      _log('connect failed error=$e');
      onError?.call(e);
      return;
    }
    _log('session ready p2p=${connection.isP2P}');

    if (_streamShellSupported) {
      var result = await _runStreamShell(connection.webRtcSession);
      if (result == _StreamShellResult.channelUnavailable) {
        result = await _reconnectForShellChannel();
      }
      if (result == _StreamShellResult.started) return;
      if (result == _StreamShellResult.unsupported) _streamShellSupported = false;
    }
    await _runWampShell(connection);
  }

  Future<_StreamShellResult> _reconnectForShellChannel() async {
    try {
      final fresh = await _acquireFreshConnection();
      return await _runStreamShell(fresh.webRtcSession);
    } catch (e) {
      _log('shell channel reconnect failed error=$e');
      return _StreamShellResult.unsupported;
    }
  }

  Future<DesktopConnection> _acquireFreshConnection() async {
    final fresh = await DesktopConnectionManager().reacquire(
      realm: config.realm,
      authId: config.authId,
      privateKey: config.privateKey,
      webRtcEnabled: config.webRtcEnabled,
    );
    fresh.isAgentOnline = true;
    return fresh;
  }

  static Future<void>? _shellPrewarm;

  // A connection carries a single 'shell' channel, so the stream shell spends
  // it. Warming a replacement up in the background the moment the terminal
  // closes keeps the next terminal instant instead of paying for a reconnect.
  static void _prewarmShellConnection(DesktopSessionLaunchConfig config) {
    if (_shellPrewarm != null) return;
    _shellPrewarm = DesktopConnectionManager()
        .reacquire(
          realm: config.realm,
          authId: config.authId,
          privateKey: config.privateKey,
          webRtcEnabled: config.webRtcEnabled,
        )
        .then<void>((connection) => connection.isAgentOnline = true)
        .catchError((Object _) {})
        .whenComplete(() => _shellPrewarm = null);
  }

  Future<_StreamShellResult> _runStreamShell(web_rtc.WebRTCSession? rtc) async {
    if (rtc == null) return _StreamShellResult.unsupported;
    // A connection carries exactly one 'shell' channel, created with the offer
    // (Android can't be relied on to open more later) -- once it has served a
    // shell it is spent, so a second terminal needs a fresh connection.
    if (identical(rtc, _consumedShellSession)) return _StreamShellResult.channelUnavailable;
    _running = true;
    _shellExited = false;

    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), () {
        _shellHandle?.resize(terminal.viewWidth, terminal.viewHeight);
      });
    };

    terminal.onOutput = (String data) {
      if (!_running || data.isEmpty || _shellHandle == null) return;

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

      _shellHandle!.send(Uint8List.fromList(utf8.encode(output)));
    };

    try {
      final handle = await openShell(
        rtc,
        terminal.viewWidth,
        terminal.viewHeight,
        (bytes) {
          if (!_disposed) terminal.write(utf8.decode(bytes, allowMalformed: true));
        },
        () {
          _shellExited = true;
          _fireExit();
        },
      );

      if (_disposed || _shellExited) {
        await handle.close();
        return _StreamShellResult.started;
      }

      _consumedShellSession = rtc;
      _shellHandle = handle;
      handle.resize(terminal.viewWidth, terminal.viewHeight);
      onStarted?.call();
      return _StreamShellResult.started;
    } on ShellChannelUnavailableException catch (e) {
      _log('shell channel unavailable error=$e');
      _shellHandle = null;
      return _StreamShellResult.channelUnavailable;
    } catch (e) {
      _log('stream shell unavailable error=$e');
      _shellHandle = null;
      return _StreamShellResult.unsupported;
    }
  }

  Future<void> _runWampShell(DesktopConnection connection) async {
    _outgoingQueue.clear();
    _encryption = await Encryption.create();
    _keyReceived = false;
    _clientKeySent = false;
    _closeFrameSent = false;
    _running = true;
    _sendSize();

    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), _sendSize);
    };
    _attachInput();

    try {
      await connection.session.callProgressiveProgress(DeskconnProcedures.deskconndShell, _sender, _receiver);
    } catch (e) {
      // Mirrors what a real ssh client prints on a dropped connection —
      // a clean disconnect notice, not a raw exception dump.
      if (!_disposed) terminal.write('\r\nConnection to ${config.desktopName} closed.\r\n');
      _log('shell stream error=$e');
    } finally {
      _running = false;
      _cleanup();
      final exiting = _disposed || _shellExited;
      _log('shell stream finished disposed=$_disposed shellExited=$_shellExited exiting=$exiting');
      if (exiting) {
        onClosed?.call();
        _fireExit();
      } else {
        unawaited(_attemptReconnect());
      }
    }
  }

  Future<void> _attemptReconnect() async {
    if (_disposed || _reconnecting) return;
    _reconnecting = true;
    onReconnecting?.call();
    terminal.write('\r\n[Reconnecting…]\r\n');

    while (!_disposed) {
      if (!ConnectivityService().hasConnection) {
        await Future.delayed(_reconnectDelay);
        continue;
      }
      try {
        final connection = await DesktopConnectionManager().reacquire(
          realm: config.realm,
          authId: config.authId,
          privateKey: config.privateKey,
          webRtcEnabled: config.webRtcEnabled,
        );
        connection.isAgentOnline = true;
        break;
      } catch (e) {
        _log('reconnect failed error=$e');
        if (_disposed) {
          _reconnecting = false;
          return;
        }
        await Future.delayed(_reconnectDelay);
      }
    }

    _reconnecting = false;
    if (_disposed) return;
    onReconnected?.call();
    unawaited(_connectAndRun());
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
      _shellExited = true;
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
      // Server sends a MIGRATE: frame immediately after the KEY: frame.
      // It is a session-migration token for the desktop proxy, not PTY output.
      if (_isMigrateFrame(bytes)) return;
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
    if (_shellHandle != null) {
      _shellHandle!.send(Uint8List.fromList(utf8.encode('\x03')));
      unawaited(_shellHandle!.close());
      _shellHandle = null;
      return;
    }
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

  static bool _isMigrateFrame(Uint8List bytes) {
    const prefix = [0x4D, 0x49, 0x47, 0x52, 0x41, 0x54, 0x45, 0x3A]; // 'MIGRATE:'
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is String) return Uint8List.fromList(base64.decode(raw));
    throw FormatException('Unsupported terminal payload type: ${raw.runtimeType}');
  }

  void sendSpecialKey(String sequence) {
    if (!_running) return;
    if (_shellHandle != null) {
      _shellHandle!.send(Uint8List.fromList(utf8.encode(sequence)));
      return;
    }
    if (!_keyReceived) return;
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
    if (!_running) return;
    _log('request redraw');
    if (_shellHandle != null) {
      _shellHandle!.resize(terminal.viewWidth, terminal.viewHeight);
      return;
    }
    if (_keyReceived) _sendSize();
  }

  void dispose() {
    if (_disposed) return;
    _log('dispose');
    final usedStreamShell = _shellHandle != null;
    _requestShellClose();
    _disposed = true;
    _running = false;
    _cleanup();
    _fireExit();
    if (usedStreamShell) _prewarmShellConnection(config);
  }
}
