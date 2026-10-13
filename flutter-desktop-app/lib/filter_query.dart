/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'capture/classification.dart';
import 'models.dart';

/// One parsed filter term. Invalid/unknown tokens fall back to plain text so
/// the filter never throws.
class _Term {
  _Term({
    required this.negate,
    required this.field,
    required this.op,
    required this.value,
  });

  final bool negate;
  final String field; // method, status, domain, type, header, body, url, text
  final String op; // '', '=', '>=', '<=', '>', '<'
  final String value;

  bool matches(LogRecord r) {
    final result = _eval(r);
    return negate ? !result : result;
  }

  bool _eval(LogRecord r) {
    final v = value.toLowerCase();
    switch (field) {
      case 'method':
        return r.method.toLowerCase() == v;
      case 'status':
        return _statusMatch(r, v);
      case 'domain':
        return r.hostDisplay.toLowerCase().contains(v);
      case 'type':
        return kindLabel(classifyRequest(r)) == v ||
            r.type.toLowerCase().contains(v);
      case 'header':
        return _headerMatch(r, v);
      case 'body':
        return _bodyMatch(r, v);
      case 'url':
        return r.url.toLowerCase().contains(v);
      default:
        return _textMatch(r, v);
    }
  }

  bool _statusMatch(LogRecord r, String v) {
    final code = r.statusCode;
    if (RegExp(r'^\dxx$').hasMatch(v)) {
      final base = int.parse(v[0]) * 100;
      return code != null && code >= base && code < base + 100;
    }
    final n = int.tryParse(v);
    if (n == null) return false;
    if (code == null) return false;
    switch (op) {
      case '>=':
        return code >= n;
      case '<=':
        return code <= n;
      case '>':
        return code > n;
      case '<':
        return code < n;
      default:
        return code == n;
    }
  }

  bool _headerMatch(LogRecord r, String v) {
    bool check(Map<String, String>? headers) {
      if (headers == null) return false;
      for (final e in headers.entries) {
        if (e.key.toLowerCase().contains(v) ||
            e.value.toLowerCase().contains(v)) {
          return true;
        }
      }
      return false;
    }

    return check(r.requestHeaders) || check(r.responseHeaders);
  }

  bool _bodyMatch(LogRecord r, String v) {
    final req = requestBodyText(r.requestBody).toLowerCase();
    final res = (r.responseBody ?? '').toLowerCase();
    return req.contains(v) || res.contains(v);
  }

  bool _textMatch(LogRecord r, String v) {
    return r.method.toLowerCase().contains(v) ||
        r.url.toLowerCase().contains(v) ||
        r.type.toLowerCase().contains(v) ||
        (r.statusCode?.toString().contains(v) ?? false) ||
        (r.statusLine?.toLowerCase().contains(v) ?? false) ||
        r.site.toLowerCase().contains(v) ||
        r.hostDisplay.toLowerCase().contains(v) ||
        _headerMatch(r, v) ||
        _bodyMatch(r, v);
  }
}

class FilterQuery {
  FilterQuery._(this._terms);

  final List<_Term> _terms;

  bool get isEmpty => _terms.isEmpty;

  static const _fields = {
    'method',
    'status',
    'domain',
    'type',
    'header',
    'body',
    'url',
  };

  static FilterQuery parse(String input) {
    final terms = <_Term>[];
    for (final raw in _tokenize(input)) {
      if (raw.isEmpty) continue;
      var token = raw;
      var negate = false;
      if (token.startsWith('-') && token.length > 1) {
        negate = true;
        token = token.substring(1);
      }
      final colon = token.indexOf(':');
      if (colon > 0) {
        final field = token.substring(0, colon).toLowerCase();
        if (_fields.contains(field)) {
          var value = token.substring(colon + 1);
          var op = '';
          if (field == 'status') {
            for (final candidate in ['>=', '<=', '>', '<', '=']) {
              if (value.startsWith(candidate)) {
                op = candidate;
                value = value.substring(candidate.length);
                break;
              }
            }
          }
          if (value.isNotEmpty) {
            terms.add(_Term(
              negate: negate,
              field: field,
              op: op,
              value: value,
            ));
            continue;
          }
        }
      }
      terms.add(_Term(negate: negate, field: 'text', op: '', value: token));
    }
    return FilterQuery._(terms);
  }

  bool matches(LogRecord r) => _terms.every((t) => t.matches(r));

  /// Splits on whitespace, keeping quoted (single/double) segments together.
  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buffer.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}

const String kFilterHelp = '''
Filter tokens (space = AND, - = NOT):
method:POST        status:404   status:4xx   status:>=400
domain:api         type:json     header:authorization
body:userId        url:/v2/      -domain:analytics
"quoted value"     plain text matches URL, headers and bodies''';
