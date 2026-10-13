/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import '../models.dart';
import '../settings.dart';
import 'ignored_extensions.dart';

/// Short, developer-first classification used by the table's Type column and
/// the type filter tabs.
enum RequestKind { json, xml, gql, ws, sse, form, html, css, xhr, other }

String kindLabel(RequestKind kind) => switch (kind) {
      RequestKind.json => 'json',
      RequestKind.xml => 'xml',
      RequestKind.gql => 'gql',
      RequestKind.ws => 'ws',
      RequestKind.sse => 'sse',
      RequestKind.form => 'form',
      RequestKind.html => 'html',
      RequestKind.css => 'css',
      RequestKind.xhr => 'xhr',
      RequestKind.other => 'other',
    };

/// Slow-request threshold in ms (one constant, per spec).
const int kSlowThresholdMs = 1000;
const int kVerySlowThresholdMs = 3000;

enum SkipGroup { image, script, font, media }

// ---------------------------------------------------------------------------
// Header / body helpers
// ---------------------------------------------------------------------------

String? _header(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == name) return e.value;
  }
  return null;
}

String contentTypeOf(LogRecord r) =>
    _header(r.responseHeaders, 'content-type') ??
    _header(r.requestHeaders, 'content-type') ??
    '';

String requestContentTypeOf(LogRecord r) =>
    _header(r.requestHeaders, 'content-type') ?? '';

String requestBodyText(RequestBody? body) {
  if (body == null) return '';
  if (body.form != null && body.form!.isNotEmpty) {
    return body.form!.entries
        .expand((e) => e.value.map(
            (v) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}'))
        .join('&');
  }
  return body.text ?? '';
}

bool _looksJson(String text) {
  final t = text.trimLeft();
  if (!(t.startsWith('{') || t.startsWith('['))) return false;
  try {
    jsonDecode(text);
    return true;
  } catch (_) {
    return false;
  }
}

/// Best-effort transferred size (body bytes only; headers are not stored).
int? transferredBytes(LogRecord r) {
  final body = r.responseBody;
  if (body != null) return utf8.encode(body).length;
  final req = requestBodyText(r.requestBody);
  if (req.isNotEmpty) return utf8.encode(req).length;
  return null;
}

bool isError(LogRecord r) =>
    (r.statusCode != null && r.statusCode! >= 400) ||
    (r.statusCode == null && r.error != null && r.error!.isNotEmpty) ||
    (r.statusCode != null && r.statusCode == 0);

bool isRedirect(LogRecord r) =>
    r.statusCode != null && r.statusCode! >= 300 && r.statusCode! < 400;

bool isSlow(LogRecord r) =>
    r.durationMs != null && r.durationMs! >= kSlowThresholdMs;

bool isVerySlow(LogRecord r) =>
    r.durationMs != null && r.durationMs! >= kVerySlowThresholdMs;

bool isPreflight(LogRecord r) => r.method.toUpperCase() == 'OPTIONS';

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/// Pure helper: classifies a stored request by kind. Order follows the spec:
/// recorded resource type, then Content-Type, then the body itself.
RequestKind classifyRequest(LogRecord r) {
  final type = r.type.toLowerCase();
  final ct = contentTypeOf(r).toLowerCase();
  final requestCt = requestContentTypeOf(r).toLowerCase();
  final uri = r.uri;
  final path = uri?.path.toLowerCase() ?? '';

  // GraphQL (URL path or JSON request body with query/operationName).
  if (path.contains('/graphql')) return RequestKind.gql;
  final reqBody = requestBodyText(r.requestBody);
  if (reqBody.isNotEmpty && _looksJson(reqBody)) {
    try {
      final decoded = jsonDecode(reqBody);
      if (decoded is Map &&
          (decoded.containsKey('query') || decoded.containsKey('operationName'))) {
        return RequestKind.gql;
      }
    } catch (_) {}
  }

  // WebSocket.
  final url = r.url.toLowerCase();
  if (url.startsWith('ws://') ||
      url.startsWith('wss://') ||
      type == 'websocket') {
    return RequestKind.ws;
  }

  // Server-sent events.
  if (ct.contains('text/event-stream')) return RequestKind.sse;

  // JSON / XML / HTML / CSS by content type (most specific first).
  if (ct.contains('json')) return RequestKind.json;
  if (ct.contains('xml') && !ct.contains('svg')) return RequestKind.xml;
  if (ct.contains('html')) return RequestKind.html;
  if (ct.contains('css')) return RequestKind.css;

  // Form request bodies.
  if (requestCt.contains('x-www-form-urlencoded') ||
      requestCt.contains('multipart/form-data')) {
    return RequestKind.form;
  }

  // Body sniffing.
  final respBody = r.responseBody;
  if (respBody != null && respBody.trimLeft().isNotEmpty) {
    final t = respBody.trimLeft();
    if (t.startsWith('<?xml')) return RequestKind.xml;
    if (t.startsWith('{') || t.startsWith('[')) {
      if (_looksJson(respBody)) return RequestKind.json;
    }
  }

  // Recorded resource type.
  if (type == 'xmlhttprequest') return RequestKind.xhr;
  if (type == 'stylesheet') return RequestKind.css;
  if (type == 'main_frame' || type == 'sub_frame') return RequestKind.html;

  return RequestKind.other;
}

String kindDisplay(LogRecord r) => kindLabel(classifyRequest(r));

/// GraphQL operation name (or the first word of the query).
String? graphqlOperation(LogRecord r) {
  final body = requestBodyText(r.requestBody);
  if (body.isEmpty || !_looksJson(body)) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final name = decoded['operationName'];
    if (name is String && name.isNotEmpty) return name;
    final query = decoded['query'];
    if (query is String) {
      final m = RegExp(r'\b(query|mutation|subscription)\s+([A-Za-z_]\w*)')
          .firstMatch(query);
      if (m != null) return m.group(2);
    }
  } catch (_) {}
  return null;
}

