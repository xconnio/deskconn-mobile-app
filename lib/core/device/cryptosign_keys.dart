import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoSignKeys {
  static Future<String> generatePrivateKey() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    return bytesToHex(privateBytes);
  }

  static Future<String> derivePublicKey(String privateKeyHex) async {
    final algorithm = Ed25519();
    final seedBytes = hexToBytes(privateKeyHex);

    if (seedBytes.length != 32) {
      throw ArgumentError('Ed25519 seed must be 32 bytes (64 hex chars)');
    }

    final keyPair = await algorithm.newKeyPairFromSeed(seedBytes);
    final publicKey = await keyPair.extractPublicKey();

    final publicBytes = (publicKey).bytes;

    return bytesToHex(publicBytes);
  }

  static Future<Map<String, String>> signMessage(String privateKeyHex, String message) async {
    final algorithm = Ed25519();
    final seedBytes = hexToBytes(privateKeyHex);

    if (seedBytes.length != 32) {
      throw ArgumentError('Invalid seed length');
    }

    final keyPair = await algorithm.newKeyPairFromSeed(seedBytes);
    final messageBytes = Uint8List.fromList(message.codeUnits);

    final signature = await algorithm.sign(messageBytes, keyPair: keyPair);

    final pubBytes = (signature.publicKey as SimplePublicKey).bytes;

    return {'signature': bytesToHex(signature.bytes), 'publicKey': bytesToHex(pubBytes)};
  }

  static Future<bool> verifySignature(String message, String signatureHex, String publicKeyHex) async {
    final algorithm = Ed25519();

    final messageBytes = Uint8List.fromList(message.codeUnits);
    final sigBytes = hexToBytes(signatureHex);
    final pubBytes = hexToBytes(publicKeyHex);

    if (pubBytes.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }

    final publicKeyObj = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);

    final signatureObj = Signature(sigBytes, publicKey: publicKeyObj);

    return algorithm.verify(messageBytes, signature: signatureObj);
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toLowerCase();
  }

  static Uint8List hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[\s:-]'), '').toLowerCase();
    if (clean.length.isOdd) throw const FormatException('Odd hex length');
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      bytes[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}
