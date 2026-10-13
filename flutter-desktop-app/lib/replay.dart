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

class ReplayOutcome {
  ReplayOutcome({
    required this.time,
    required this.method,
    required this.url,
    required this.elapsedMs,
    required this.statusCode,
    required this.statusText,
    required this.headers,
    required this.body,
    required this.success,
  });

  final DateTime time;
  final String method;
  final String url;
  final int elapsedMs;
  final int statusCode;
  final String statusText;
  final String headers;
  final String body;
  final bool success;
}

Map<String, String> parseHeadersText(String text) {
  final result = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final name = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    if (name.isNotEmpty) result[name] = value;
  }
  return result;
}

Future<ReplayOutcome> sendReplay({
  required String method,
  required String url,
  required String headersText,
  required String bodyText,
  required bool followRedirects,
  required bool ignoreTls,
}) async {
  final client = HttpClient();
  final stopwatch = Stopwatch()..start();
  try {
    client.badCertificateCallback = (cert, host, port) => ignoreTls;
    client.connectionTimeout = const Duration(seconds: 30);

    final verb = method.trim().isEmpty ? 'GET' : method.trim().toUpperCase();
    final request = await client.openUrl(verb, Uri.parse(url.trim()));
    request.followRedirects = followRedirects;

    final headers = parseHeadersText(headersText);
    String? contentType;
    headers.forEach((name, value) {
      if (name.toLowerCase() == 'content-type') {
        contentType = value;
        return;
      }
      try {
        request.headers.set(name, value, preserveHeaderCase: true);
      } catch (_) {
        // header not allowed; skip
      }
    });

    if (bodyText.isNotEmpty || (contentType != null && contentType!.isNotEmpty)) {
      if (contentType != null && contentType!.isNotEmpty) {
        try {
          request.headers.set('content-type', contentType!, preserveHeaderCase: true);
        } catch (_) {}
      }
      request.add(utf8.encode(bodyText));
    }

    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    stopwatch.stop();

    final headerBuffer = StringBuffer();
    response.headers.forEach((name, values) {
      headerBuffer.writeln('$name: ${values.join(', ')}');
    });

    final statusText =
        'HTTP ${response.statusCode} ${response.reasonPhrase}  ·  '
        '${stopwatch.elapsedMilliseconds} ms  ·  ${text.length} bytes';

    return ReplayOutcome(
      time: DateTime.now(),
      method: verb,
      url: url.trim(),
      elapsedMs: stopwatch.elapsedMilliseconds,
      statusCode: response.statusCode,
      statusText: statusText,
      headers: headerBuffer.toString().trimRight(),
      body: prettyJson(text),
      success: true,
    );
  } finally {
    client.close(force: true);
  }
}
