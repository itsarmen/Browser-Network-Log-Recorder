/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:network_log_viewer/capture/classification.dart';
import 'package:network_log_viewer/filter_query.dart';
import 'package:network_log_viewer/models.dart';
import 'package:network_log_viewer/settings.dart';

void main() {
  test('log record json round trip', () {
    final record = LogRecord(
      id: 'x',
      url: 'http://webbook.ge/api',
      method: 'POST',
      site: 'webbook.ge',
      statusCode: 200,
    );
    final back = LogRecord.fromJson(record.toJson());
    expect(back.url, 'http://webbook.ge/api');
    expect(back.method, 'POST');
    expect(back.statusCode, 200);
    expect(back.site, 'webbook.ge');
  });

  group('classifyRequest', () {
    test('json by content type', () {
      final r = LogRecord(
        url: 'https://a.b/data',
        type: 'xmlhttprequest',
        responseHeaders: {'content-type': 'application/json'},
      );
      expect(classifyRequest(r), RequestKind.json);
    });

    test('graphql by path', () {
      final r = LogRecord(url: 'https://a.b/graphql', method: 'POST');
      expect(classifyRequest(r), RequestKind.gql);
    });

    test('websocket by url scheme', () {
      final r = LogRecord(url: 'wss://a.b/socket');
      expect(classifyRequest(r), RequestKind.ws);
    });

    test('html main frame', () {
      final r = LogRecord(
        url: 'https://a.b/',
        type: 'main_frame',
        responseHeaders: {'content-type': 'text/html; charset=utf-8'},
      );
      expect(classifyRequest(r), RequestKind.html);
    });
  });

  group('isSkippedType', () {
    const on = SkipSettings();
    const off = SkipSettings(
      images: false,
      scripts: false,
      fonts: false,
      media: false,
    );

    test('image extension skipped when images on', () {
      final r = LogRecord(url: 'https://a.b/pic.png', type: 'other');
      expect(isSkippedType(r, on), isTrue);
      expect(isSkippedType(r, off), isFalse);
    });

    test('json never skipped by extension rules', () {
      final r = LogRecord(
        url: 'https://a.b/data.json',
        type: 'xmlhttprequest',
        responseHeaders: {'content-type': 'application/json'},
      );
      expect(isSkippedType(r, on), isFalse);
    });

    test('developer xhr type never skipped', () {
      final r = LogRecord(url: 'https://a.b/api', type: 'xmlhttprequest');
      expect(isSkippedType(r, on), isFalse);
    });
  });

  group('FilterQuery', () {
    final r = LogRecord(
      url: 'https://api.b/v2/users?id=7',
      method: 'POST',
      statusCode: 404,
      responseHeaders: {'content-type': 'application/json'},
      responseBody: '{"error":"nope"}',
    );

    test('method and status tokens', () {
      expect(FilterQuery.parse('method:POST').matches(r), isTrue);
      expect(FilterQuery.parse('method:GET').matches(r), isFalse);
      expect(FilterQuery.parse('status:404').matches(r), isTrue);
      expect(FilterQuery.parse('status:4xx').matches(r), isTrue);
      expect(FilterQuery.parse('status:>=400').matches(r), isTrue);
      expect(FilterQuery.parse('status:200').matches(r), isFalse);
    });

    test('negation and body', () {
      expect(FilterQuery.parse('-method:GET').matches(r), isTrue);
      expect(FilterQuery.parse('body:nope').matches(r), isTrue);
      expect(FilterQuery.parse('body:missing').matches(r), isFalse);
    });
  });
}
