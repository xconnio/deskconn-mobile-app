import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:xconn/xconn.dart';
// ignore: implementation_imports
import 'package:xconn/src/types.dart';
import 'package:xconn_webrtc_dart/xconn_webrtc_dart.dart' as web_rtc;
import 'package:xterm/core.dart';

import 'shell_encryption.dart';

const String shellStartEvent = 'shell.start';
const String shellStartedEvent = 'shell.started';
const String shellInputEvent = 'shell.input';
const String shellOutputEvent = 'shell.output';
const String shellResizeEvent = 'shell.resize';
const String shellStopEvent = 'shell.stop';
const String shellStoppedEvent = 'shell.stopped';
const String shellErrorEvent = 'shell.error';
const String shellPingEvent = 'shell.ping';
const String shellPongEvent = 'shell.pong';

bool _serviceConfigured = false;
Future<void>? _serviceConfigureFuture;
const MethodChannel _shellNotificationChannel = MethodChannel('deskconn/shell_notification');

class ShellLaunchConfig {
  const ShellLaunchConfig({
    required this.sessionKey,
    required this.desktopName,
    required this.realm,
    required this.authId,
    required this.privateKey,
    required this.webRtcEnabled,
    this.turnCredentials,
  });

  final String sessionKey;
  final String desktopName;
  final String realm;
  final String authId;
  final String privateKey;
  final bool webRtcEnabled;
  final Map<String, dynamic>? turnCredentials;

  Map<String, Object> toEvent() {
    final event = <String, Object>{
      'sessionKey': sessionKey,
      'desktopName': desktopName,
      'realm': realm,
      'authId': authId,
      'privateKey': privateKey,
      'webRtcEnabled': webRtcEnabled,
    };
    final credentials = turnCredentials;
    if (credentials != null) {
      event['turnCredentials'] = credentials;
    }
    return event;
  }
}

Future<void> initializeShellBackgroundService() async {
  if (_serviceConfigured) return;
  final existingConfigure = _serviceConfigureFuture;
  if (existingConfigure != null) {
    await existingConfigure;
    return;
  }

  _serviceConfigureFuture = _configureShellBackgroundService();
  try {
    await _serviceConfigureFuture;
    _serviceConfigured = true;
  } finally {
    _serviceConfigureFuture = null;
  }
}

Future<void> _configureShellBackgroundService() {
  final service = FlutterBackgroundService();
  return service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: shellBackgroundServiceEntryPoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      initialNotificationTitle: 'Deskconn Shell',
      initialNotificationContent: 'Shell service is idle',
      foregroundServiceNotificationId: 1107,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: shellBackgroundServiceEntryPoint,
      onBackground: shellIosBackgroundEntryPoint,
    ),
  );
}

Future<void> startShellBackgroundService(ShellLaunchConfig config) async {
  await initializeShellBackgroundService();

  final service = FlutterBackgroundService();
  final pingToken = DateTime.now().microsecondsSinceEpoch.toString();
  final ready = Completer<void>();
  late final StreamSubscription<Map<String, dynamic>?> pongSub;
  pongSub = service.on(shellPongEvent).listen((event) {
    if (event?['token'] == pingToken && !ready.isCompleted) {
      ready.complete();
    }
  });

  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }

  try {
    for (var i = 0; i < 40 && !ready.isCompleted; i++) {
      service.invoke(shellPingEvent, {'token': pingToken});
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (!ready.isCompleted) {
      throw TimeoutException('Shell background service did not become ready.');
    }

    await ready.future;
    service.invoke(shellStartEvent, config.toEvent());
  } finally {
    await pongSub.cancel();
  }
}

void stopShellBackgroundService(String sessionKey) {
  FlutterBackgroundService().invoke(shellStopEvent, {'sessionKey': sessionKey});
}

