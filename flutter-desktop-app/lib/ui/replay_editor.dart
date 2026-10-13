/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../replay.dart';
import 'code_format.dart';
import 'widgets.dart';

class ReplayEditor extends StatefulWidget {
  const ReplayEditor({super.key, required this.state, required this.record});

  final AppState state;
  final LogRecord record;

  @override
  State<ReplayEditor> createState() => _ReplayEditorState();
}

class _ReplayEditorState extends State<ReplayEditor> {
  late final TextEditingController _url;
  late final TextEditingController _headers;
  late final TextEditingController _body;
  late final TextEditingController _hostOverride;
  late String _method;
  bool _follow = true;
  bool _ignoreTls = true;
  bool _running = false;
  bool _advanced = false;

  final List<ReplayOutcome> _history = <ReplayOutcome>[];
  ReplayOutcome? _selectedOutcome;

  static const _methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  @override
  void initState() {
    super.initState();
    _url = TextEditingController();
    _headers = TextEditingController();
    _body = TextEditingController();
    _hostOverride = TextEditingController();
    _loadFromRecord();
  }

  @override
  void didUpdateWidget(covariant ReplayEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.id != widget.record.id ||
        oldWidget.record.timeStamp != widget.record.timeStamp) {
      _history.clear();
      _selectedOutcome = null;
      _loadFromRecord();
    }
  }

  void _loadFromRecord() {
    final r = widget.record;
    _method =
        _methods.contains(r.method.toUpperCase()) ? r.method.toUpperCase() : 'GET';
    _url.text = r.url;
    _headers.text = formatHeaders(r.requestHeaders);
    _body.text = bodyText(r.requestBody);
    _hostOverride.clear();
    _selectedOutcome = null;
  }

  @override
  void dispose() {
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    _hostOverride.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    ReplayOutcome outcome;
    try {
      outcome = await sendReplay(
        method: _method,
        url: _url.text,
        headersText: _headers.text,
        bodyText: _body.text,
        followRedirects: _follow,
        ignoreTls: _ignoreTls,
      );
    } catch (e) {
      outcome = ReplayOutcome(
        time: DateTime.now(),
        method: _method,
        url: _url.text,
        elapsedMs: 0,
        statusCode: 0,
        statusText: 'Request failed: $e',
        headers: '',
        body: '$e',
        success: false,
      );
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _history.insert(0, outcome);
      _selectedOutcome = outcome;
    });
  }

  void _save() {
    final headers = parseHeadersText(_headers.text);
    final body =
        _body.text.isEmpty ? null : RequestBody(kind: 'raw', text: _body.text);
    widget.state.saveRecordEdits(
      widget.record,
      _method,
      _url.text.trim(),
      headers.isEmpty ? null : headers,
      body,
    );
    _snack('Saved to log');
  }

  void _applyHostOverride() {
    final override = _hostOverride.text.trim();
    if (override.isEmpty) return;
    final uri = Uri.tryParse(_url.text);
    if (uri == null) return;
    final parts = override.split(':');
    final host = parts.first;
    final port = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final replaced = port != null
        ? uri.replace(host: host, port: port)
        : uri.replace(host: host);
    setState(() => _url.text = replaced.toString());
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                isDense: true,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: AppSizes.fontBody,
                  color: AppColors.text,
                ),
                iconEnabledColor: AppColors.secondary,
                dropdownColor: AppColors.surface,
                decoration: softDecoration(context),
                items: _methods
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          m,
                          style: const TextStyle(
                            fontSize: AppSizes.fontBody,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? 'GET'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _url,
                style: const TextStyle(fontSize: AppSizes.fontBody),
                decoration: softDecoration(context, hint: 'Request URL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _advancedSection(context),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final request = _requestColumn(context);
            final response = _responseColumn(context);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: request),
                  const SizedBox(width: 16),
                  Expanded(child: response),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                request,
                const SizedBox(height: 16),
                response,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _actionBar(context),
        const SizedBox(height: 20),
        SectionTitle(
          'Run history',
          trailing: _history.isEmpty
              ? null
              : TextButton(
                  onPressed: () => setState(() {
                    _history.clear();
                    _selectedOutcome = null;
                  }),
                  child: const Text('Clear'),
                ),
        ),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No runs yet — press Run.',
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: AppSizes.fontSecondary,
              ),
            ),
          )
        else
          for (final o in _history)
            _HistoryTile(
              outcome: o,
              selected: identical(o, _selectedOutcome),
              onTap: () => setState(() => _selectedOutcome = o),
            ),
      ],
    );
  }

  Widget _advancedSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _advanced = !_advanced),
            child: SizedBox(
              height: AppSizes.button,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      _advanced
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Advanced options',
                      style: TextStyle(fontSize: AppSizes.fontBody),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_advanced) ...[
            Divider(height: 1, color: kDivider(context)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hostOverride,
                          style: const TextStyle(fontSize: AppSizes.fontBody),
                          decoration: softDecoration(
                            context,
                            hint: 'Host override (host or host:port)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _applyHostOverride,
                        child: const Text('Apply to URL'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _check('Follow redirects', _follow,
                          (v) => setState(() => _follow = v)),
                      _check('Ignore TLS errors', _ignoreTls,
                          (v) => setState(() => _ignoreTls = v)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _requestColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Request headers (Name: Value per line)'),
        SizedBox(height: 140, child: _MonoField(controller: _headers)),
        const SizedBox(height: 12),
        const SectionTitle('Request body'),
        SizedBox(height: 140, child: _MonoField(controller: _body)),
      ],
    );
  }

  Widget _responseColumn(BuildContext context) {
    final outcome = _selectedOutcome;
    if (outcome == null) {
      return CopyableBlock(
        title: 'Response',
        copyText: '',
        child: const SizedBox(
          height: 120,
          child: Center(
            child: Text(
              'Run the request to see the response.',
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: AppSizes.fontSecondary,
              ),
            ),
          ),
        ),
      );
    }
    final body = outcome.body;
    final isJson =
        body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CopyableBlock(
          title: 'Response',
          copyText:
              '${outcome.success ? outcome.statusCode : 'ERR'}  ${outcome.elapsedMs} ms',
          child: Row(
            children: [
              StatusPill(
                status: outcome.success ? outcome.statusCode : null,
                error: outcome.success ? null : 'ERR',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  outcome.statusText,
                  style: const TextStyle(fontSize: AppSizes.fontBody),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${outcome.elapsedMs} ms',
                style: const TextStyle(
                  fontSize: AppSizes.fontSecondary,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CodeBlock(
          title: 'Response headers',
          code: outcome.headers,
          copyText: outcome.headers,
          kind: CodeKind.headers,
          height: 120,
        ),
        const SizedBox(height: 12),
        CodeBlock(
          title: 'Response body',
          code: body,
          copyText: body,
          kind: isJson ? CodeKind.json : CodeKind.plain,
          height: 160,
          showWrapToggle: true,
        ),
      ],
    );
  }

  Widget _actionBar(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 18),
          label: const Text('Run'),
        ),
        OutlinedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save to log'),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(_loadFromRecord),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label, style: const TextStyle(fontSize: AppSizes.fontBody)),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.outcome,
    required this.selected,
    required this.onTap,
  });

  final ReplayOutcome outcome;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(
              color: selected
                  ? kBorderSelected(context)
                  : kBorder(context),
            ),
          ),
          child: Row(
            children: [
              StatusPill(
                status: outcome.success ? outcome.statusCode : null,
                error: outcome.success ? null : 'ERR',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label(outcome),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppSizes.fontSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CopyButton(
                text: _copy(outcome),
                size: AppSizes.popupIconButton,
                iconSize: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _stamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static String _label(ReplayOutcome o) {
    final code = o.success ? '${o.statusCode}' : 'ERR';
    return '${_stamp(o.time)}  ${o.method.padRight(7)} $code  '
        '${o.elapsedMs} ms  ${o.url}';
  }

  static String _copy(ReplayOutcome o) {
    final code = o.success ? '${o.statusCode}' : 'ERR';
    return '${_stamp(o.time)}  ${o.method} $code  ${o.elapsedMs} ms\n'
        '${o.url}\n\n${o.statusText}\n\n${o.headers}\n\n${o.body}';
  }
}

class _MonoField extends StatelessWidget {
  const _MonoField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: AppSizes.fontSecondary,
        height: 1.35,
      ),
      decoration: softDecoration(context),
    );
  }
}
