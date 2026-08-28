import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:xconn/xconn.dart';

class QUICConnectionManager {
  static final _instance = QUICConnectionManager._();

  factory QUICConnectionManager() => _instance;

  QUICConnectionManager._();

  QUICSession? _root;
  Future<QUICSession>? _connecting;

  Future<Session> openSession(String realm, QUICDialerConfig config) async {
    final root = _root;
    if (root != null && root.isConnected()) {
      return root.openSession(realm, config);
    }

    final newRoot = await _connectRoot(realm, config);
    return newRoot.openSession(realm, config);
  }

  // Coalesces concurrent callers into a single in-flight connect instead of
  // racing separate connectQUIC() calls, whose last-writer-wins assignment
  // to _root would silently orphan whichever session lost the race.
  Future<QUICSession> _connectRoot(String realm, QUICDialerConfig config) {
    return _connecting ??= () async {
      try {
        final newRoot = await connectQUIC(DeskconnConfig.quicAddr, realm, config);
        _root = newRoot;
        newRoot.onDisconnect(() {
          if (_root == newRoot) {
            _root = null;
          }
        });
        return newRoot;
      } finally {
        _connecting = null;
      }
    }();
  }

  Future<void> close() async {
    final root = _root;
    _root = null;
    await root?.close();
  }
}