@pragma('vm:entry-point')
Future<bool> shellIosBackgroundEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void shellBackgroundServiceEntryPoint(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  final runtime = _ShellBackgroundRuntime(service);

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(title: 'Deskconn Shell', content: 'Shell service is idle');
  }

  service.on(shellStartEvent).listen(runtime.start);
  service.on(shellInputEvent).listen(runtime.sendInput);
  service.on(shellResizeEvent).listen(runtime.resize);
  service.on(shellStopEvent).listen(runtime.stop);
  service.on(shellPingEvent).listen((event) {
    service.invoke(shellPongEvent, event);
  });
}

class ShellBackgroundController {
  ShellBackgroundController(this.config);

  static const int _outputChunkSize = 4096;
  static const int _maxOutputChunksPerFlush = 3;

  final ShellLaunchConfig config;
  final Terminal terminal = Terminal();
  final FlutterBackgroundService _service = FlutterBackgroundService();
  final Queue<String> _pendingOutput = Queue<String>();
  final Queue<String> _pendingInput = Queue<String>();

  void Function()? onStarted;
  void Function()? onExit;
  void Function()? onModifierChanged;

  StreamSubscription<Map<String, dynamic>?>? _startedSub;
  StreamSubscription<Map<String, dynamic>?>? _outputSub;
  StreamSubscription<Map<String, dynamic>?>? _stoppedSub;
  StreamSubscription<Map<String, dynamic>?>? _errorSub;
  Timer? _outputFlushTimer;
  Timer? _resizeTimer;
  Timer? _serviceWatchTimer;
  Timer? _exitStopTimer;

  bool ctrl = false;
  bool alt = false;
  bool _running = false;
  bool _started = false;
  String _inputBuffer = '';
  bool _disposed = false;
  bool _exitNotified = false;

  Future<void> start() async {
    _running = true;
    _listenForServiceEvents();
    _attachInput();
    try {
      await startShellBackgroundService(config);
    } catch (error) {
      _running = false;
      terminal.write('\r\n${_friendlyStartError(error)}\r\n');
      _notifyExit();
    }
  }

