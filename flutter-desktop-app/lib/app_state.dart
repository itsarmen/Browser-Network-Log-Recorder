/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture/classification.dart';
import 'filter_query.dart';
import 'log_database.dart';
import 'log_server.dart';
import 'models.dart';
import 'settings.dart';

const String kAutoSite = '(auto by domain)';
const String kAllTypes = 'All types';

/// Sortable columns of the network table.
enum LogColumn { status, method, domain, file, type, size, time, duration }

/// The final type-filter tabs (Parts 2 & 3). `Errors` and `Slow` are special.
const List<String> kBaseTypeTabs = [
  'All',
  'JSON',
  'XML',
  'XHR',
  'GraphQL',
  'WS',
  'HTML',
  'CSS',
  'Other',
  'Errors',
  'Slow',
];

class AppState extends ChangeNotifier {
  AppState(this.db, this.settingsStore) {
    settings = settingsStore.load();
    server = LogServer(onRecords: _onRecords, onCleared: _onServerCleared);
  }

  final LogDatabase db;
  final SettingsStore settingsStore;
  late final LogServer server;
  late AppSettings settings;

  SkipSettings get skip => settings.skip;

  final List<LogRecord> all = <LogRecord>[];
  final List<LogRecord> pending = <LogRecord>[];
  final Set<String> _keys = <String>{};

  final List<SiteItem> sites = <SiteItem>[SiteItem(name: '', isAll: true)];
  final Map<String, SiteItem> _siteMap = <String, SiteItem>{};

  /// Records after the skip filter (the list the UI and counts use).
  List<LogRecord> _displayAll = <LogRecord>[];
  List<LogRecord> get stored => _displayAll;

  /// Requests ignored during this session (for the footer "N skipped").
  int skippedSession = 0;

  String activeSite = '';
  String? viewSite;
  String logSearch = '';
  String siteSearch = '';
  String typeTab = 'All';
  static const List<String> methodOptions = [
    'All',
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];
  String methodFilter = 'All';
  LogColumn sortColumn = LogColumn.time;
  bool sortAscending = false;
  int selectedIndex = -1;
  bool live = true;

  static const List<int> pageSizeOptions = [25, 50, 100, 200];
  int pageSize = 50;
  int pageIndex = 0;

  bool serverRunning = false;
  String status = 'Server stopped';

  Timer? _flushTimer;

  SiteItem get allItem => sites.first;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  Future<void> init() async {
    try {
      for (final record in db.loadAll()) {
        _addCore(record);
      }
    } catch (e) {
      status = 'Could not load history: $e';
    }
    _rebuildDisplay();
    await startServer();
    notifyListeners();
  }

  Future<void> startServer() async {
    try {
      await server.start();
      serverRunning = true;
      status = 'Listening on http://127.0.0.1:${server.port}';
    } catch (e) {
      serverRunning = false;
      status = 'Could not start server: $e';
    }
    notifyListeners();
  }

  Future<void> stopServer() async {
    await server.stop();
    serverRunning = false;
    status = 'Server stopped';
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Ingest (skip filter applied here, the single accept path)
  // ------------------------------------------------------------------

  void _onRecords(List<LogRecord> records) {
    final kept = <LogRecord>[];
    for (final record in records) {
      if (isSkippedType(record, skip)) {
        skippedSession++;
        continue;
      }
      record.site = _resolveSite(record);
      kept.add(record);
    }
    if (kept.isEmpty) {
      notifyListeners();
      return;
    }
    try {
      db.insert(kept);
    } catch (e) {
      status = 'Save failed: $e';
    }
    pending.addAll(kept);
    _scheduleFlush();
  }

  void _onServerCleared() {
    clearAll(skipServerNotify: true);
  }

  void _scheduleFlush() {
    if (!live) {
      notifyListeners();
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), flushPending);
  }

  void flushPending() {
    _flushTimer?.cancel();
    if (pending.isEmpty) return;

    final added = <LogRecord>[];
    for (final record in pending) {
      if (_addCore(record)) added.add(record);
    }
    pending.clear();

    if (added.isNotEmpty) {
      _rebuildDisplay();
      // Live follow: new arrivals show on page 1. Paused browsing keeps
      // its page (pending count is shown on the refresh button instead).
      if (live) pageIndex = 0;
    } else {
      notifyListeners();
    }
  }

  bool _addCore(LogRecord record) {
    final key = '${record.id}|${record.timeStamp}';
    if (!_keys.add(key)) return false;
    all.add(record);
    return true;
  }

