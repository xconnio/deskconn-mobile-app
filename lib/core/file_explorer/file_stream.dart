import 'dart:async';
import 'dart:io';

import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/file_explorer/utils.dart';
import 'package:flutter/foundation.dart';

class StreamMediaServer {
  final FileExplorerController controller;
  final String path;
  final String name;
  final int size;

  HttpServer? _server;

  StreamMediaServer({required this.controller, required this.path, required this.name, required this.size});

  Uri? get uri {
    final server = _server;
    if (server == null) return null;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['stream', name],
    );
  }

  Future<Uri> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    _server!.listen(_handleRequest, onError: (Object e) => debugPrint('Stream server error: $e'));
    return uri!;
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader), size);
    final offset = range.$1;
    final length = range.$2;

    try {
      final result = await controller.streamRange(path, offset, length);
      final end = result.offset + result.length - 1;
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType.parse(mimeTypeForName(name))
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes ${result.offset}-$end/${result.size}')
        ..headers.contentLength = result.length;

      if (request.method != 'HEAD') {
        await request.response.addStream(result.stream);
      }
    } catch (e) {
      debugPrint('Range stream failed: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }
}

// Cap applied only to open-ended "give me the rest of the file" requests
// (no Range header, or "bytes=N-" with no end) — a player that doesn't say
// how much it wants gets a bounded first chunk instead of the whole file,
// and issues its own follow-up range requests (including tail probes for
// MP4 files whose moov atom isn't at the front) as it needs more. Explicit
// ranges and suffix ("last N bytes") requests are already deliberately
// bounded by the caller, so they're honored exactly.
const _initialChunkSize = 2 * 1024 * 1024; // 2MB

(int, int) _parseRange(String? header, int size) {
  if (size <= 0) return (0, 0);
  if (header == null || !header.startsWith('bytes=')) {
    return (0, size < _initialChunkSize ? size : _initialChunkSize);
  }

  final value = header.substring('bytes='.length).split(',').first.trim();
  final dash = value.indexOf('-');
  if (dash < 0) return (0, size < _initialChunkSize ? size : _initialChunkSize);

  final startPart = value.substring(0, dash).trim();
  final endPart = value.substring(dash + 1).trim();

  if (startPart.isEmpty) {
    final suffix = int.tryParse(endPart) ?? size;
    final length = suffix.clamp(0, size);
    return (size - length, length);
  }

  final start = (int.tryParse(startPart) ?? 0).clamp(0, size - 1);
  if (endPart.isEmpty) {
    final remaining = size - start;
    return (start, remaining < _initialChunkSize ? remaining : _initialChunkSize);
  }

  final end = (int.tryParse(endPart) ?? size - 1).clamp(start, size - 1);
  return (start, end - start + 1);
}

String mimeTypeForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (kVideoExts.contains(ext)) {
    return switch (ext) {
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'ogv' => 'video/ogg',
      '3gp' => 'video/3gpp',
      _ => 'video/mp4',
    };
  }
  if (kAudioExts.contains(ext)) {
    return switch (ext) {
      'wav' => 'audio/wav',
      'ogg' || 'opus' => 'audio/ogg',
      'flac' => 'audio/flac',
      'aac' => 'audio/aac',
      'm4a' => 'audio/mp4',
      _ => 'audio/mpeg',
    };
  }
  return 'application/octet-stream';
}
