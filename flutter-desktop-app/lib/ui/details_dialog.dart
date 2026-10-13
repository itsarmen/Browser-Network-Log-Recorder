/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../capture/classification.dart';
import '../models.dart';
import 'body_viewer.dart';
import 'code_format.dart';
import 'copy_as.dart';
import 'dev_sections.dart';
import 'format.dart';
import 'replay_editor.dart';
import 'widgets.dart';

Future<void> showRecordDialog(
  BuildContext context,
  AppState state,
  LogRecord record, {
  int initialTab = 0,
  int? selectedRow,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _RecordDialog(state: state, record: record, initialTab: initialTab),
  );
}

/// White popup, Raw-first tabs, everything selectable & copyable.
class _RecordDialog extends StatefulWidget {
  const _RecordDialog({
    required this.state,
    required this.record,
    required this.initialTab,
  });

  final AppState state;
  final LogRecord record;
  final int initialTab;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog>
    with SingleTickerProviderStateMixin {
  // Order: Raw, Request, Response, Overview, Edit & Run (Raw first).
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    _tabs.animateTo(index.clamp(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width * 0.92 > 900 ? 900.0 : size.width * 0.92;
    final height = size.height * 0.85;
    final record = widget.record;

    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
          const SingleActivator(LogicalKeyboardKey.digit1): () => _selectTab(0),
          const SingleActivator(LogicalKeyboardKey.digit2): () => _selectTab(1),
          const SingleActivator(LogicalKeyboardKey.digit3): () => _selectTab(2),
          const SingleActivator(LogicalKeyboardKey.digit4): () => _selectTab(3),
          const SingleActivator(LogicalKeyboardKey.digit5): () => _selectTab(4),
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: SelectionArea(
            child: Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusPopup),
                border: Border.all(color: AppColors.borderOuter),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, record),
                  const Divider(height: 1, color: AppColors.border),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: AppColors.text,
                    unselectedLabelColor: AppColors.secondary,
                    labelStyle: const TextStyle(
                      fontSize: AppSizes.fontBody,
                      fontWeight: FontWeight.w500,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: AppSizes.fontBody,
                    ),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(color: AppColors.accent, width: 3),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(height: AppSizes.popupTab, text: 'Raw'),
                      Tab(height: AppSizes.popupTab, text: 'Request'),
                      Tab(height: AppSizes.popupTab, text: 'Response'),
                      Tab(height: AppSizes.popupTab, text: 'Overview'),
                      Tab(height: AppSizes.popupTab, text: 'Edit & Run'),
                    ],
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          RawTab(record: record),
                          _RequestTab(record: record),
                          _ResponseTab(record: record),
                          _OverviewTab(record: record),
                          ReplayEditor(state: widget.state, record: record),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, LogRecord record) {
    return SizedBox(
      height: AppSizes.popupHeader,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            MethodBadge(record.method),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                record.url,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: AppSizes.fontTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(
              status: record.statusCode,
              error: record.error,
              failedLabel: true,
            ),
            if (record.durationMs != null) ...[
              const SizedBox(width: 10),
              _chip(formatDuration(record.durationMs)),
            ],
            const SizedBox(width: 8),
            CopyButton(
              text: record.url,
              tooltip: 'Copy URL',
              size: AppSizes.popupIconButton,
              iconSize: AppSizes.popupIconButtonIcon,
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  copyToClipboard(context, curlCommand(record), 'cURL'),
              icon: const Icon(Icons.code, size: 16),
              label: const Text('Copy as cURL'),
            ),
            IconButton(
              tooltip: 'Close (Esc)',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      height: AppSizes.pill,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppSizes.fontSecondary,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Raw (default)
// ---------------------------------------------------------------------------

class RawTab extends StatelessWidget {
  const RawTab({super.key, required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final request = rawRequest(record);
    final response = rawResponse(record);
    final rawObj = rawObjectJson(record);
    final allCopy =
        '=== RAW REQUEST ===\n\n$request\n\n=== RAW RESPONSE ===\n\n$response\n\n=== RAW OBJECT (all stored fields) ===\n\n$rawObj';
    const maxBody = 200 * 1024;

    return ListView(
      children: [
        _RawBlock(
          title: 'Raw object (all stored fields)',
          text: rawObj,
          copyText: rawObj,
          maxBytes: maxBody,
        ),
        const SizedBox(height: 16),
        _RawBlock(
          title: 'Raw request',
          text: request,
          copyText: request,
          maxBytes: maxBody,
        ),
        const SizedBox(height: 16),
        _RawBlock(
          title: 'Raw response',
          text: response,
          copyText: response,
          maxBytes: maxBody,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  copyToClipboard(context, allCopy, 'all raw data'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy all'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RawBlock extends StatefulWidget {
  const _RawBlock({
    required this.title,
    required this.text,
    required this.copyText,
    this.maxBytes = 200 * 1024,
  });

  final String title;
  final String text;
  final String copyText;
  final int maxBytes;

  @override
  State<_RawBlock> createState() => _RawBlockState();
}

class _RawBlockState extends State<_RawBlock> {
  bool _wrap = false;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final encoded = utf8.encode(widget.text);
    final truncated = !_showAll && encoded.length > widget.maxBytes;
    final displayText = truncated
        ? utf8.decode(encoded.sublist(0, widget.maxBytes))
        : widget.text;
    final copyText = widget.copyText;

    Widget content = SelectableText(
      displayText,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: AppSizes.fontMono,
        height: 1.5,
        color: AppColors.text,
      ),
    );

    if (!_wrap) {
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: content,
      );
    }

    return CopyableBlock(
      title: widget.title,
      copyText: copyText,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _wrap,
                onChanged: (v) => setState(() => _wrap = v ?? false),
              ),
              const Text('Wrap lines', style: TextStyle(fontSize: 12)),
            ],
          ),
          if (truncated) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: const Text('Show all'),
            ),
          ],
        ],
      ),
      child: SingleChildScrollView(child: content),
    );
  }
}

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final bodyCopy = requestBodyText(record.requestBody);
    final query = record.uri?.queryParameters ?? const <String, String>{};
    final cookies = requestCookies(record);
    return ListView(
      children: [
        _HeaderTable(title: 'Request headers', headers: record.requestHeaders),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Query parameters',
            copyText: record.uri?.query ?? '',
            entries: query.entries
                .map((e) => MapEntry(e.key, e.value))
                .toList(),
          ),
        ],
        if (cookies.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Cookies',
            copyText:
                record.requestHeaders?['cookie'] ??
                record.requestHeaders?['Cookie'] ??
                '',
            entries: cookies,
          ),
        ],
        if (bodyCopy.isNotEmpty) ...[
          const SizedBox(height: 16),
          BodyViewer(
            text: bodyCopy,
            kind: classifyRequest(record),
            contentType: requestContentTypeOf(record),
            sizeBytes: utf8.encode(bodyCopy).length,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final body = record.responseBody;
    final hasBody = body != null && body.isNotEmpty;
    final statusCopy = record.statusLine ?? record.statusCode?.toString() ?? '';
    final setCookie = responseSetCookies(record);

    return ListView(
      children: [
        CopyableBlock(
          title: 'Status',
          copyText: statusCopy,
          child: Row(
            children: [
              StatusPill(
                status: record.statusCode,
                error: record.error,
                failedLabel: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  record.statusLine ?? record.statusCode?.toString() ?? '—',
                  style: const TextStyle(fontSize: AppSizes.fontBody),
                ),
              ),
              if (record.fromCache)
                const Text(
                  'from cache',
                  style: TextStyle(
                    fontSize: AppSizes.fontSecondary,
                    color: AppColors.secondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _HeaderTable(
          title: 'Response headers',
          headers: record.responseHeaders,
        ),
        if (setCookie.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Set-Cookie',
            copyText: setCookieRaw(record),
            entries: setCookie,
          ),
        ],
        const SizedBox(height: 16),
        if (!hasBody)
          CopyableBlock(
            title: 'Response body',
            copyText: '',
            child: const Text(
              '(not captured — enable "Capture response bodies" in the '
              'extension, or this was a cached/redirect response)',
              style: TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
          )
        else
          BodyViewer(
            text: body,
            kind: classifyRequest(record),
            contentType: contentTypeOf(record),
            sizeBytes: utf8.encode(body).length,
            minHeight: 240,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overview (developer sections)
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final general = <MapEntry<String, String>>[
      MapEntry('Website', record.site.isEmpty ? '—' : record.site),
      MapEntry('Method', record.methodDisplay),
      MapEntry('URL', record.url),
      MapEntry(
        'Status',
        record.statusLine ??
            record.statusCode?.toString() ??
            (record.error ?? 'pending'),
      ),
      MapEntry(
        'Type',
        '${kindLabel(classifyRequest(record))} '
            '(${record.type.isEmpty ? '—' : record.type})',
      ),
      MapEntry('Duration', formatDuration(record.durationMs)),
      MapEntry('Size', humanBytes(transferredBytes(record))),
      MapEntry('Cached', record.fromCache ? 'yes' : 'no'),
      MapEntry('Tab', '${record.tabId}'),
      MapEntry('Started', readableDate(record.startedAt)),
      if (record.error != null) MapEntry('Error', record.error!),
    ];

    final important = importantHeaders(record);
    final query = record.uri?.queryParameters ?? const <String, String>{};
    final cookies = requestCookies(record);
    final isGql = classifyRequest(record) == RequestKind.gql;
    final jwt = decodeJwt(record);

    return ListView(
      children: [
        _KeyValueBlock(
          title: 'General',
          copyText: buildDetailsText(record),
          entries: general,
          labelWidth: 160,
        ),
        if (important.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Important headers',
            copyText: important.map((e) => '${e.key}: ${e.value}').join('\n'),
            entries: important,
            labelWidth: 160,
          ),
        ],
        if (query.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Query parameters',
            copyText: record.uri?.query ?? '',
            entries: query.entries
                .map((e) => MapEntry(e.key, e.value))
                .toList(),
            labelWidth: 160,
          ),
        ],
        if (cookies.isNotEmpty) ...[
          const SizedBox(height: 16),
          _KeyValueBlock(
            title: 'Cookies',
            copyText:
                record.requestHeaders?['cookie'] ??
                record.requestHeaders?['Cookie'] ??
                '',
            entries: cookies,
            labelWidth: 160,
          ),
        ],
        if (isGql) ...[
          const SizedBox(height: 16),
          CopyableBlock(
            title: 'GraphQL',
            copyText: requestBodyText(record.requestBody),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (graphqlType(record) != null)
                  Text(
                    '${graphqlType(record)} '
                    '${graphqlOperation(record) ?? ''}',
                    style: const TextStyle(
                      fontSize: AppSizes.fontBody,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                const SizedBox(height: 8),
                SelectableText(
                  _graphqlQuery(record) ?? '(no query captured)',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppSizes.fontMono,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (jwt != null) ...[
          const SizedBox(height: 16),
          CopyableBlock(
            title: 'Authorization · JWT decoded',
            copyText: jsonPseudo(jwt),
            child: SelectableText(
              jsonPseudo(jwt),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: AppSizes.fontMono,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String? _graphqlQuery(LogRecord r) {
    final body = requestBodyText(r.requestBody);
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['query'] is String) {
        return decoded['query'] as String;
      }
    } catch (_) {}
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared header / key-value widgets
// ---------------------------------------------------------------------------

class _HeaderTable extends StatelessWidget {
  const _HeaderTable({required this.title, required this.headers});

  final String title;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final entries = headers?.entries.toList() ?? <MapEntry<String, String>>[];
    return CopyableBlock(
      title: title,
      copyText: formatHeaders(headers),
      child: entries.isEmpty
          ? const Text(
              '(none)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppSizes.fontMono,
                color: AppColors.secondary,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _KeyValueRow(
                    name: entries[i].key,
                    value: entries[i].value,
                    dividerTop: i > 0,
                    monoValue: true,
                    labelWidth: 190,
                  ),
              ],
            ),
    );
  }
}

class _KeyValueBlock extends StatelessWidget {
  const _KeyValueBlock({
    required this.title,
    required this.copyText,
    required this.entries,
    this.labelWidth = 190,
  });

  final String title;
  final String copyText;
  final List<MapEntry<String, String>> entries;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return CopyableBlock(
      title: title,
      copyText: copyText,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _KeyValueRow(
              name: entries[i].key,
              value: entries[i].value,
              dividerTop: i > 0,
              monoValue: true,
              labelWidth: labelWidth,
            ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  const _KeyValueRow({
    required this.name,
    required this.value,
    this.dividerTop = false,
    this.monoValue = false,
    this.labelWidth = 150,
  });

  final String name;
  final String value;
  final bool dividerTop;
  final bool monoValue;
  final double labelWidth;

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.dividerTop)
            const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: widget.labelWidth,
                  child: SelectableText(
                    widget.name,
                    style: const TextStyle(
                      fontSize: AppSizes.fontBody,
                      fontWeight: FontWeight.w500,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    widget.value,
                    style: TextStyle(
                      fontSize: AppSizes.fontMono,
                      height: 1.4,
                      fontFamily: widget.monoValue ? 'monospace' : null,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: AppSizes.popupIconButton,
                  child: _hovered
                      ? CopyButton(
                          text: widget.value,
                          size: AppSizes.popupIconButton,
                          iconSize: 14,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
