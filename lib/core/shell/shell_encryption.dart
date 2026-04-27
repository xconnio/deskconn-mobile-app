import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

class Encryption {
  Encryption._(this._clientKeyPair, this.clientPublicKey);

  static const String _keyPrefix = 'KEY:';
  static final Uint8List _keyPrefixBytes = Uint8List.fromList(utf8.encode(_keyPrefix));

  final SimpleKeyPair _clientKeyPair;
  final Uint8List clientPublicKey;

  final DartChacha20 _cipher = Chacha20.poly1305Aead().toSync();

  SecretKeyData? _sendKey;
  SecretKeyData? _receiveKey;

  static Future<Encryption> create() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return Encryption._(keyPair, Uint8List.fromList(publicKey.bytes));
  }

  Uint8List buildClientFirstMessage(List<int> payload) {
    return Uint8List.fromList([...payload, ...utf8.encode(':$_keyPrefix'), ...clientPublicKey]);
  }

  Future<void> acceptServerKey(List<int> payload) async {
    if (payload.length != _keyPrefixBytes.length + 32) {
      throw const FormatException('Invalid server key payload length');
    }
    if (!_hasPrefix(payload, _keyPrefixBytes)) {
      throw const FormatException('Missing server key prefix');
    }

    final serverPublicKey = SimplePublicKey(payload.sublist(_keyPrefixBytes.length), type: KeyPairType.x25519);

    final sharedSecret = await X25519().sharedSecretKey(keyPair: _clientKeyPair, remotePublicKey: serverPublicKey);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    _sendKey = await hkdf.deriveKey(secretKey: sharedSecret, info: utf8.encode('frontendToBackend'));
    _receiveKey = await hkdf.deriveKey(secretKey: sharedSecret, info: utf8.encode('backendToFrontend'));
  }

  Uint8List encrypt(List<int> plaintext) {
    final key = _sendKey;
    if (key == null) {
      throw StateError('Shell encryption handshake is not complete');
    }

    final secretBox = _cipher.encryptSync(plaintext, secretKey: key);
    return Uint8List.fromList([...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes]);
  }

  Uint8List decrypt(List<int> payload) {
    final key = _receiveKey;
    if (key == null) {
      throw StateError('Shell encryption handshake is not complete');
    }
    if (payload.length < _cipher.nonceLength + _cipher.macAlgorithm.macLength) {
      throw const FormatException('Encrypted payload is too short');
    }

    final nonceEnd = _cipher.nonceLength;
    final macStart = payload.length - _cipher.macAlgorithm.macLength;
    final secretBox = SecretBox(
      payload.sublist(nonceEnd, macStart),
      nonce: payload.sublist(0, nonceEnd),
      mac: Mac(payload.sublist(macStart)),
    );

    return Uint8List.fromList(_cipher.decryptSync(secretBox, secretKey: key));
  }

  static bool _hasPrefix(List<int> data, List<int> prefix) {
    if (data.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}