  void _listenForServiceEvents() {
    _startedSub ??= _service.on(shellStartedEvent).listen((event) {
      if (!_isCurrentSession(event)) return;
      _started = true;
      while (_pendingInput.isNotEmpty) {
        _sendInput(_pendingInput.removeFirst());
      }
      _showNotificationCloseAction();
      _sendSize();
      _startServiceWatch();
      onStarted?.call();
    });
    _outputSub ??= _service.on(shellOutputEvent).listen((event) {
      if (!_isCurrentSession(event)) return;
      final data = event?['data']?.toString();
      if (data != null && data.isNotEmpty) {
        _enqueueOutput(data);
      }
    });
    _stoppedSub ??= _service.on(shellStoppedEvent).listen((event) {
      if (!_isCurrentSession(event)) return;
      _running = false;
      _notifyExit();
    });
    _errorSub ??= _service.on(shellErrorEvent).listen((event) {
      if (!_isCurrentSession(event)) return;
      _running = false;
      final message = event?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        terminal.write('\r\n$message\r\n');
      }
      _notifyExit();
    });
  }

  void _enqueueOutput(String data) {
    for (var start = 0; start < data.length; start += _outputChunkSize) {
      final end = (start + _outputChunkSize).clamp(0, data.length);
      _pendingOutput.add(data.substring(start, end));
    }
    _scheduleOutputFlush();
  }

  void _scheduleOutputFlush() {
    if (_disposed || _outputFlushTimer != null || _pendingOutput.isEmpty) {
      return;
    }
    _outputFlushTimer = Timer(Duration.zero, _flushOutput);
  }

  void _flushOutput() {
    _outputFlushTimer = null;
    if (_disposed) {
      _pendingOutput.clear();
      return;
    }

    var chunksWritten = 0;
    while (_pendingOutput.isNotEmpty && chunksWritten < _maxOutputChunksPerFlush) {
      terminal.write(_pendingOutput.removeFirst());
      chunksWritten++;
    }

    if (_pendingOutput.isNotEmpty) {
      _outputFlushTimer = Timer(const Duration(milliseconds: 1), _flushOutput);
    }
  }

  void _attachInput() {
    terminal.onResize = (int w, int h, int pw, int ph) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 100), _sendSize);
    };

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

      if (_started) {
        _sendInput(output);
      } else {
        _pendingInput.add(output);
      }
      _trackExitCommands(output);
    };
  }

  void _sendInput(String output) {
    _service.invoke(shellInputEvent, {'sessionKey': config.sessionKey, 'data': output});
  }

  void _sendSize() {
    if (!_running || !_started) return;
    _service.invoke(shellResizeEvent, {
      'sessionKey': config.sessionKey,
      'width': terminal.viewWidth,
      'height': terminal.viewHeight,
    });
  }

  String _applyCtrl(String data) {
    return data.runes.map((code) {
      if (code >= 97 && code <= 122) return String.fromCharCode(code - 96);
      return String.fromCharCode(code);
    }).join();
  }

  void _trackExitCommands(String output) {
    for (final rune in output.runes) {
      if (rune == 4) {
        if (_inputBuffer.trim().isEmpty) _scheduleExitStop();
        _inputBuffer = '';
        continue;
      }

      if (rune == 8 || rune == 127) {
        if (_inputBuffer.isNotEmpty) {
          _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1);
        }
        continue;
      }

      if (rune == 13 || rune == 10) {
        final command = _inputBuffer.trim();
        if (command == 'exit' || command == 'logout') _scheduleExitStop();
        _inputBuffer = '';
        continue;
      }

      if (rune >= 32) {
        _inputBuffer += String.fromCharCode(rune);
      } else {
        _inputBuffer = '';
      }
    }
  }

  void _scheduleExitStop() {
    _exitStopTimer?.cancel();
    _exitStopTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_running || _disposed) return;
      stopShellBackgroundService(config.sessionKey);
    });
  }

  void _startServiceWatch() {
    _serviceWatchTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_running || _disposed) return;
      final isRunning = await _service.isRunning();
      if (isRunning || !_running || _disposed) return;
      _running = false;
      _notifyExit();
    });
  }

  void _notifyExit() {
    if (_disposed || _exitNotified) return;
    _exitNotified = true;
    onExit?.call();
  }

  String _friendlyStartError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timeout')) {
      return 'Shell connection timed out. Try again.';
    }
    return 'Shell connection ended.';
  }

  bool _isCurrentSession(Map<String, dynamic>? event) {
    return event?['sessionKey']?.toString() == config.sessionKey;
  }

  Future<void> _showNotificationCloseAction() async {
    try {
      await _shellNotificationChannel.invokeMethod('showShellNotification', {
        'title': 'Deskconn Shell',
        'content': 'Terminal is running on ${config.desktopName}',
      });
    } catch (_) {}
  }

  void sendSpecialKey(String sequence) {
    if (!_running) return;
    if (_started) {
      _sendInput(sequence);
    } else {
      _pendingInput.add(sequence);
    }
    _trackExitCommands(sequence);
  }

  void sendInterrupt() {
    _pendingOutput.clear();
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    sendSpecialKey('\x03');
  }

  void sendTab() => sendSpecialKey('\t');
  void sendEsc() => sendSpecialKey('\x1b');
  void sendCtrlC() => sendInterrupt();
  void sendCtrlD() => sendSpecialKey('\x04');
  void sendArrowUp() => sendSpecialKey('\x1b[A');
  void sendArrowDown() => sendSpecialKey('\x1b[B');
  void sendArrowRight() => sendSpecialKey('\x1b[C');
  void sendArrowLeft() => sendSpecialKey('\x1b[D');
  void sendHome() => sendSpecialKey('\x1b[H');
  void sendEnd() => sendSpecialKey('\x1b[F');
  void sendDel() => sendSpecialKey('\x1b[3~');

  void dispose() {
    _disposed = true;
    _running = false;
    _started = false;
    _pendingOutput.clear();
    _pendingInput.clear();
    _outputFlushTimer?.cancel();
    _resizeTimer?.cancel();
    _serviceWatchTimer?.cancel();
    _exitStopTimer?.cancel();
    _startedSub?.cancel();
    _outputSub?.cancel();
    _stoppedSub?.cancel();
    _errorSub?.cancel();
  }
}

