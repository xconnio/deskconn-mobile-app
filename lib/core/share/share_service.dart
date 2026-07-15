import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedUploadFile {
  final String path;
  final String name;
  final String? mimeType;
  final int? size;

  const SharedUploadFile({required this.path, required this.name, this.mimeType, this.size});

  factory SharedUploadFile.fromMap(Map<dynamic, dynamic> map) {
    final rawSize = map['size'];
    return SharedUploadFile(
      path: map['path']?.toString() ?? '',
      name: map['name']?.toString() ?? 'shared-file',
      mimeType: map['mimeType']?.toString(),
      size: rawSize is int ? rawSize : int.tryParse(rawSize?.toString() ?? ''),
    );
  }
}

class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  static const MethodChannel _channel = MethodChannel('deskconn/share');

  final ValueNotifier<List<SharedUploadFile>> pendingFiles = ValueNotifier<List<SharedUploadFile>>([]);
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedFiles') {
        _setPending(_parseFiles(call.arguments));
      }
    });

    try {
      final initial = await _channel.invokeMethod<List<dynamic>>('consumeInitialSharedFiles');
      _setPending(_parseFiles(initial));
    } on MissingPluginException {
      // Android provides this channel. Other platforms can still start normally.
    }
  }

  List<SharedUploadFile> takePendingFiles() {
    final files = pendingFiles.value;
    pendingFiles.value = const [];
    return files;
  }

  void _setPending(List<SharedUploadFile> files) {
    final usable = files.where((file) => file.path.isNotEmpty).toList(growable: false);
    if (usable.isEmpty) return;
    pendingFiles.value = usable;
  }

  List<SharedUploadFile> _parseFiles(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(SharedUploadFile.fromMap)
        .where((file) => file.path.isNotEmpty)
        .toList(growable: false);
  }
}
