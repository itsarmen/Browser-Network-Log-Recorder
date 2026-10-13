/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// SQLite persistence for captured records (same schema as the earlier
/// WinUI viewer, so an existing logs.db keeps working).
class LogDatabase {
  LogDatabase(this.path);

  final String path;
  late final Database _db;
  PreparedStatement? _insert;

  static String defaultPath() {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    return '$base\\NetworkLogViewer\\logs.db';
  }

  void open() {
    Directory(File(path).parent.path).createSync(recursive: true);
    _db = sqlite3.open(path);
    _migrate();
  }

  void _migrate() {
    _db.execute('PRAGMA journal_mode=WAL;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS records (
        seq                INTEGER PRIMARY KEY AUTOINCREMENT,
        id                 TEXT,
        site               TEXT,
        url                TEXT,
        method             TEXT,
        type               TEXT,
        tab_id             INTEGER,
        time_stamp         REAL,
        started_at         TEXT,
        duration_ms        REAL,
        status_code        INTEGER,
        status_line        TEXT,
        from_cache         INTEGER,
        error              TEXT,
        request_headers    TEXT,
        response_headers   TEXT,
        request_body       TEXT,
        response_body      TEXT,
        response_truncated INTEGER,
        received_at        TEXT
      );
    ''');
    _addColumnIfMissing('site', 'TEXT');
    _addColumnIfMissing('response_body', 'TEXT');
    _addColumnIfMissing('response_truncated', 'INTEGER');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sites (
        name       TEXT PRIMARY KEY,
        created_at TEXT
      );
    ''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_records_site ON records(site);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_records_type ON records(type);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_records_url ON records(url);');
  }

  void _addColumnIfMissing(String column, String type) {
    final cols = _db.select('PRAGMA table_info(records);');
    final exists = cols.any((r) => '${r['name']}'.toLowerCase() == column);
    if (!exists) {
      _db.execute('ALTER TABLE records ADD COLUMN $column $type;');
    }
  }

  int count() =>
      _db.select('SELECT COUNT(*) AS c FROM records;').first['c'] as int;

  void insert(List<LogRecord> records) {
    if (records.isEmpty) return;
    final stmt = _insert ??= _db.prepare('''
      INSERT INTO records
        (id, site, url, method, type, tab_id, time_stamp, started_at, duration_ms,
         status_code, status_line, from_cache, error,
         request_headers, response_headers, request_body,
         response_body, response_truncated, received_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''');

    final received = DateTime.now().toUtc().toIso8601String();
    _db.execute('BEGIN;');
    try {
      for (final r in records) {
        stmt.execute([
          r.id,
          r.site.isEmpty ? null : r.site,
          r.url,
          r.method,
          r.type,
          r.tabId,
          r.timeStamp,
          r.startedAt,
          r.durationMs,
          r.statusCode,
          r.statusLine,
          r.fromCache ? 1 : 0,
          r.error,
          _enc(r.requestHeaders),
          _enc(r.responseHeaders),
          r.requestBody == null ? null : _enc(r.requestBody!.toJson()),
          r.responseBody,
          r.responseTruncated ? 1 : 0,
          received,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }

    _db.execute('BEGIN;');
    try {
      for (final site in records.map((r) => r.site).where((s) => s.isNotEmpty).toSet()) {
        _db.execute(
          'INSERT OR IGNORE INTO sites (name, created_at) VALUES (?, ?);',
          [site, received],
        );
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
    }
  }

  List<LogRecord> loadAll({int limit = 100000}) {
    final rows = _db.select('''
      SELECT id, site, url, method, type, tab_id, time_stamp, started_at,
             duration_ms, status_code, status_line, from_cache, error,
             request_headers, response_headers, request_body,
             response_body, response_truncated
      FROM records ORDER BY seq ASC LIMIT ?;
    ''', [limit]);

    return rows.map(_rowToRecord).toList();
  }

  LogRecord _rowToRecord(Row row) {
    return LogRecord(
      id: (row['id'] ?? '') as String,
      site: (row['site'] ?? '') as String,
      url: (row['url'] ?? '') as String,
      method: (row['method'] ?? '') as String,
      type: (row['type'] ?? '') as String,
      tabId: (row['tab_id'] as int?) ?? 0,
      timeStamp: ((row['time_stamp'] as num?) ?? 0).toDouble(),
      startedAt: (row['started_at'] ?? '') as String,
      durationMs: (row['duration_ms'] as num?)?.toDouble(),
      statusCode: row['status_code'] as int?,
      statusLine: row['status_line'] as String?,
      fromCache: (row['from_cache'] as int? ?? 0) != 0,
      error: row['error'] as String?,
      requestHeaders: _decHeaders(row['request_headers'] as String?),
      responseHeaders: _decHeaders(row['response_headers'] as String?),
      requestBody: _decBody(row['request_body'] as String?),
      responseBody: row['response_body'] as String?,
      responseTruncated: (row['response_truncated'] as int? ?? 0) != 0,
    );
  }

  List<String> getSites() {
    final rows = _db.select('''
      SELECT name FROM (
        SELECT name FROM sites
        UNION
        SELECT DISTINCT site AS name FROM records
          WHERE site IS NOT NULL AND site <> ''
      ) ORDER BY name COLLATE NOCASE;
    ''');
    return rows.map((r) => '${r['name']}').toList();
  }

  void ensureSite(String name) {
    if (name.trim().isEmpty) return;
    _db.execute(
      'INSERT OR IGNORE INTO sites (name, created_at) VALUES (?, ?);',
      [name, DateTime.now().toUtc().toIso8601String()],
    );
  }

  void renameSite(String oldName, String newName) {
    if (newName.trim().isEmpty || oldName == newName) return;
    _db.execute('UPDATE records SET site = ? WHERE site = ?;', [newName, oldName]);
    _db.execute('DELETE FROM sites WHERE name = ?;', [oldName]);
    _db.execute(
      'INSERT OR IGNORE INTO sites (name, created_at) VALUES (?, ?);',
      [newName, DateTime.now().toUtc().toIso8601String()],
    );
  }

  void deleteSite(String name) {
    _db.execute('DELETE FROM records WHERE site = ?;', [name]);
    _db.execute('DELETE FROM sites WHERE name = ?;', [name]);
  }

  void updateRequest(
    String id,
    double timeStamp,
    String method,
    String url,
    Map<String, String>? requestHeaders,
    RequestBody? requestBody,
  ) {
    _db.execute(
      '''UPDATE records SET method = ?, url = ?, request_headers = ?, request_body = ?
         WHERE id = ? AND time_stamp = ?;''',
      [
        method,
        url,
        _enc(requestHeaders),
        requestBody == null ? null : _enc(requestBody.toJson()),
        id,
        timeStamp,
      ],
    );
  }

  void clear() {
    _db.execute('DELETE FROM records;');
    _db.execute('DELETE FROM sites;');
  }

  void dispose() {
    try {
      _insert?.close();
    } catch (_) {}
    _db.close();
  }

  static String? _enc(Object? value) => value == null ? null : jsonEncode(value);

  static Map<String, String>? _decHeaders(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    return decoded.map((k, v) => MapEntry('$k', '$v'));
  }

  static RequestBody? _decBody(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    return RequestBody.fromJson(Map<String, dynamic>.from(decoded));
  }
}
