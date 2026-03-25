import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:xconn/xconn.dart';

class WampClient {
  Client? _client;
  Session? _session;

  Session get session => _session!;

  Future<Session> connectCra({required String email, required String password, required String realm}) async {
    _client = Client(
      config: ClientConfig(serializer: JSONSerializer(), authenticator: WAMPCRAAuthenticator(email, password)),
    );

    _session = await _client!.connect(DeskconnConfig.wampUrl, realm);

    if (_session == null) {
      throw Exception('Failed to connect to WAMP server');
    }

    return _session!;
  }

  Future<Session> connectCryptoSign({required String authId, required String privateKey, required String realm}) async {
    _client = Client(
      config: ClientConfig(serializer: JSONSerializer(), authenticator: CryptoSignAuthenticator(authId, privateKey)),
    );

    _session = await _client!.connect(DeskconnConfig.wampUrl, realm);

    if (_session == null) {
      throw Exception('Failed to connect to WAMP server with cryptosign');
    }

    return _session!;
  }

  Future<void> disconnect() async {
    await _session?.close();
    _session = null;
    _client = null;
  }
}
