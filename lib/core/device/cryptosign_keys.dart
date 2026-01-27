import 'dart:math';
import 'package:crypto/crypto.dart';

class CryptoSignKeys {
  static String generatePrivateKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return hex(bytes);
  }

  static String derivePublicKey(String privateKey) {
    final bytes = hexToBytes(privateKey);
    return sha256.convert(bytes).toString();
  }

  static String hex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
