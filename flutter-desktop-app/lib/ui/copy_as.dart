/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import '../capture/classification.dart';
import '../models.dart';

/// Pure string builders for "Copy as …". No networking, no side effects.

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _jsQuote(String value) =>
    "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

String _pyQuote(String value) => _jsQuote(value);

String curlCommand(LogRecord r) {
  final sb = StringBuffer('curl -X ${r.methodDisplay} ');
  sb.write(_shellQuote(r.url));
  r.requestHeaders?.forEach((k, v) {
    sb.write(' \\\n  -H ${_shellQuote('$k: $v')}');
  });
  final body = requestBodyText(r.requestBody);
  if (body.isNotEmpty) {
    sb.write(' \\\n  --data-raw ${_shellQuote(body)}');
  }
  return sb.toString();
}

/// HTTPie needs the method wrapped in single quotes for verbs with token costs.
String httpieCommand(LogRecord r) {
  final sb = StringBuffer("http '${r.methodDisplay}' ${_shellQuote(r.url)}");
  r.requestHeaders?.forEach((k, v) {
    sb.write(' \\\n  ${_shellQuote('$k: $v')}');
  });
  final body = requestBodyText(r.requestBody);
  if (body.isNotEmpty) {
    sb.write(' \\\n  ${_shellQuote(body)}');
  }
  return sb.toString();
}

String fetchCommand(LogRecord r) {
  final sb = StringBuffer('fetch(');
  sb.write(_jsQuote(r.url));
  sb.writeln(', {');
  sb.writeln('  method: ${_jsQuote(r.methodDisplay)},');
  final headers = r.requestHeaders;
  if (headers != null && headers.isNotEmpty) {
    sb.writeln('  headers: {');
    headers.forEach((k, v) {
      sb.writeln('    ${_jsQuote(k)}: ${_jsQuote(v)},');
    });
    sb.writeln('  },');
  }
  final body = requestBodyText(r.requestBody);
  if (body.isNotEmpty) {
    sb.writeln('  body: ${_jsQuote(body)},');
  }
  sb.write('})');
  return sb.toString();
}

String pythonCommand(LogRecord r) {
  final sb = StringBuffer('import requests\n\n');
  final headers = r.requestHeaders;
  if (headers != null && headers.isNotEmpty) {
    sb.writeln('headers = {');
    headers.forEach((k, v) {
      sb.writeln('    ${_pyQuote(k)}: ${_pyQuote(v)},');
    });
    sb.writeln('}');
    sb.writeln();
  }
  final body = requestBodyText(r.requestBody);
  if (body.isNotEmpty) {
    sb.writeln('data = ${_pyQuote(body)}');
    sb.writeln();
  }
  sb.write('response = requests.${r.methodDisplay.toLowerCase()}(');
  sb.write('\n    ${_pyQuote(r.url)},');
  if (headers != null && headers.isNotEmpty) sb.write('\n    headers=headers,');
  if (body.isNotEmpty) sb.write('\n    data=data,');
  sb.write('\n)');
  return sb.toString();
}

enum CopyAsKind { curl, fetch, python, httpie }

String copyAs(CopyAsKind kind, LogRecord r) => switch (kind) {
  CopyAsKind.curl => curlCommand(r),
  CopyAsKind.fetch => fetchCommand(r),
  CopyAsKind.python => pythonCommand(r),
  CopyAsKind.httpie => httpieCommand(r),
};

String copyAsLabel(CopyAsKind kind) => switch (kind) {
  CopyAsKind.curl => 'cURL',
  CopyAsKind.fetch => 'fetch (JavaScript)',
  CopyAsKind.python => 'Python requests',
  CopyAsKind.httpie => 'HTTPie',
};

/// Pretty JSON when the response is JSON, otherwise the raw body.
String prettyResponseIfJson(LogRecord r) {
  final body = r.responseBody ?? '';
  if (body.isEmpty) return '';
  if (classifyRequest(r) == RequestKind.json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
    } catch (_) {
      return body;
    }
  }
  return body;
}
