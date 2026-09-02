import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:deskconn_mobile_app/core/wamp/file_stream_service.dart';

class _Range {
  _Range(this.start, this.length, this.partial);

  final int start;
  final int length;
  final bool partial;
}

class _StreamSession {
  _StreamSession({required this.path, required this.size, required this.mimeType});

  final String path;
  final int size;
  final String mimeType;
}

// A loopback-only HTTP server that lets video_player/audioplayers (which need
// a URL, not a raw data channel) play a desktop file progressively: each
// distinct HTTP Range request is mapped straight to its own
// FileStreamService.openRange WebRTC read and streamed through as chunks
// arrive — no local buffering or ordering assumption, so an out-of-order
// probe (e.g. a player reading a trailing MP4 "moov" atom before the start
// of the file) is served on its own, not stuck behind a sequential
// from-byte-zero download. Mirrors the web app's fileStream.ts, which opens
// one data channel per range request for the same reason; this is safe here
// because every channel it might need is pre-negotiated at connect time (see
// desktop_connection_manager.dart's OfferConfig.additionalChannels), which is
// also why the number of ranges a single connection can serve is capped at
// kFileStreamChannelPoolSize.
class FileStreamServer {
  FileStreamServer(this._service);

  final FileStreamService _service;
  HttpServer? _server;
  final Map<String, _StreamSession> _sessions = {};
  int _nextId = 0;

  Future<Uri> open(String path, int size, String mimeType) async {
    await _ensureServer();
    final id = '${_nextId++}';
    _sessions[id] = _StreamSession(path: path, size: size, mimeType: mimeType);
    return Uri.parse('http://127.0.0.1:${_server!.port}/stream/$id');
  }

  Future<void> close(Uri uri) async {
    _sessions.remove(uri.pathSegments.last);
  }

  Future<void> dispose() async {
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments[0] != 'stream' || _sessions[segments[1]] == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final session = _sessions[segments[1]]!;

    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader), session.size);
    if (range == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${session.size}');
      await request.response.close();
      return;
    }

    try {
      final result = await _service.openRange(session.path, range.start, range.length);
      request.response.statusCode = range.partial ? HttpStatus.partialContent : HttpStatus.ok;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, session.mimeType)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentLengthHeader, result.length);
      if (range.partial) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.start + result.length - 1}/${session.size}',
        );
      }
      await for (final chunk in result.chunks) {
        request.response.add(chunk);
      }
    } catch (e) {
      debugPrint('[FileStreamServer] range read failed: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  _Range? _parseRange(String? header, int size) {
    if (header == null) return _Range(0, size, false);

    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final startStr = match.group(1) ?? '';
    final endStr = match.group(2) ?? '';
    if (startStr.isEmpty && endStr.isEmpty) return null;

    int start;
    int end;
    if (startStr.isEmpty) {
      final suffixLength = int.tryParse(endStr);
      if (suffixLength == null || suffixLength <= 0) return null;
      start = max(0, size - suffixLength);
      end = size - 1;
    } else {
      start = int.tryParse(startStr) ?? -1;
      end = endStr.isEmpty ? size - 1 : (int.tryParse(endStr) ?? -1);
    }
    if (start < 0 || end < 0 || start > end) return null;
    if (size > 0 && start >= size) return null;
    end = min(end, size - 1);
    return _Range(start, end - start + 1, true);
  }
}
