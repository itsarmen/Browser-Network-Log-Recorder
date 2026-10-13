/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Loopback HTTP server the Firefox extension posts captured records to.
///
///   GET    /api/ping     -> "pong"
///   GET    /api/health   -> status json
///   GET    /api/logs     -> all buffered records
///   POST   /api/logs     -> ingest a record or array of records
///   DELETE /api/logs     -> clear the buffer
class LogServer {
  LogServer({
    this.port = 8765,
    required this.onRecords,
    required this.onCleared,
  });

  final int port;
  final void Function(List<LogRecord> records) onRecords;
  final void Function() onCleared;

  HttpServer? _server;
  final List<LogRecord> history = <LogRecord>[];

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
    } catch (e) {
      // Try next few ports if the default is in use
      for (int p = port + 1; p <= port + 10; p++) {
        try {
          _server = await HttpServer.bind(InternetAddress.loopbackIPv4, p, shared: true);
          break;
        } catch (_) {
          continue;
        }
      }
      if (_server == null) {
        rethrow;
      }
    }
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (req.method == 'OPTIONS') {
        _cors(req.response);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      if (req.method == 'GET' && path == '/api/ping') {
        await _json(req.response, HttpStatus.ok, '"pong"');
        return;
      }

      if (req.method == 'GET' && path == '/api/health') {
        await _json(req.response, HttpStatus.ok,
            jsonEncode({'status': 'ok', 'port': port, 'count': history.length}));
        return;
      }

      if (req.method == 'POST' && path == '/api/logs') {
        final body = await utf8.decoder.bind(req).join();
        var received = 0;
        try {
          final decoded = jsonDecode(body);
          final list = <LogRecord>[];
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) list.add(LogRecord.fromJson(Map<String, dynamic>.from(e)));
            }
          } else if (decoded is Map) {
            list.add(LogRecord.fromJson(Map<String, dynamic>.from(decoded)));
          }
          if (list.isNotEmpty) {
            history.addAll(list);
            const max = 20000;
            if (history.length > max) {
              history.removeRange(0, history.length - max);
            }
            onRecords(list);
            received = list.length;
          }
        } catch (_) {
          // ignore malformed payloads
        }
        await _json(req.response, HttpStatus.ok, jsonEncode({'received': received}));
        return;
      }

      if (req.method == 'GET' && path == '/api/logs') {
        final json = jsonEncode(history.map((r) => r.toJson()).toList());
        await _json(req.response, HttpStatus.ok, json);
        return;
      }

      if (req.method == 'DELETE' && path == '/api/logs') {
        history.clear();
        onCleared();
        await _json(req.response, HttpStatus.ok, '{"cleared":true}');
        return;
      }

      await _json(req.response, HttpStatus.notFound, '{"error":"not found"}');
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _cors(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }

  Future<void> _json(HttpResponse res, int status, String body) async {
    _cors(res);
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    final bytes = utf8.encode(body);
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }
}
