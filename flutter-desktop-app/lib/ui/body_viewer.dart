/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';

import 'package:flutter/material.dart';

import '../capture/classification.dart';
import 'code_format.dart';
import 'format.dart';
import 'widgets.dart';

enum BodyView { pretty, tree, raw }

/// One reusable body viewer used for request and response bodies.
///
/// Header line: content type + size + corner copy button. Segmented switch
/// (Pretty | Tree | Raw) and a search field with match count and up/down.
class BodyViewer extends StatefulWidget {
  const BodyViewer({
    super.key,
    required this.text,
    this.kind = RequestKind.other,
    this.contentType = '',
    this.sizeBytes,
    this.minHeight = 160,
    this.searchFocusNode,
  });

  final String text;
  final RequestKind kind;
  final String contentType;
  final int? sizeBytes;
  final double minHeight;
  final FocusNode? searchFocusNode;

  @override
  State<BodyViewer> createState() => _BodyViewerState();
}

class _BodyViewerState extends State<BodyViewer> {
  BodyView _view = BodyView.pretty;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  int _active = 0;
  int _matchCount = 0;
  bool _showAll = false;

  bool get _isJson =>
      widget.kind == RequestKind.json && _tryDecode(widget.text) != null;
  bool get _isXml => widget.kind == RequestKind.xml || widget.text.trimLeft().startsWith('<?xml');

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _search.text;
    final count = q.isEmpty
        ? 0
        : RegExp(RegExp.escape(q), caseSensitive: false)
            .allMatches(_prettyText())
            .length;
    setState(() {
      _query = q;
      _matchCount = count;
      _active = count == 0 ? 0 : _active.clamp(0, count - 1);
    });
  }

  static dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  String _prettyText() {
    if (widget.text.isEmpty) return '';
    if (_isJson) {
      try {
        return const JsonEncoder.withIndent('  ')
            .convert(jsonDecode(widget.text));
      } catch (_) {
        return widget.text;
      }
    }
    if (_isXml) return prettyXml(widget.text);
    return widget.text;
  }

  String _rawText() => widget.text;

  String get _displayText =>
      _view == BodyView.raw ? _rawText() : _prettyText();

  List<TextSpan> _spans() {
    final text = _displayText;
    if (text.trim().isEmpty) {
      return [const TextSpan(text: '(no body)')];
    }
    List<TextSpan> base;
    if (_view == BodyView.raw) {
      base = plainSpans(text);
    } else if (_isJson) {
      base = jsonSpans(text);
    } else if (_isXml) {
      base = xmlSpans(text);
    } else {
      base = plainSpans(text);
    }
    if (_query.isNotEmpty) base = _highlight(base, _query);
    return base;
  }

  static List<TextSpan> _highlight(List<TextSpan> spans, String query) {
    final result = <TextSpan>[];
    final re = RegExp(RegExp.escape(query), caseSensitive: false);
    for (final span in spans) {
      final text = span.text ?? '';
      if (text.isEmpty) continue;
      var start = 0;
      for (final m in re.allMatches(text)) {
        if (m.start > start) {
          result.add(TextSpan(text: text.substring(start, m.start), style: span.style));
        }
        result.add(TextSpan(
          text: text.substring(m.start, m.end),
          style: (span.style ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.accent,
          ),
        ));
        start = m.end;
      }
      if (start < text.length) {
        result.add(TextSpan(text: text.substring(start), style: span.style));
      }
    }
    return result;
  }

  void _cycle(int delta) {
    if (_matchCount == 0) return;
    setState(() => _active = (_active + delta) % _matchCount);
  }

  @override
  Widget build(BuildContext context) {
    final text = _prettyText();
    final lineCount = '\n'.allMatches(text).length + 1;
    final tooBig = text.length > 200 * 1024 || lineCount > 5000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 8),
        if (_view != BodyView.tree) _searchRow(context),
        if (_view != BodyView.tree) const SizedBox(height: 8),
        if (tooBig && !_showAll)
          _showAllNotice(context, text.length, text.split('\n').take(5000).join('\n'))
        else if (_view == BodyView.tree && _isJson)
          _JsonTree(root: _tryDecode(widget.text))
        else if (_view == BodyView.tree)
          _notice('Tree view is available for JSON bodies only.')
        else
          _codeArea(context, _spans()),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            [
              if (widget.contentType.isNotEmpty) widget.contentType,
              humanBytes(widget.sizeBytes),
            ].join('  ·  '),
            style: const TextStyle(
              fontSize: AppSizes.fontSecondary,
              color: AppColors.secondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _segmented(),
        const SizedBox(width: 8),
        CopyButton(text: _displayText),
      ],
    );
  }

  Widget _segmented() {
    Widget seg(String label, BodyView view, {bool enabled = true}) {
      final selected = _view == view;
      return _segButton(
        label: label,
        selected: selected,
        enabled: enabled,
        onTap: () => setState(() => _view = view),
      );
    }

    return Container(
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.borderField),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Pretty', BodyView.pretty),
          _segDivider(),
          seg('Tree', BodyView.tree, enabled: _isJson),
          _segDivider(),
          seg('Raw', BodyView.raw),
        ],
      ),
    );
  }

  Widget _segDivider() =>
      Container(width: 1, height: 28, color: AppColors.borderField);

  Widget _segButton({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppSizes.fontSecondary,
            color: !enabled
                ? AppColors.disabled
                : selected
                    ? AppColors.text
                    : AppColors.secondary,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _searchRow(BuildContext context) {
    return SizedBox(
      height: AppSizes.field,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: widget.searchFocusNode,
              style: const TextStyle(fontSize: AppSizes.fontBody),
              decoration: softDecoration(
                context,
                hint: 'Search in body',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Clear',
                        onPressed: () => _search.clear(),
                      ),
              ),
            ),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              _matchCount == 0
                  ? 'No matches'
                  : '${_active + 1} of $_matchCount',
              style: const TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
            IconButton(
              tooltip: 'Previous match',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _matchCount == 0 ? null : () => _cycle(-1),
            ),
            IconButton(
              tooltip: 'Next match',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _matchCount == 0 ? null: () => _cycle(1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _codeArea(BuildContext context, List<TextSpan> spans) {
    return Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText.rich(
        TextSpan(children: spans),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: AppSizes.fontMono,
          height: 1.5,
          color: AppColors.text,
        ),
      ),
    );
  }

  Widget _showAllNotice(BuildContext context, int bytes, String preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _codeArea(context, plainSpans(preview)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(() => _showAll = true),
            child: Text('Show all (${humanBytes(bytes)})'),
          ),
        ),
      ],
    );
  }

  Widget _notice(String message) {
    return Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: AppSizes.fontSecondary,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsible JSON tree
// ---------------------------------------------------------------------------

class _JsonTree extends StatelessWidget {
  const _JsonTree({required this.root});

  final dynamic root;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: _TreeNode(label: null, value: root, depth: 0, isLast: true, path: r'$'),
    );
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.label,
    required this.value,
    required this.depth,
    required this.isLast,
    required this.path,
  });

  final String? label;
  final dynamic value;
  final int depth;
  final bool isLast;
  final String path;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  bool get _isMap => widget.value is Map;
  bool get _isList => widget.value is List;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final key = widget.label;
    if (_isMap || _isList) {
      final entries = _isMap
          ? (v as Map).entries.toList()
          : List.generate((v as List).length, (i) => MapEntry('$i', v[i]));
      final open = _isMap ? '{' : '[';
      final close = _isMap ? '}' : ']';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  if (key != null) ...[
                    Text('"$key"',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppSizes.fontMono,
                            color: AppColors.info)),
                    const Text(': ',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppSizes.fontMono)),
                  ],
                  Text('$open ${entries.length} $close',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppSizes.fontMono,
                          color: AppColors.secondary)),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _TreeNode(
                      label: entries[i].key.toString(),
                      value: entries[i].value,
                      depth: widget.depth + 1,
                      isLast: i == entries.length - 1,
                      path: _childPath(entries[i].key.toString()),
                    ),
                ],
              ),
            ),
        ],
      );
    }
    return _leaf(context, key, v);
  }

  String _childPath(String key) {
    if (_isList) return '${widget.path}[$key]';
    return '${widget.path}.$key';
  }

  Widget _leaf(BuildContext context, String? key, dynamic v) {
    final valueStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: AppSizes.fontMono,
      color: v is String
          ? AppColors.success
          : v is num
              ? AppColors.warning
              : v == null
                  ? AppColors.purple
                  : AppColors.purple,
    );
    final valueText =
        v is String ? '"$v"' : v == null ? 'null' : v.toString();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 16),
          if (key != null) ...[
            Text('"$key"',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppSizes.fontMono,
                    color: AppColors.info)),
            const Text(': ',
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: AppSizes.fontMono)),
          ],
          Flexible(
            child: SelectableText(
              valueText,
              style: valueStyle,
            ),
          ),
          if (_hovered) ...[
            const SizedBox(width: 4),
            _treeCopy(
              tooltip: 'Copy value',
              onTap: () => _copy(context, valueText),
            ),
            _treeCopy(
              tooltip: 'Copy path',
              onTap: () => _copy(context, widget.path),
            ),
          ],
        ],
      ),
    );
  }

  bool _hovered = false;

  Widget _treeCopy({required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.copy_outlined, size: 13, color: AppColors.secondary),
        ),
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    copyToClipboard(context, text, text.length > 24 ? 'value' : 'path');
  }
}
