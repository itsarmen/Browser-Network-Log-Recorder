/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:xml/xml.dart';

import 'models.dart';

/// XML export/import for [LogRecord]s, mirroring the JSON structure.
class LogXml {
  static String serialize(List<LogRecord> records) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element('networkLog', nest: () {
      for (final r in records) {
        builder.element('record', attributes: {
          'id': r.id,
          'site': r.site,
          'url': r.url,
          'method': r.method,
          'type': r.type,
          'tabId': '${r.tabId}',
          'startedAt': r.startedAt,
          'fromCache': '${r.fromCache}',
          if (r.durationMs != null) 'durationMs': '${r.durationMs}',
          if (r.statusCode != null) 'statusCode': '${r.statusCode}',
          if (r.statusLine != null) 'statusLine': r.statusLine!,
          if (r.error != null) 'error': r.error!,
        }, nest: () {
          _headers(builder, 'requestHeaders', r.requestHeaders);
          _body(builder, r.requestBody);
          _headers(builder, 'responseHeaders', r.responseHeaders);
        });
      }
    });
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static void _headers(
      XmlBuilder builder, String name, Map<String, String>? headers) {
    builder.element(name, nest: () {
      if (headers == null) return;
      headers.forEach((k, v) {
        builder.element('header', attributes: {'name': k, 'value': v});
      });
    });
  }

  static void _body(XmlBuilder builder, RequestBody? body) {
    builder.element(
      'requestBody',
      attributes: {
        if (body != null && body.kind.isNotEmpty) 'kind': body.kind,
      },
      nest: () {
        if (body == null) return;
        if (body.error != null) {
          builder.element('error', nest: body.error);
        }
        if (body.form != null) {
          builder.element('form', nest: () {
            body.form!.forEach((key, values) {
              builder.element('field', attributes: {'name': key}, nest: () {
                for (final v in values) {
                  builder.element('value', nest: v);
                }
              });
            });
          });
        }
        if (body.text != null) {
          builder.element('text', nest: body.text);
        }
      },
    );
  }

  static List<LogRecord> deserialize(String xml) {
    final doc = XmlDocument.parse(xml);
    final result = <LogRecord>[];
    for (final rec in doc.rootElement.findElements('record')) {
      final headers = <String, String>{};
      final resHeaders = <String, String>{};
      _readHeaders(rec, 'requestHeaders', headers);
      _readHeaders(rec, 'responseHeaders', resHeaders);
      result.add(LogRecord(
        id: rec.getAttribute('id') ?? '',
        site: rec.getAttribute('site') ?? '',
        url: rec.getAttribute('url') ?? '',
        method: rec.getAttribute('method') ?? '',
        type: rec.getAttribute('type') ?? '',
        tabId: int.tryParse(rec.getAttribute('tabId') ?? '') ?? 0,
        startedAt: rec.getAttribute('startedAt') ?? '',
        fromCache: rec.getAttribute('fromCache') == 'true',
        durationMs: double.tryParse(rec.getAttribute('durationMs') ?? ''),
        statusCode: int.tryParse(rec.getAttribute('statusCode') ?? ''),
        statusLine: rec.getAttribute('statusLine'),
        error: rec.getAttribute('error'),
        requestHeaders: headers.isEmpty ? null : headers,
        responseHeaders: resHeaders.isEmpty ? null : resHeaders,
        requestBody: _readBody(rec),
      ));
    }
    return result;
  }

  static void _readHeaders(
      XmlElement rec, String name, Map<String, String> out) {
    final containers = rec.findElements(name);
    if (containers.isEmpty) return;
    for (final h in containers.first.findElements('header')) {
      final key = h.getAttribute('name');
      if (key != null) out[key] = h.getAttribute('value') ?? '';
    }
  }

  static RequestBody? _readBody(XmlElement rec) {
    final containers = rec.findElements('requestBody');
    if (containers.isEmpty) return null;
    final el = containers.first;
    final kind = el.getAttribute('kind') ?? '';
    final textEl = el.findElements('text');
    final errorEl = el.findElements('error');
    Map<String, List<String>>? form;
    final forms = el.findElements('form');
    if (forms.isNotEmpty) {
      form = {};
      for (final field in forms.first.findElements('field')) {
        final name = field.getAttribute('name');
        if (name == null) continue;
        form[name] =
            field.findElements('value').map((v) => v.innerText).toList();
      }
    }
    final body = RequestBody(
      kind: kind,
      text: textEl.isEmpty ? null : textEl.first.innerText,
      error: errorEl.isEmpty ? null : errorEl.first.innerText,
      form: form,
    );
    return body.isEmpty ? null : body;
  }
}
