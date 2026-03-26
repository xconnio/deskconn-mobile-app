import "dart:async";
import "dart:collection";
import "dart:convert";

import "package:xterm/core.dart";
import "package:xconn/xconn.dart";
// ignore: implementation_imports
import "package:xconn/src/types.dart";

class BlockingQueue<T> {
  final Queue<T> _queue = Queue<T>();
  final List<Completer<T?>> _waiters = [];

  void put(T item) {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeAt(0);
      waiter.complete(item);
    } else {
      _queue.add(item);
    }
  }

  Future<T> take() {
    if (_queue.isNotEmpty) {
      return Future.value(_queue.removeFirst());
    }

    final completer = Completer<T>();
    _waiters.add(completer);
    return completer.future;
  }
}

class ShellController {
  final Terminal terminal = Terminal();
  final Session session;

  bool _running = false;
  Timer? _resizeTimer;

  final BlockingQueue<Progress> _outgoingQueue = BlockingQueue();

  ShellController(this.session);

  Future<void> start() async {
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
      terminal.write("\r\nShell error: $e\r\n");
    } finally {
      _running = false;
      _cleanup();
    }
  }

  void _sendSize() {
    if (_running) {
      var progress = Progress(args: ["SIZE:${terminal.viewWidth}:${terminal.viewHeight}"], options: {"progress": true});
      _outgoingQueue.put(progress);
    }
  }

  void attachInput() {
    terminal.onOutput = (String data) {
      if (_running && data.isNotEmpty) {
        _outgoingQueue.put(Progress(args: [data], options: {"progress": true}));
      }
    };
  }

  Future<Progress> _sender() async {
    return await _outgoingQueue.take();
  }

  void _receiver(Result result) {
    if (result.args.isEmpty) return;
    final raw = result.args.first;
    String text;
    try {
      if (raw is List<int>) {
        text = utf8.decode(raw);
      } else if (raw is String) {
        text = utf8.decode(base64.decode(raw));
      } else {
        text = raw.toString();
      }
    } catch (_) {
      text = raw.toString();
    }
    if (text.isNotEmpty) terminal.write(text);
  }

  void _cleanup() {
    _resizeTimer?.cancel();
  }

  void dispose() {
    _running = false;
    _cleanup();
  }

  void sendSpecialKey(String sequence) {
    if (_running) {
      var progress = Progress(args: [sequence], options: {"progress": true});
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
}
