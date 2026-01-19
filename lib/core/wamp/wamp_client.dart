import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:xconn/xconn.dart';

class WampClient {
  Client? _client;
  Session? _session;

  Session get session => _session!;

  Future<Session> connectCra({
    required String email,
    required String password,
  }) async {
    await disconnect();

    _client = Client(
      config: ClientConfig(
        serializer: JSONSerializer(),
        authenticator: WAMPCRAAuthenticator(email, password),
        keepAliveInterval: const Duration(seconds: 10),
      ),
    );

    _session = await _client!.connect(
      DeskconnConfig.wampUrl,
      DeskconnConfig.realm,
    );

    return _session!;
  }

  Future<Session> connectCryptoSign() async {
    await disconnect();

    _client = Client(
      config: ClientConfig(
        serializer: JSONSerializer(),
        authenticator: CryptoSignAuthenticator(
          DeskconnConfig.serviceAuthId,
          DeskconnConfig.servicePrivateKey,
        ),
        keepAliveInterval: const Duration(seconds: 10),
      ),
    );

    _session = await _client!.connect(
      DeskconnConfig.wampUrl,
      DeskconnConfig.realm,
    );

    return _session!;
  }

  Future<void> disconnect() async {
    if (_session != null) {
      await _session!.close();
      _session = null;
    }
  }
}
