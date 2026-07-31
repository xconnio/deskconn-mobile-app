import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:xconn/xconn.dart';

class QUICConnectionManager {
  static final _instance = QUICConnectionManager._();

  factory QUICConnectionManager() => _instance;

  QUICConnectionManager._();

  QUICSession? _root;

  Future<Session> openSession(String realm, QUICDialerConfig config) async {
    final root = _root;
    if (root != null && root.isConnected()) {
      return root.openSession(realm, config);
    }

    final newRoot = await connectQUIC(DeskconnConfig.quicAddr, realm, config);
    _root = newRoot;
    newRoot.onDisconnect(() {
      if (_root == newRoot) {
        _root = null;
      }
    });

    return newRoot.openSession(realm, config);
  }

  Future<void> close() async {
    final root = _root;
    _root = null;
    await root?.close();
  }
}