class BlockingQueue<T> {
  final Queue<T> _queue = Queue<T>();
  final List<Completer<T>> _waiters = [];

  void put(T item) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(item);
      return;
    }
    _queue.add(item);
  }

  Future<T> take() {
    if (_queue.isNotEmpty) {
      return Future.value(_queue.removeFirst());
    }
    final completer = Completer<T>();
    _waiters.add(completer);
    return completer.future;
  }

  void clear() {
    _queue.clear();
  }

  void cancelPending(Object error) {
    clear();
    final waiters = List<Completer<T>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }
}

class _ShellBackgroundRuntime {
  _ShellBackgroundRuntime(this.service);

  static const int _outputChunkSize = 4096;
  static const int _maxOutputChunksPerFlush = 2;
  static const int _maxOutputHistoryLength = 12000;

  final ServiceInstance service;
  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue<Progress>();
  final Queue<String> _pendingOutput = Queue<String>();
  final Queue<String> _pendingInput = Queue<String>();

  Session? _session;
  Encryption? _encryption;
  Timer? _outputFlushTimer;
  String _outputHistory = '';
  bool _starting = false;
  bool _running = false;
  bool _keyReceived = false;
  bool _clientKeySent = false;
  String? _sessionKey;

  Future<void> start(dynamic event) async {
    final data = _asMap(event);
    final sessionKey = data['sessionKey']?.toString();
    final desktopName = data['desktopName']?.toString() ?? 'Shell';
    final realm = data['realm']?.toString();
    final authId = data['authId']?.toString();
    final privateKey = data['privateKey']?.toString();
    final webRtcEnabled = data['webRtcEnabled'] == true;
    final turnCredentials = _asMapOrNull(data['turnCredentials']);

    if (sessionKey == null || realm == null || authId == null || privateKey == null) {
      _emitError('Missing shell start parameters.');
      return;
    }

    if (_starting && _sessionKey == sessionKey) {
      return;
    }

    if (_running && _sessionKey == sessionKey) {
      service.invoke(shellStartedEvent, {'sessionKey': _sessionKey});
      if (_outputHistory.isNotEmpty) {
        service.invoke(shellOutputEvent, {'sessionKey': _sessionKey, 'data': _outputHistory});
      }
      return;
    }

    if (_running) {
      await _stopCurrentShell('Switching shell session');
    }

    _sessionKey = sessionKey;
    _starting = true;
    _setNotification('Deskconn Shell', 'Connecting to $desktopName');

    try {
      _encryption = await Encryption.create();
      _keyReceived = false;
      _clientKeySent = false;
      _outputHistory = '';
      _pendingInput.clear();
      _session = await _createShellSession(
        realm: realm,
        authId: authId,
        privateKey: privateKey,
        webRtcEnabled: webRtcEnabled,
        turnCredentials: turnCredentials,
      );
      _running = true;
      _setNotification('Deskconn Shell', 'Terminal is running on $desktopName');
      service.invoke(shellStartedEvent, {'sessionKey': _sessionKey});

      await _session!.callProgressiveProgress('io.xconn.deskconn.deskconnd.shell', _sender, _receiver);
    } catch (error) {
      if (_sessionKey == null) return;
      _emitError(_friendlyShellError(error));
    } finally {
      _starting = false;
      await _stopCurrentShell('Shell ended');
    }
  }

  void sendInput(dynamic event) {
    if (!_running) return;
    final data = _asMap(event);
    if (data['sessionKey']?.toString() != _sessionKey) return;
    final input = data['data']?.toString();
    if (input == null || input.isEmpty) return;
    if (input == '\x03') {
      _pendingOutput.clear();
      _outputFlushTimer?.cancel();
      _outputFlushTimer = null;
    }
    if (!_keyReceived) {
      _pendingInput.add(input);
      return;
    }
    _sendInput(input);
  }

