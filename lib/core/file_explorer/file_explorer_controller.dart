import 'dart:convert';
import 'dart:typed_data';

import 'package:xconn/xconn.dart';
import '../shell/shell_encryption.dart';
import 'models.dart';

class FileExplorerController {
  final Session session;
  Encryption? _encryption;
  bool _keyExchanged = false;

  FileExplorerController(this.session);

  Future<void> ensureKeyExchanged() async {
    if (_keyExchanged) return;

    _encryption = await Encryption.create();
    final res = await session.call('io.xconn.deskconn.deskconnd.key.exchange', args: [_encryption!.clientPublicKey]);

    if (res.args.isEmpty) {
      throw Exception('Key exchange failed: empty response');
    }

    final serverKey = _coerceBytes(res.args[0]);
    // The Encryption class expects a prefix 'KEY:' in acceptServerKey
    // Let's check if the server returns it with the prefix.
    // If not, we might need to adjust.
    // Based on ShellController, it seems the server might send it without prefix if it's a regular call?
    // Actually, ShellController expects the prefix.

    // Let's check the web app logic again if it mentions a prefix.
    // It didn't mention a prefix in the summary.

    // I'll try to add the prefix if it's missing, to satisfy ShellEncryption.
    Uint8List keyPayload;
    if (serverKey.length == 32) {
      keyPayload = Uint8List.fromList([...utf8.encode('KEY:'), ...serverKey]);
    } else {
      keyPayload = serverKey;
    }

    await _encryption!.acceptServerKey(keyPayload);
    _keyExchanged = true;
  }

  Future<FileBrowseResult> browse(String path) async {
    await ensureKeyExchanged();

    final encryptedPath = _encryption!.encrypt(utf8.encode(path));
    final res = await session.call('io.xconn.deskconn.deskconnd.file.browse', args: [encryptedPath]);

    if (res.args.isEmpty) {
      throw Exception('Browse failed: empty response');
    }

    final decrypted = _encryption!.decrypt(_coerceBytes(res.args[0]));
    final decoded = utf8.decode(decrypted);
    return FileBrowseResult.fromJson(jsonDecode(decoded) as Map<String, dynamic>);
  }

  Future<void> rename(String oldPath, String newPath) async {
    await _callEncrypted('io.xconn.deskconn.deskconnd.file.rename', {'old_path': oldPath, 'new_path': newPath});
  }

  Future<void> delete(String path) async {
    await _callEncrypted('io.xconn.deskconn.deskconnd.file.delete', {'path': path});
  }

  Future<void> copy(String srcPath, String destPath) async {
    await _callEncrypted('io.xconn.deskconn.deskconnd.file.copy', {'src_path': srcPath, 'dest_path': destPath});
  }

  Future<void> _callEncrypted(String procedure, Map<String, dynamic> payload) async {
    await ensureKeyExchanged();

    final encryptedPayload = _encryption!.encrypt(utf8.encode(jsonEncode(payload)));
    final res = await session.call(procedure, args: [encryptedPayload]);

    if (res.args.isNotEmpty) {
      // Some procedures might return an encrypted result even if it's just 'ok'
      // But usually they just return or throw error.
    }
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    if (raw is String) {
      return Uint8List.fromList(base64.decode(raw));
    }
    throw FormatException('Unsupported payload type: ${raw.runtimeType}');
  }
}
