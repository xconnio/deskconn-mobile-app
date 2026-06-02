import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xconn/xconn.dart';
// ignore: implementation_imports
import 'package:xconn/src/types.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_encryption.dart';
import 'package:deskconn_mobile_app/core/terminal/blocking_queue.dart';
import 'models.dart';

class FileExplorerController {
  final Session session;
  final String realm;
  Encryption? _encryption;
  bool _keyExchanged = false;

  static final Map<String, Uint8List> _thumbnailCache = {};
  static final Map<String, Future<Uint8List>> _thumbnailFutures = {};

  static int _activeDownloads = 0;
  static const int _maxConcurrentDownloads = 4;
  static final List<Completer<void>> _downloadWaiters = [];

  FileExplorerController(this.session, this.realm);

  bool get isKeyExchanged => _keyExchanged;

  Future<void> ensureKeyExchanged() async {
    if (_keyExchanged) return;

    _encryption = await Encryption.create();
    final res = await session.call('io.xconn.deskconn.deskconnd.key.exchange', args: [_encryption!.clientPublicKey]);

    if (res.args.isEmpty) {
      throw Exception('Key exchange failed: empty response');
    }

    final serverKey = _coerceBytes(res.args[0]);
    final keyPayload = serverKey.length == 32 ? Uint8List.fromList([...utf8.encode('KEY:'), ...serverKey]) : serverKey;

    await _encryption!.acceptServerKey(keyPayload);
    _keyExchanged = true;
  }

  Future<FileBrowseResult> browse(String path) async {
    await ensureKeyExchanged();
    final encryptedPath = _encryption!.encrypt(utf8.encode(path));
    final res = await session.call('io.xconn.deskconn.deskconnd.file.browse', args: [encryptedPath]);
    if (res.args.isEmpty) throw Exception('Browse failed: empty response');
    final decrypted = _encryption!.decrypt(_coerceBytes(res.args[0]));
    return FileBrowseResult.fromJson(jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>);
  }

  Future<Uint8List> read(String path) async => _download(path, false);

