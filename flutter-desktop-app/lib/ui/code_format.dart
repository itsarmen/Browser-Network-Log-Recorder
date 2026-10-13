/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import 'app_theme.dart';

/// Text-only syntax colouring for JSON bodies, header tables and raw HTTP.
/// Colours are applied to the text only, never to backgrounds.

TextSpan _plain(String text, {Color? color}) => TextSpan(
  text: text,
  style: TextStyle(color: color ?? AppColors.text),
);

final RegExp _jsonToken = RegExp(
  r'("(?:[^"\\]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\d+\.?\d*(?:[eE][+-]?\d+)?)',
);

List<TextSpan> jsonSpans(String text) {
  if (text.trim().isEmpty) {
    return [_plain('(none)', color: AppColors.secondary)];
  }
  final spans = <TextSpan>[];
  var i = 0;
  for (final m in _jsonToken.allMatches(text)) {
    if (m.start > i) spans.add(_plain(text.substring(i, m.start)));
    final str = m.group(1);
    if (str != null) {
      if (m.group(2) != null) {
        spans.add(_plain(str, color: AppColors.info));
        spans.add(_plain(m.group(2)!));
      } else {
        spans.add(_plain(str, color: AppColors.success));
      }
    } else if (m.group(3) != null) {
      spans.add(_plain(m.group(3)!, color: AppColors.purple));
    } else {
      spans.add(_plain(m.group(4)!, color: AppColors.warning));
    }
    i = m.end;
  }
  if (i < text.length) spans.add(_plain(text.substring(i)));
  return spans;
}

List<TextSpan> headerSpans(String text) {
  if (text.trim().isEmpty) {
    return [_plain('(none)', color: AppColors.secondary)];
  }
  final spans = <TextSpan>[];
  final lines = text.split('\n');
  for (var idx = 0; idx < lines.length; idx++) {
    final line = lines[idx];
    final c = line.indexOf(':');
    if (c > 0) {
      spans.add(_plain(line.substring(0, c), color: AppColors.info));
      spans.add(_plain(line.substring(c)));
    } else {
      spans.add(_plain(line));
    }
    if (idx < lines.length - 1) spans.add(_plain('\n'));
  }
  return spans;
}

List<TextSpan> plainSpans(String text) {
  if (text.trim().isEmpty) {
    return [_plain('(none)', color: AppColors.secondary)];
  }
  return [_plain(text)];
}

/// Pretty-prints XML by indenting between tags. Returns input unchanged when it
/// does not look like XML.
String prettyXml(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('<')) return text;
  try {
    var depth = 0;
    final out = StringBuffer();
    final tokens = RegExp(r'<[^>]*>|[^<]+').allMatches(trimmed);
    for (final m in tokens) {
      final token = m.group(0)!;
      final isTag = token.startsWith('<');
      final isClose = token.startsWith('</');
      final isSelf =
          token.startsWith('<?') ||
          token.startsWith('<!') ||
          token.endsWith('/>') ||
          token.startsWith('<!--');
      if (isClose && depth > 0) depth--;
      out.write('${'  ' * depth}${token.trim()}\n');
      if (isTag && !isClose && !isSelf) depth++;
    }
    return out.toString().trimRight();
  } catch (_) {
    return text;
  }
}

List<TextSpan> xmlSpans(String text) {
  if (text.trim().isEmpty) {
    return [_plain('(none)', color: AppColors.secondary)];
  }
  final spans = <TextSpan>[];
  for (final m in RegExp(r'<[^>]*>|[^<]+').allMatches(text)) {
    final token = m.group(0)!;
    if (token.startsWith('<!--')) {
      spans.add(_plain(token, color: AppColors.secondary));
    } else if (token.startsWith('<')) {
      spans.add(_plain(token, color: AppColors.info));
    } else if (token.trim().isEmpty) {
      spans.add(_plain(token));
    } else {
      spans.add(_plain(token, color: AppColors.text));
    }
  }
  return spans;
}

/// Raw HTTP exchange: first line (request/status), headers, blank line, body.
List<TextSpan> httpSpans(String text) {
  if (text.trim().isEmpty) {
    return [_plain('(none)', color: AppColors.secondary)];
  }
  final spans = <TextSpan>[];
  final lines = text.split('\n');
  var inBody = false;
  for (var idx = 0; idx < lines.length; idx++) {
    final line = lines[idx];
    if (idx == 0) {
      spans.add(
        TextSpan(
          text: line,
          style: const TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else if (!inBody) {
      if (line.trim().isEmpty) {
        inBody = true;
        spans.add(_plain(line));
      } else {
        final c = line.indexOf(':');
        if (c > 0) {
          spans.add(_plain(line.substring(0, c), color: AppColors.info));
          spans.add(_plain(line.substring(c)));
        } else {
          spans.add(_plain(line));
        }
      }
    } else {
      spans.add(_plain(line, color: AppColors.success));
    }
    if (idx < lines.length - 1) spans.add(_plain('\n'));
  }
  return spans;
}

// ---------------------------------------------------------------------------
// Raw HTTP + cURL serialisation (for the popup's Raw tab and Copy as cURL).
// ---------------------------------------------------------------------------

String bodyText(RequestBody? body) {
  if (body == null) return '';
  if (body.form != null && body.form!.isNotEmpty) {
    return body.form!.entries
        .expand(
          (e) => e.value.map(
            (v) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}',
          ),
        )
        .join('&');
  }
  return body.text ?? '';
}

String requestLine(LogRecord r) {
  final u = r.uri;
  String target = r.url;
  if (u != null) {
    final path = u.path.isEmpty ? '/' : u.path;
    target = path + (u.hasQuery ? '?${u.query}' : '');
  }
  return '${r.methodDisplay} $target HTTP/1.1';
}

String rawRequest(LogRecord r) {
  final sb = StringBuffer()..writeln(requestLine(r));
  if (r.requestHeaders != null) {
    r.requestHeaders!.forEach((k, v) {
      sb.writeln('$k: $v');
    });
  }
  sb.writeln();
  final body = bodyText(r.requestBody);
  if (body.isNotEmpty) sb.write(body);
  return sb.toString().trimRight();
}

String rawResponse(LogRecord r) {
  final line = r.statusLine?.isNotEmpty == true
      ? r.statusLine!
      : (r.statusCode != null ? 'HTTP/1.1 ${r.statusCode}' : 'HTTP/1.1');
  final sb = StringBuffer()..writeln(line);
  if (r.responseHeaders != null) {
    r.responseHeaders!.forEach((k, v) {
      sb.writeln('$k: $v');
    });
  }
  sb.writeln();
  if (r.responseTruncated) sb.writeln('[truncated]');
  if (r.responseBody != null && r.responseBody!.isNotEmpty) {
    sb.write(r.responseBody);
  }
  return sb.toString().trimRight();
}

String rawRequestUntouched(LogRecord r) {
  return rawRequest(r);
}

String rawResponseUntouched(LogRecord r) {
  return rawResponse(r);
}

String rawObjectJson(LogRecord r) {
  try {
    return const JsonEncoder.withIndent('  ').convert(r.toJson());
  } catch (_) {
    return '{}';
  }
}
