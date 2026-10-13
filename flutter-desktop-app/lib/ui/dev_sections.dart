/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import '../models.dart';

/// Developer-first derived sections used by the popup's Request / Response /
/// Overview tabs. Everything here is derived purely from the stored record.

String? _value(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  final lower = name.toLowerCase();
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return null;
}

/// Cookie pairs parsed from the request `Cookie` header.
List<MapEntry<String, String>> requestCookies(LogRecord r) {
  final raw = _value(r.requestHeaders, 'cookie');
  if (raw == null || raw.trim().isEmpty) return const [];
  final out = <MapEntry<String, String>>[];
  for (final part in raw.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) {
      out.add(MapEntry(trimmed, ''));
    } else {
      out.add(MapEntry(trimmed.substring(0, eq).trim(),
          trimmed.substring(eq + 1).trim()));
    }
  }
  return out;
}

/// Set-Cookie name/value pairs from the response.
List<MapEntry<String, String>> responseSetCookies(LogRecord r) {
  final raw = _value(r.responseHeaders, 'set-cookie');
  if (raw == null || raw.trim().isEmpty) return const [];
  final out = <MapEntry<String, String>>[];
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq).trim();
    final rest = trimmed.substring(eq + 1).trim();
    final attrs = rest.indexOf(';');
    final value = attrs < 0 ? rest : rest.substring(0, attrs).trim();
    out.add(MapEntry(name, value));
  }
  return out;
}

String setCookieRaw(LogRecord r) => _value(r.responseHeaders, 'set-cookie') ?? '';

/// A curated set of developer-relevant headers, request then response.
const List<String> _importantNames = [
  'content-type',
  'accept',
  'authorization',
  'cookie',
  'set-cookie',
  'cache-control',
  'location',
  'origin',
  'referer',
  'user-agent',
  'access-control-allow-origin',
  'x-request-id',
  'x-csrf-token',
  'x-xsrf-token',
];

List<MapEntry<String, String>> importantHeaders(LogRecord r) {
  final out = <MapEntry<String, String>>[];
  final seen = <String>{};
  void add(String name, Map<String, String>? headers) {
    final v = _value(headers, name);
    if (v != null && seen.add(name)) out.add(MapEntry(name, v));
  }

  for (final name in _importantNames) {
    add(name, r.requestHeaders);
  }
  for (final name in _importantNames) {
    if (name == 'cookie') continue;
    add(name, r.responseHeaders);
  }
  return out;
}

String? _jwtFrom(String? header) {
  if (header == null) return null;
  final trimmed = header.trim();
  if (trimmed.toLowerCase().startsWith('bearer ')) {
    return trimmed.substring(7).trim();
  }
  final m = RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
      .firstMatch(trimmed);
  return m?.group(0);
}

String _decodeSegment(String segment) {
  var s = segment.replaceAll('-', '+').replaceAll('_', '/');
  switch (s.length % 4) {
    case 2:
      s += '==';
    case 3:
      s += '=';
  }
  return utf8.decode(base64.decode(s), allowMalformed: true);
}

/// Decodes a JWT found in `Authorization` or a cookie. Returns
/// `{header, payload}` or null.
Map<String, dynamic>? decodeJwt(LogRecord r) {
  var token = _jwtFrom(_value(r.requestHeaders, 'authorization'));
  if (token == null) {
    for (final cookie in requestCookies(r)) {
      final t = _jwtFrom(cookie.value);
      if (t != null && t.split('.').length == 3) {
        token = t;
        break;
      }
    }
  }
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final header = jsonDecode(_decodeSegment(parts[0]));
    final payload = jsonDecode(_decodeSegment(parts[1]));
    return {'header': header, 'payload': payload};
  } catch (_) {
    return null;
  }
}

String jsonPseudo(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