  void resize(dynamic event) {
    if (!_running) return;
    final data = _asMap(event);
    if (data['sessionKey']?.toString() != _sessionKey) return;
    final width = data['width'];
    final height = data['height'];
    if (width is! int || height is! int) return;
    if (!_keyReceived && _clientKeySent) return;

    final payload = _encodeOutboundText('SIZE:$width:$height', encrypt: _keyReceived);
    _clientKeySent = true;
    _outgoingQueue.put(Progress(args: [payload], options: {'progress': true}));
  }

  Future<void> stop(dynamic event) async {
    final data = _asMap(event);
    final sessionKey = data['sessionKey']?.toString();
    if (sessionKey != null && sessionKey != _sessionKey) return;
    await _stopCurrentShell('Shell terminated');
    if (service is AndroidServiceInstance) {
      await (service as AndroidServiceInstance).stopSelf();
    }
  }

  Future<Progress> _sender() async {
    if (!_running && !_starting) {
      throw StateError('Shell stopped');
    }
    return _outgoingQueue.take();
  }

  Future<void> _receiver(Result result) async {
    if (result.args.isEmpty || _sessionKey == null) return;
    final raw = result.args.first;
    String output;

    try {
      final bytes = _coerceBytes(raw);
      if (!_keyReceived) {
        await _encryption!.acceptServerKey(bytes);
        _keyReceived = true;
        _flushPendingInput();
        return;
      }
      output = utf8.decode(_encryption!.decrypt(bytes));
    } catch (_) {
      output = raw.toString();
    }

    if (output.isEmpty) return;
    _enqueueOutput(output);
  }

  Future<void> _stopCurrentShell(String reason) async {
    final sessionKey = _sessionKey;
    _starting = false;
    _running = false;
    _pendingOutput.clear();
    _pendingInput.clear();
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    _outgoingQueue.cancelPending(StateError(reason));

    try {
      await _session?.close();
    } catch (_) {}

    _session = null;
    _encryption = null;
    _sessionKey = null;
    _setNotification('Deskconn Shell', 'Shell service is idle');

    if (sessionKey != null) {
      service.invoke(shellStoppedEvent, {'sessionKey': sessionKey, 'reason': reason});
    }
  }

  void _enqueueOutput(String data) {
    _outputHistory += data;
    if (_outputHistory.length > _maxOutputHistoryLength) {
      _outputHistory = _outputHistory.substring(_outputHistory.length - _maxOutputHistoryLength);
    }

    for (var start = 0; start < data.length; start += _outputChunkSize) {
      final end = (start + _outputChunkSize).clamp(0, data.length);
      _pendingOutput.add(data.substring(start, end));
    }
    _scheduleOutputFlush();
  }

  void _flushPendingInput() {
    while (_pendingInput.isNotEmpty) {
      _sendInput(_pendingInput.removeFirst());
    }
  }

  void _sendInput(String input) {
    _outgoingQueue.put(Progress(args: [_encodeOutboundText(input)], options: {'progress': true}));
  }

  void _scheduleOutputFlush() {
    if (!_running || _outputFlushTimer != null || _pendingOutput.isEmpty) {
      return;
    }
    _outputFlushTimer = Timer(Duration.zero, _flushOutput);
  }

  void _flushOutput() {
    _outputFlushTimer = null;
    if (!_running || _sessionKey == null) {
      _pendingOutput.clear();
      return;
    }

    var chunksWritten = 0;
    final buffer = StringBuffer();
    while (_pendingOutput.isNotEmpty && chunksWritten < _maxOutputChunksPerFlush) {
      buffer.write(_pendingOutput.removeFirst());
      chunksWritten++;
    }

    final data = buffer.toString();
    if (data.isNotEmpty) {
      service.invoke(shellOutputEvent, {'sessionKey': _sessionKey, 'data': data});
    }

    if (_pendingOutput.isNotEmpty) {
      _outputFlushTimer = Timer(const Duration(milliseconds: 4), _flushOutput);
    }
  }

