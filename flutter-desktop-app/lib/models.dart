/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

class RequestBody {
  RequestBody({this.kind = '', this.text, this.form, this.error});

  String kind;
  String? text;
  Map<String, List<String>>? form;
  String? error;

  bool get isEmpty =>
      kind.isEmpty && text == null && form == null && error == null;

  factory RequestBody.fromJson(Map<String, dynamic> j) => RequestBody(
        kind: (j['kind'] ?? '') as String,
        text: j['text'] as String?,
        error: j['error'] as String?,
        form: (j['form'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            List<String>.from((v as List).map((e) => '$e')),
          ),
        ),
      );

  Map<String, dynamic> toJson() => {
        if (kind.isNotEmpty) 'kind': kind,
        if (text != null) 'text': text,
        if (form != null) 'form': form,
        if (error != null) 'error': error,
      };
}

class LogRecord {
  LogRecord({
    this.id = '',
    this.site = '',
    this.url = '',
    this.method = '',
    this.type = '',
    this.tabId = 0,
    this.timeStamp = 0,
    this.startedAt = '',
    this.durationMs,
    this.statusCode,
    this.statusLine,
    this.requestHeaders,
    this.responseHeaders,
    this.requestBody,
    this.responseBody,
    this.responseTruncated = false,
    this.fromCache = false,
    this.error,
  });

  String id;
  String site;
  String url;
  String method;
  String type;
  int tabId;
  double timeStamp;
  String startedAt;
  double? durationMs;
  int? statusCode;
  String? statusLine;
  Map<String, String>? requestHeaders;
  Map<String, String>? responseHeaders;
  RequestBody? requestBody;
  String? responseBody;
  bool responseTruncated;
  bool fromCache;
  String? error;

  String get methodDisplay => method.isEmpty ? '?' : method.toUpperCase();

  String get statusDisplay {
    if (statusCode != null) return '$statusCode';
    if (error != null && error!.isNotEmpty) return 'ERR';
    return '…';
  }

  bool get isSuccess => statusCode != null && statusCode! < 400;

  Uri? get uri => Uri.tryParse(url);

  String get hostDisplay {
    final u = uri;
    if (u == null) return url;
    return u.host;
  }

  String get pathDisplay {
    final u = uri;
    if (u == null) return '';
    final p = u.path + (u.hasQuery ? '?${u.query}' : '');
    return p.isEmpty ? '/' : p;
  }

  String get timeDisplay {
    final d = DateTime.tryParse(startedAt);
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}';
  }

  factory LogRecord.fromJson(Map<String, dynamic> j) => LogRecord(
        id: (j['id'] ?? '') as String,
        site: (j['site'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        method: (j['method'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        tabId: (j['tabId'] as num?)?.toInt() ?? 0,
        timeStamp: (j['timeStamp'] as num?)?.toDouble() ?? 0,
        startedAt: (j['startedAt'] ?? '') as String,
        durationMs: (j['durationMs'] as num?)?.toDouble(),
        statusCode: (j['statusCode'] as num?)?.toInt(),
        statusLine: j['statusLine'] as String?,
        requestHeaders: _toStringMap(j['requestHeaders']),
        responseHeaders: _toStringMap(j['responseHeaders']),
        requestBody: j['requestBody'] is Map
            ? RequestBody.fromJson(Map<String, dynamic>.from(j['requestBody']))
            : null,
        responseBody: j['responseBody'] as String?,
        responseTruncated: j['responseTruncated'] == true,
        fromCache: j['fromCache'] == true,
        error: j['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'site': site,
        'url': url,
        'method': method,
        'type': type,
        'tabId': tabId,
        'timeStamp': timeStamp,
        'startedAt': startedAt,
        if (durationMs != null) 'durationMs': durationMs,
        if (statusCode != null) 'statusCode': statusCode,
        if (statusLine != null) 'statusLine': statusLine,
        if (requestHeaders != null) 'requestHeaders': requestHeaders,
        if (responseHeaders != null) 'responseHeaders': responseHeaders,
        if (requestBody != null && !requestBody!.isEmpty)
          'requestBody': requestBody!.toJson(),
        if (responseBody != null) 'responseBody': responseBody,
        if (responseTruncated) 'responseTruncated': true,
        if (fromCache) 'fromCache': true,
        if (error != null) 'error': error,
      };

  static Map<String, String>? _toStringMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((k, v) => MapEntry('$k', '$v'));
  }
}

class SiteItem {
  SiteItem({required this.name, this.isAll = false, this.count = 0});

  final String name;
  final bool isAll;
  int count;

  String get display => isAll ? 'All websites' : name;
}

String prettyJson(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return text;
    }
  }
  return text;
}

String formatHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return '';
  return headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
}

String buildDetailsText(LogRecord r) {
  final sb = StringBuffer();
  sb.writeln('${r.method} ${r.url}');
  sb.writeln('─' * 48);
  if (r.site.isNotEmpty) sb.writeln('Website    : ${r.site}');
  sb.writeln('Type       : ${r.type}');
  sb.writeln('Tab        : ${r.tabId}');
  sb.writeln('Started    : ${r.startedAt}');
  if (r.durationMs != null) {
    sb.writeln('Duration   : ${r.durationMs!.toStringAsFixed(0)} ms');
  }
  if (r.fromCache) sb.writeln('Cached     : yes');
  sb.writeln('Status     : ${r.statusLine ?? r.statusCode ?? '-'}');
  if (r.error != null) sb.writeln('Error      : ${r.error}');
  sb.writeln();
  sb.writeln('── Request headers ──');
  sb.writeln(formatHeaders(r.requestHeaders).isEmpty
      ? '(none)'
      : formatHeaders(r.requestHeaders));
  if (r.requestBody != null) {
    sb.writeln();
    sb.writeln('── Request body ──');
    final body = formatBody(r.requestBody);
    sb.writeln(body.isEmpty ? '(empty)' : body);
  }
  sb.writeln();
  sb.writeln('── Response headers ──');
  sb.writeln(formatHeaders(r.responseHeaders).isEmpty
      ? '(none)'
      : formatHeaders(r.responseHeaders));
  sb.writeln();
  sb.writeln('── Response body ──');
  if (r.responseBody == null || r.responseBody!.isEmpty) {
    sb.writeln('(not captured)');
  } else {
    if (r.responseTruncated) sb.writeln('[truncated]');
    sb.writeln(prettyJson(r.responseBody!));
  }
  return sb.toString();
}

String formatBody(RequestBody? body) {
  if (body == null) return '';
  final parts = <String>[];
  if (body.kind.isNotEmpty) parts.add('kind: ${body.kind}');
  if (body.error != null && body.error!.isNotEmpty) parts.add('error: ${body.error}');
  if (body.form != null) {
    body.form!.forEach((k, v) => parts.add('$k = ${v.join(', ')}'));
  }
  if (body.text != null && body.text!.isNotEmpty) parts.add(prettyJson(body.text!));
  return parts.join('\n').trim();
}