String? graphqlType(LogRecord r) {
  final body = requestBodyText(r.requestBody);
  if (body.isEmpty || !_looksJson(body)) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final query = decoded['query'];
      if (query is String) {
        final m = RegExp(r'\b(query|mutation|subscription)\b').firstMatch(query);
        if (m != null) return m.group(1);
      }
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Skip filter (Part 2)
// ---------------------------------------------------------------------------

SkipGroup? _typeGroup(String type) => switch (type) {
      'image' || 'imageset' => SkipGroup.image,
      'script' => SkipGroup.script,
      'font' => SkipGroup.font,
      'media' => SkipGroup.media,
      _ => null,
    };

SkipGroup? _contentTypeGroup(String ct) {
  if (ct.isEmpty) return null;
  if (ct.startsWith('image/')) return SkipGroup.image;
  if (ct.contains('javascript') || ct.contains('ecmascript')) {
    return SkipGroup.script;
  }
  if (ct.startsWith('font/') ||
      ct.startsWith('application/font-') ||
      ct.contains('vnd.ms-fontobject')) {
    return SkipGroup.font;
  }
  if (ct.startsWith('video/') ||
      ct.startsWith('audio/') ||
      ct.contains('vnd.apple.mpegurl') ||
      ct.contains('dash+xml')) {
    return SkipGroup.media;
  }
  return null;
}

SkipGroup? _extGroup(String ext, String contentType) {
  if (skippedImageExtensions.contains(ext)) return SkipGroup.image;
  if (skippedScriptExtensions.contains(ext)) return SkipGroup.script;
  if (skippedFontExtensions.contains(ext)) return SkipGroup.font;
  if (skippedAudioExtensions.contains(ext) ||
      skippedVideoExtensions.contains(ext)) {
    return SkipGroup.media;
  }
  if (ext == 'ts' && contentType.contains('video/mp2t')) return SkipGroup.media;
  return null;
}

bool _enabled(SkipGroup group, SkipSettings s) => switch (group) {
      SkipGroup.image => s.images,
      SkipGroup.script => s.scripts,
      SkipGroup.font => s.fonts,
      SkipGroup.media => s.media,
    };

/// Types that are developer content and must never be skipped by extension
/// alone (their response could be JSON/XML/HTML regardless of the URL suffix).
/// Everything else (including `other`) still falls back to the URL extension.
const Set<String> _developerTypes = {
  'xmlhttprequest',
  'fetch',
  'websocket',
};

/// Pure, testable skip filter. Called where requests are accepted and on read.
bool isSkippedType(LogRecord r, SkipSettings s) {
  final type = r.type.toLowerCase();
  final ct = contentTypeOf(r).toLowerCase();

  var group = _typeGroup(type) ?? _contentTypeGroup(ct);
  group ??= _contentTypeGroup(requestContentTypeOf(r).toLowerCase());
  if (group != null) return _enabled(group, s);

  // Extension fallback, only when neither the recorded type nor the
  // content type identified a skip group.
  if (_developerTypes.contains(type)) return false;
  final ext = urlExtension(r.url);
  if (ext == null) return false;
  if (s.downloads && skippedDownloadExtensions.contains(ext)) return true;
  final eg = _extGroup(ext, ct);
  return eg != null && _enabled(eg, s);
}
