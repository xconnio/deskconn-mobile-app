import 'dart:async';
import 'dart:collection';

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