  String _resolveSite(LogRecord record) {
    if (record.site.isNotEmpty) return record.site;
    if (activeSite.isNotEmpty) return activeSite;
    return _domain(record.url);
  }

  static String _domain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '(unknown)';
    var host = uri.host;
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  // ------------------------------------------------------------------
  // Display set (skip filter on read) + site counts
  // ------------------------------------------------------------------

  void _rebuildDisplay() {
    _displayAll = all
        .where((r) => !isSkippedType(r, skip))
        .where((r) => !(skip.hidePreflight && isPreflight(r)))
        .toList();
    _rebuildSites();
  }

  void _rebuildSites() {
    sites
      ..clear()
      ..add(SiteItem(name: '', isAll: true));
    _siteMap.clear();
    final names = _displayAll
        .map((r) => r.site)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      _ensureSite(name);
    }
    _recountSites();
  }

  SiteItem _ensureSite(String name) {
    if (name.isEmpty) return allItem;
    final existing = _siteMap[name];
    if (existing != null) return existing;
    final item = SiteItem(name: name);
    _siteMap[name] = item;
    final index = sites.indexWhere(
      (s) => !s.isAll && s.name.toLowerCase().compareTo(name.toLowerCase()) > 0,
    );
    if (index < 0) {
      sites.add(item);
    } else {
      sites.insert(index, item);
    }
    return item;
  }

  void _recountSites() {
    allItem.count = _displayAll.length;
    for (final item in _siteMap.values) {
      item.count = 0;
    }
    for (final record in _displayAll) {
      final item = _siteMap[record.site];
      if (item != null) item.count++;
    }
  }

  // ------------------------------------------------------------------
  // Settings
  // ------------------------------------------------------------------

  void setSkip(SkipSettings value) {
    settings.skip = value;
    settingsStore.save(settings);
    _rebuildDisplay();
    if (!_tabAvailable(typeTab)) typeTab = 'All';
    _clampSelection();
    notifyListeners();
  }

  void toggleSkipImages() => setSkip(skip.copyWith(images: !skip.images));
  void toggleSkipScripts() => setSkip(skip.copyWith(scripts: !skip.scripts));
  void toggleSkipFonts() => setSkip(skip.copyWith(fonts: !skip.fonts));
  void toggleSkipMedia() => setSkip(skip.copyWith(media: !skip.media));
  void toggleSkipDownloads() =>
      setSkip(skip.copyWith(downloads: !skip.downloads));
  void toggleHidePreflight() =>
      setSkip(skip.copyWith(hidePreflight: !skip.hidePreflight));

  // ------------------------------------------------------------------
  // Sites
  // ------------------------------------------------------------------

  void selectSite(SiteItem? item) {
    viewSite = (item == null || item.isAll) ? null : item.name;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setActiveSite(String value) {
    activeSite = (value.isEmpty || value == kAutoSite) ? '' : value;
    notifyListeners();
  }

  void addSite(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    db.ensureSite(trimmed);
    _ensureSite(trimmed);
    _recountSites();
    activeSite = trimmed;
    viewSite = trimmed;
    pageIndex = 0;
    notifyListeners();
  }

  void renameSite(String oldName, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return;
    for (final record in all) {
      if (record.site == oldName) record.site = trimmed;
    }
    db.renameSite(oldName, trimmed);
    if (activeSite == oldName) activeSite = trimmed;
    if (viewSite == oldName) viewSite = trimmed;
    _rebuildDisplay();
    pageIndex = 0;
    notifyListeners();
  }

  void deleteSite(String name) {
    db.deleteSite(name);
    all.removeWhere((r) => r.site == name);
    _keys
      ..clear()
      ..addAll(all.map((r) => '${r.id}|${r.timeStamp}'));
    if (activeSite == name) activeSite = '';
    if (viewSite == name) viewSite = null;
    _rebuildDisplay();
    pageIndex = 0;
    _pruneChecked();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Refresh / clear / import
  // ------------------------------------------------------------------

  int importRecords(List<LogRecord> records) {
    var added = 0;
    final kept = <LogRecord>[];
    for (final record in records) {
      if (isSkippedType(record, skip)) continue;
      record.site = _resolveSite(record);
      kept.add(record);
      if (_addCore(record)) added++;
    }
    try {
      db.insert(kept);
    } catch (_) {}
    _rebuildDisplay();
    pageIndex = 0;
    notifyListeners();
    return added;
  }

  void saveRecordEdits(
    LogRecord record,
    String method,
    String url,
    Map<String, String>? headers,
    RequestBody? body,
  ) {
    record.method = method;
    record.url = url;
    record.requestHeaders = headers;
    record.requestBody = body;
    db.updateRequest(record.id, record.timeStamp, method, url, headers, body);
    _rebuildDisplay();
    notifyListeners();
  }

  void refresh() {
    flushPending();
    try {
      for (final record in db.loadAll()) {
        _addCore(record);
      }
    } catch (_) {}
    _rebuildDisplay();
    notifyListeners();
  }

  void clearAll({bool skipServerNotify = false}) {
    db.clear();
    all.clear();
    pending.clear();
    _keys.clear();
    checkedIds.clear();
    skippedSession = 0;
    viewSite = null;
    activeSite = '';
    selectedIndex = -1;
    pageIndex = 0;
    _rebuildDisplay();
    server.history.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Filters, sort, selection
  // ------------------------------------------------------------------

  void setLive(bool value) {
    live = value;
    if (value) flushPending();
    notifyListeners();
  }

  void setLogSearch(String value) {
    logSearch = value;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setSiteSearch(String value) {
    siteSearch = value;
    notifyListeners();
  }

  void setTypeTab(String value) {
    typeTab = value;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setMethodFilter(String value) {
    methodFilter = value;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setSortColumn(LogColumn column) {
    if (sortColumn == column) {
      sortAscending = !sortAscending;
    } else {
      sortColumn = column;
      sortAscending = column == LogColumn.method || column == LogColumn.domain ||
          column == LogColumn.file || column == LogColumn.type;
    }
    notifyListeners();
  }

  void selectIndex(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void moveSelection(int delta) {
    final list = visible;
    if (list.isEmpty) return;
    var index = selectedIndex + delta;
    if (index < 0) index = 0;
    if (index >= list.length) index = list.length - 1;
    selectedIndex = index;
    notifyListeners();
  }

  LogRecord? get selectedRecord {
    final list = visible;
    if (selectedIndex < 0 || selectedIndex >= list.length) return null;
    return list[selectedIndex];
  }

  void _selectFirst() {
    selectedIndex = visible.isEmpty ? -1 : 0;
  }

  void _clampSelection() {
    final count = visible.length;
    if (selectedIndex >= count) selectedIndex = count - 1;
  }

  /// Type tabs including un-skipped groups (Part 2).
  List<String> get typeTabs {
    final tabs = <String>[...kBaseTypeTabs];
    if (!skip.images) tabs.insert(tabs.length - 2, 'Images');
    if (!skip.scripts) tabs.insert(tabs.length - 2, 'JS');
    if (!skip.fonts) tabs.insert(tabs.length - 2, 'Fonts');
    if (!skip.media) tabs.insert(tabs.length - 2, 'Media');
    return tabs;
  }

  bool _tabAvailable(String tab) => typeTabs.contains(tab);

  // ------------------------------------------------------------------
  // Derived views
  // ------------------------------------------------------------------

  List<SiteItem> get sitesView {
    final query = siteSearch.trim().toLowerCase();
    if (query.isEmpty) return sites;
    return sites
        .where((s) => s.isAll || s.name.toLowerCase().contains(query))
        .toList();
  }

  List<LogRecord> get visible {
    Iterable<LogRecord> query = _displayAll;
    if (viewSite != null) {
      query = query.where((r) => r.site == viewSite);
    }
    query = query.where((r) => _matchesTab(r));
    if (methodFilter != 'All') {
      final method = methodFilter;
      query = query.where((r) => r.method.toUpperCase() == method);
    }
    final fq = FilterQuery.parse(logSearch);
    if (!fq.isEmpty) {
      query = query.where(fq.matches);
    }
    final list = query.toList();
    list.sort(_compare);
    return list;
  }

  // ------------------------------------------------------------------
  // Pagination (selection indices stay global — position inside [visible])
  // ------------------------------------------------------------------

  int get pageCount {
    final total = visible.length;
    if (total == 0) return 1;
    return ((total - 1) ~/ pageSize) + 1;
  }

  /// Page clamped into range, so a shrunk list never strands the pager.
  int get _clampedPage {
    final total = visible.length;
    if (total == 0) return 0;
    return pageIndex.clamp(0, ((total - 1) ~/ pageSize));
  }

  int get pageStart => _clampedPage * pageSize;

  List<LogRecord> get pageItems {
    final list = visible;
    if (list.isEmpty) return list;
    final start = _clampedPage * pageSize;
    final end = (start + pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  String get pageLabel {
    final total = visible.length;
    if (total == 0) return 'Page 1 of 1';
    return 'Page ${_clampedPage + 1} of $pageCount';
  }

  String get pageRangeLabel {
    final total = visible.length;
    if (total == 0) return '0 of 0';
    final start = pageStart + 1;
    final end = (pageStart + pageSize).clamp(0, total);
    return '$start–$end of $total';
  }

  void setPage(int index) {
    pageIndex = index.clamp(0, pageCount - 1);
    notifyListeners();
  }

  void setPageSize(int size) {
    pageSize = size;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Checkbox multi-select (id-based, survives paging and filtering)
  // ------------------------------------------------------------------

  static String recordKey(LogRecord r) => '${r.id}|${r.timeStamp}';

  final Set<String> checkedIds = <String>{};

  bool isChecked(LogRecord r) => checkedIds.contains(recordKey(r));

  void toggleChecked(LogRecord r) {
    final key = recordKey(r);
    if (!checkedIds.remove(key)) checkedIds.add(key);
    notifyListeners();
  }

  void setPageChecked(bool value) {
    for (final r in pageItems) {
      if (value) {
        checkedIds.add(recordKey(r));
      } else {
        checkedIds.remove(recordKey(r));
      }
    }
    notifyListeners();
  }

  bool get pageAllChecked =>
      pageItems.isNotEmpty && pageItems.every(isChecked);

  bool get pageAnyChecked => pageItems.any(isChecked);

  void clearChecked() {
    if (checkedIds.isEmpty) return;
    checkedIds.clear();
    notifyListeners();
  }

  List<LogRecord> get checkedRecords =>
      visible.where(isChecked).toList();

  void _pruneChecked() {
    checkedIds.retainWhere((key) => _keys.contains(key));
  }

  bool _matchesTab(LogRecord r) {
    switch (typeTab) {
      case 'All':
        return true;
      case 'Errors':
        return isError(r);
      case 'Slow':
        return isSlow(r);
      case 'JSON':
        return classifyRequest(r) == RequestKind.json;
      case 'XML':
        return classifyRequest(r) == RequestKind.xml;
      case 'XHR':
        return classifyRequest(r) == RequestKind.xhr;
      case 'GraphQL':
        return classifyRequest(r) == RequestKind.gql;
      case 'WS':
        return classifyRequest(r) == RequestKind.ws;
      case 'HTML':
        return classifyRequest(r) == RequestKind.html;
      case 'CSS':
        return classifyRequest(r) == RequestKind.css;
      case 'Other':
        return classifyRequest(r) == RequestKind.other;
      case 'Images':
        return const {'image', 'imageset'}.contains(r.type.toLowerCase());
      case 'JS':
        return r.type.toLowerCase() == 'script';
      case 'Fonts':
        return r.type.toLowerCase() == 'font';
      case 'Media':
        return r.type.toLowerCase() == 'media';
      default:
        return true;
    }
  }

  int _compare(LogRecord a, LogRecord b) {
    int c;
    switch (sortColumn) {
      case LogColumn.status:
        c = (a.statusCode ?? 0).compareTo(b.statusCode ?? 0);
      case LogColumn.method:
        c = a.method.toLowerCase().compareTo(b.method.toLowerCase());
      case LogColumn.domain:
        c = a.hostDisplay.toLowerCase().compareTo(b.hostDisplay.toLowerCase());
      case LogColumn.file:
        c = a.pathDisplay.toLowerCase().compareTo(b.pathDisplay.toLowerCase());
      case LogColumn.type:
        c = kindLabel(classifyRequest(a))
            .compareTo(kindLabel(classifyRequest(b)));
      case LogColumn.size:
        c = (transferredBytes(a) ?? -1).compareTo(transferredBytes(b) ?? -1);
      case LogColumn.duration:
        c = (a.durationMs ?? -1).compareTo(b.durationMs ?? -1);
      case LogColumn.time:
        c = a.timeStamp.compareTo(b.timeStamp);
    }
    if (!sortAscending) c = -c;
    return c != 0 ? c : b.timeStamp.compareTo(a.timeStamp);
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    server.stop();
    db.dispose();
    super.dispose();
  }
}