  Future<Session> _createShellSession({
    required String realm,
    required String authId,
    required String privateKey,
    required bool webRtcEnabled,
    required Map<String, dynamic>? turnCredentials,
  }) async {
    final client = Client(
      config: ClientConfig(serializer: CBORSerializer(), authenticator: CryptoSignAuthenticator(authId, privateKey)),
    );
    final session = await client.connect(DeskconnConfig.wampUrl, realm);

    if (!webRtcEnabled) {
      return session;
    }

    try {
      final credentials = _usableTurnCredentials(turnCredentials) ?? await _fetchTurnCredentials(authId, privateKey);
      final config = web_rtc.ClientConfig(
        realm: realm,
        procedureWebRTCOffer: 'io.xconn.webrtc.offer',
        topicAnswererOnCandidate: 'io.xconn.webrtc.answerer.on_candidate',
        topicOffererOnCandidate: 'io.xconn.webrtc.offerer.on_candidate',
        iceServers: [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': credentials['urls'], 'username': credentials['username'], 'credential': credentials['credential']},
        ],
        serializer: CBORSerializer(),
        session: session,
        authenticator: CryptoSignAuthenticator(authId, privateKey),
      );

      return web_rtc.connectWAMP(config).timeout(const Duration(seconds: 12));
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Map<String, dynamic>? _usableTurnCredentials(Map<String, dynamic>? credentials) {
    if (credentials == null) return null;

    final expiresAt = credentials['expiresAt'];
    final username = credentials['username'];
    final credential = credentials['credential'];
    final urls = credentials['urls'];
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (expiresAt is int && expiresAt > nowSeconds + 60 && username is String && credential is String && urls is List) {
      return {'username': username, 'credential': credential, 'urls': urls};
    }

    return null;
  }

  Future<Map<String, dynamic>> _fetchTurnCredentials(String authId, String privateKey) async {
    final client = Client(
      config: ClientConfig(serializer: JSONSerializer(), authenticator: CryptoSignAuthenticator(authId, privateKey)),
    );
    final session = await client.connect(DeskconnConfig.wampUrl, DeskconnConfig.realm);

    try {
      final result = await session.call('io.xconn.deskconn.coturn.credentials.create');
      final turnCredential = result.args[0];

      final username = turnCredential['username'] as String;
      final credential = turnCredential['credential'] as String;
      final urls = turnCredential['urls'] as List<dynamic>;

      return {'username': username, 'credential': credential, 'urls': urls};
    } finally {
      await session.close();
    }
  }

  Uint8List _encodeOutboundText(String text, {bool encrypt = true}) {
    final encryption = _encryption;
    if (encryption == null) {
      throw StateError('Shell encryption is not initialized');
    }

    final bytes = Uint8List.fromList(utf8.encode(text));
    if (!encrypt) {
      return encryption.buildClientFirstMessage(bytes);
    }
    if (!_keyReceived) {
      throw StateError('Shell encryption handshake is not complete');
    }
    return encryption.encrypt(bytes);
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is String) return Uint8List.fromList(base64.decode(raw));
    throw FormatException('Unsupported shell payload type: ${raw.runtimeType}');
  }

  void _emitError(String message) {
    _setNotification('Deskconn Shell', message);
    service.invoke(shellErrorEvent, {'sessionKey': _sessionKey, 'message': message});
  }

  void _setNotification(String title, String content) {
    if (service is AndroidServiceInstance) {
      final androidService = service as AndroidServiceInstance;
      androidService.setForegroundNotificationInfo(title: title, content: content);
    }
  }

  Map<String, dynamic> _asMap(dynamic event) {
    if (event is Map) {
      return event.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic>? _asMapOrNull(dynamic event) {
    if (event is Map) {
      return event.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String _friendlyShellError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('wamp.error.no_such_procedure')) {
      return 'Remote device offline. Check internet and try again.';
    }
    if (text.contains('timeout')) {
      return 'Shell connection timed out. Try again.';
    }
    return 'Remote device offline or check internet and try again.';
  }
}