  Future<Uint8List> thumbnail(String path) async {
    final cacheKey = '$realm:$path';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey]!;
    }
    if (_thumbnailFutures.containsKey(cacheKey)) {
      return _thumbnailFutures[cacheKey]!;
    }

    final future = _runThumbnailDownload(cacheKey, path);
    _thumbnailFutures[cacheKey] = future;
    return future;
  }

  Future<Uint8List> _runThumbnailDownload(String cacheKey, String path) async {
    try {
      final data = await _download(path, true);
      _thumbnailCache[cacheKey] = data;
      return data;
    } finally {
      _thumbnailFutures.remove(cacheKey);
    }
  }

  Future<Uint8List> _download(String path, bool isThumbnail) async {
    await _acquireSlot();
    try {
      return await _executeDownload(path, isThumbnail);
    } finally {
      _releaseSlot();
    }
  }

  Future<void> _acquireSlot() async {
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads++;
      return;
    }
    final waiter = Completer<void>();
    _downloadWaiters.add(waiter);
    await waiter.future;
  }

  void _releaseSlot() {
    if (_downloadWaiters.isNotEmpty) {
      _downloadWaiters.removeAt(0).complete();
    } else {
      _activeDownloads--;
    }
  }

  Future<Uint8List> _executeDownload(String path, bool isThumbnail) async {
    final enc = await Encryption.create();

    final List<Result> queue = [];
    Completer<void>? wakeUp;
    bool done = false;
    Object? streamError;

    void notify() {
      final w = wakeUp;
      wakeUp = null;
      w?.complete();
    }

    session
        .callProgress('io.xconn.deskconn.deskconnd.file.download', (result) {
          queue.add(result);
          notify();
        }, args: [path, isThumbnail, enc.clientPublicKey])
        .then((_) {
          done = true;
          notify();
        })
        .catchError((Object e) {
          streamError = e;
          done = true;
          notify();
        });

    bool keyReceived = false;
    final builder = BytesBuilder(copy: false);

    while (true) {
      if (queue.isEmpty) {
        if (done) break;
        wakeUp = Completer<void>();
        await wakeUp!.future;
        continue;
      }

      final result = queue.removeAt(0);
      if (result.args.isEmpty) continue;

      if (!keyReceived) {
        final raw = _coerceBytes(result.args[0]);
        final keyPayload = raw.length == 32 ? Uint8List.fromList([...utf8.encode('KEY:'), ...raw]) : raw;
        await enc.acceptServerKey(keyPayload);
        keyReceived = true;
        continue;
      }

      final type = result.args[0];
      if (type == 'D' && result.args.length > 1) {
        builder.add(enc.decrypt(_coerceBytes(result.args[1])));
      }
    }

    if (streamError != null) throw streamError!;
    return builder.takeBytes();
  }

  Future<void> upload(String localFilePath, String remoteDir, {void Function(int sent, int total)? onProgress}) async {
    final file = File(localFilePath);
    if (!await file.exists()) throw Exception('File not found: $localFilePath');

    await ensureKeyExchanged();
    final enc = _encryption!;

    final fileName = localFilePath.split('/').last;
    final remoteFilePath = remoteDir.isEmpty || remoteDir == '/' ? '/$fileName' : '$remoteDir/$fileName';

    final stat = await file.stat();
    onProgress?.call(0, stat.size);

    var seq = 0;
    final outgoing = BlockingQueue<Progress>();

    Future<Progress> sender() => outgoing.take();
    Future<void> receiver(Result _) async {}

    final callFuture = session.callProgressiveProgress('io.xconn.deskconn.deskconnd.file.upload', sender, receiver);

    try {
      outgoing.put(
        Progress(
          args: [
            'I',
            seq,
            enc.encrypt(
              utf8.encode(
                jsonEncode({'remote_path': remoteFilePath, 'source_is_dir': false, 'target_is_dir_hint': false}),
              ),
            ),
          ],
          options: {'progress': true},
        ),
      );
      seq++;

      outgoing.put(
        Progress(
          args: [
            'H',
            seq,
            enc.encrypt(
              utf8.encode(
                jsonEncode({'name': fileName, 'rel_path': '', 'size': stat.size, 'mode': 420, 'is_dir': false}),
              ),
            ),
          ],
          options: {'progress': true},
        ),
      );
      seq++;

      const chunkSize = 1024 * 1024;
      int sentBytes = 0;
      final raf = await file.open();
      try {
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          outgoing.put(Progress(args: ['D', seq, enc.encrypt(chunk)], options: {'progress': true}));
          seq++;
          sentBytes += chunk.length;
          onProgress?.call(sentBytes, stat.size);
        }
      } finally {
        await raf.close();
      }

      outgoing.put(Progress(args: ['E', seq], options: {}));

      await callFuture.timeout(const Duration(seconds: 10), onTimeout: () => Result());
    } catch (e) {
      outgoing.cancelPending(StateError('Upload aborted'));
      rethrow;
    }
  }

  Future<void> rename(String oldPath, String newPath) async =>
      _callEncrypted('io.xconn.deskconn.deskconnd.file.rename', {'old_path': oldPath, 'new_path': newPath});

  Future<void> delete(String path) async => _callEncrypted('io.xconn.deskconn.deskconnd.file.delete', {'path': path});

  Future<void> copy(String srcPath, String destPath) async =>
      _callEncrypted('io.xconn.deskconn.deskconnd.file.copy', {'src': srcPath, 'dst': destPath});

  Future<void> _callEncrypted(String procedure, Map<String, dynamic> payload) async {
    await ensureKeyExchanged();
    final encrypted = _encryption!.encrypt(utf8.encode(jsonEncode(payload)));
    await session.call(procedure, args: [encrypted]);
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is String) return Uint8List.fromList(base64.decode(raw));
    throw FormatException('Unsupported payload type: ${raw.runtimeType}');
  }
}
