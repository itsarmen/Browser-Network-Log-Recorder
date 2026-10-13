/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:yaru/yaru.dart';

import '../app_state.dart';
import '../log_xml.dart';
import '../models.dart';
import 'copy_as.dart';
import 'details_dialog.dart';
import 'network_table.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _dismissedError;

  final TextEditingController _siteSearchCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _siteSearchFocus = FocusNode();
  final FocusNode _filterFocus = FocusNode();
  final FocusNode _tableFocus = FocusNode();

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _siteSearchCtrl.addListener(
      () => state.setSiteSearch(_siteSearchCtrl.text),
    );
  }

  @override
  void dispose() {
    _siteSearchCtrl.dispose();
    _filterCtrl.dispose();
    _siteSearchFocus.dispose();
    _filterFocus.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final sideWidth = (constraints.maxWidth * 0.3).clamp(
            AppSizes.sidebarMin,
            AppSizes.sidebarMax,
          );
          if (wide) {
            return Scaffold(
              backgroundColor: AppColors.surface,
              body: SelectionArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: sideWidth, child: _sidebar(context)),
                    Expanded(child: _rightPane(context)),
                  ],
                ),
              ),
            );
          }
          return Scaffold(
            drawer: Drawer(
              width: sideWidth,
              child: SelectionArea(child: _sidebar(context)),
            ),
            body: SelectionArea(child: _rightPane(context, drawerButton: true)),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Left sidebar
  // ------------------------------------------------------------------

  Widget _sidebar(BuildContext context) {
    final hasSites = state.sites.any((s) => !s.isAll);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sideHeader(context),
          _siteSearchField(context),
          Expanded(
            child: hasSites
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    itemCount: state.sitesView.length,
                    itemBuilder: (context, index) =>
                        _siteRow(context, state.sitesView[index]),
                  )
                : _sidebarEmpty(context),
          ),
          _sideBottom(context),
        ],
      ),
    );
  }

  Widget _sideHeader(BuildContext context) {
    return Container(
      height: AppSizes.header,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: const Text(
        'Network Log Recorder',
        style: TextStyle(
          fontSize: AppSizes.fontTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _siteSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: SizedBox(
        height: AppSizes.field,
        child: TextField(
          controller: _siteSearchCtrl,
          focusNode: _siteSearchFocus,
          style: const TextStyle(fontSize: AppSizes.fontBody),
          decoration: softDecoration(
            context,
            hint: 'Search websites',
            prefixIcon: const Icon(Icons.search, size: AppSizes.sideRowIcon),
          ),
        ),
      ),
    );
  }

  Widget _siteRow(BuildContext context, SiteItem item) {
    final selected =
        (item.isAll && state.viewSite == null) ||
        (!item.isAll && state.viewSite == item.name);
    return _SideRow(
      key: ValueKey('site-${item.name}'),
      item: item,
      selected: selected,
      onTap: () => state.selectSite(item),
      // "All websites" is an aggregate and cannot be renamed/deleted.
      onRename: item.isAll ? null : () => _renameSite(item.name),
      onDelete: item.isAll ? null : () => _deleteSite(item.name),
    );
  }

  Widget _sidebarEmpty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_outlined,
              size: 40,
              color: AppColors.placeholder,
            ),
            SizedBox(height: 12),
            Text(
              'No websites yet',
              style: TextStyle(
                fontSize: AppSizes.fontBody,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Capture any request to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideBottom(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Capture into',
                style: TextStyle(
                  fontSize: AppSizes.fontSecondary,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 8),
              _captureInto(context),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addSite,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add website'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _captureInto(BuildContext context) {
    final siteNames = [
      kAutoSite,
      ...state.sites.where((s) => !s.isAll).map((s) => s.name),
    ];
    final value = state.activeSite.isEmpty ? kAutoSite : state.activeSite;
    return SizedBox(
      height: AppSizes.field,
      child: DropdownButtonFormField<String>(
        initialValue: siteNames.contains(value) ? value : kAutoSite,
        isExpanded: true,
        isDense: true,
        style: const TextStyle(
          fontSize: AppSizes.fontBody,
          color: AppColors.text,
        ),
        iconEnabledColor: AppColors.secondary,
        dropdownColor: AppColors.surface,
        decoration: softDecoration(context),
        items: [
          for (final name in siteNames)
            DropdownMenuItem(
              value: name,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppSizes.fontBody,
                  color: AppColors.text,
                ),
              ),
            ),
        ],
        onChanged: (v) => state.setActiveSite(v ?? kAutoSite),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Right pane
  // ------------------------------------------------------------------

  Widget _rightPane(BuildContext context, {bool drawerButton = false}) {
    final titleBar = YaruWindowTitleBar(
      leading: drawerButton
          ? Builder(
              builder: (context) => IconButton(
                tooltip: 'Sites',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : null,
      title: Text(_detailTitle),
      actions: _detailActions(context),
    );

    return Focus(
      focusNode: _tableFocus,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _focusFilter,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true):
              _focusFilter,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              state.moveSelection(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              state.moveSelection(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
          const SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          ): _copySelectedAsCurl,
        },
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBar,
              if (_errorMessage != null && _errorMessage != _dismissedError)
                _errorBanner(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: NetworkTableCard(
                    state: state,
                    onOpen: (record) =>
                        showRecordDialog(context, state, record),
                    onClear: _clear,
                    filterController: _filterCtrl,
                    filterFocusNode: _filterFocus,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _focusFilter() {
    _filterFocus.requestFocus();
  }

  void _openSelected() {
    final record = state.selectedRecord;
    if (record != null) showRecordDialog(context, state, record);
  }

  void _escape() {
    if (_filterCtrl.text.isNotEmpty) {
      _filterCtrl.clear();
      state.setLogSearch('');
      return;
    }
    if (state.selectedIndex >= 0) state.selectIndex(-1);
  }

  void _copySelectedAsCurl() {
    final record = state.selectedRecord;
    if (record == null) return;
    copyToClipboard(context, curlCommand(record), 'cURL command');
  }

  String? get _errorMessage {
    final s = state.status;
    return s.startsWith('Could not start server') ? s : null;
  }

  String get _detailTitle {
    final site = state.viewSite ?? 'All websites';
    return '$site · ${state.visible.length}';
  }

  List<Widget> _detailActions(BuildContext context) {
    return [
      _serverPill(context),
      const SizedBox(width: 4),
      IconButton(
        tooltip: state.serverRunning ? 'Stop server' : 'Start server',
        icon: Icon(
          state.serverRunning
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline,
        ),
        onPressed: state.serverRunning ? state.stopServer : state.startServer,
      ),
      IconButton(
        tooltip: state.live ? 'Pause live updates' : 'Resume live updates',
        isSelected: !state.live,
        selectedIcon: const Icon(Icons.play_arrow_outlined),
        icon: const Icon(Icons.pause_outlined),
        onPressed: () => state.setLive(!state.live),
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        onSelected: _onMore,
        itemBuilder: (context) {
          final checked = state.checkedIds.length;
          return [
            const PopupMenuItem(
                value: 'clear', child: Text('Clear all logs')),
            if (checked > 0)
              PopupMenuItem(
                  value: 'clear-selection',
                  child: Text('Clear selection ($checked)')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'view-json', child: Text('Current view → JSON')),
            const PopupMenuItem(
                value: 'view-xml', child: Text('Current view → XML')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'all-json', child: Text('All records → JSON')),
            const PopupMenuItem(
                value: 'all-xml', child: Text('All records → XML')),
            const PopupMenuDivider(),
            PopupMenuItem(
                value: 'selected-json',
                enabled: checked > 0,
                child: Text('Export selected ($checked) → JSON')),
            PopupMenuItem(
                value: 'selected-xml',
                enabled: checked > 0,
                child: Text('Export selected ($checked) → XML')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'import', child: Text('Import JSON/XML…')),
          ];
        },
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget _serverPill(BuildContext context) {
    final running = state.serverRunning;
    final color = running ? AppColors.success : AppColors.error;
    return Tooltip(
      message: state.status,
      child: Container(
        height: AppSizes.pill,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              running ? 'Server running' : 'Server stopped',
              style: TextStyle(
                color: color,
                fontSize: AppSizes.fontSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    final message = _errorMessage!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppSizes.fontBody),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => _showErrorDialog(message),
            child: const Text('Details'),
          ),
          TextButton(onPressed: state.startServer, child: const Text('Retry')),
          CopyButton(
            text: message,
            tooltip: 'Copy error',
            size: AppSizes.popupIconButton,
            iconSize: AppSizes.popupIconButtonIcon,
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _dismissedError = message),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server error'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: const TextStyle(fontSize: AppSizes.fontMono),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  void _onMore(String value) {
    switch (value) {
      case 'clear':
        _clear();
      case 'clear-selection':
        state.clearChecked();
      case 'import':
        _import();
      case 'selected-json':
        _exportRecords(state.checkedRecords, 'json');
      case 'selected-xml':
        _exportRecords(state.checkedRecords, 'xml');
      default:
        _export(value);
    }
  }

  Future<void> _addSite() async {
    final name = await _promptText('Add website', '');
    if (name == null || name.trim().isEmpty) return;
    state.addSite(name.trim());
  }

  Future<void> _renameSite(String current) async {
    final name = await _promptText('Rename website', current);
    if (name == null) return;
    state.renameSite(current, name);
  }

  Future<void> _deleteSite(String current) async {
    final count = state.all.where((r) => r.site == current).length;
    final ok = await _confirm(
      'Delete website',
      'Delete "$current" and its $count records?',
    );
    if (!ok) return;
    state.deleteSite(current);
  }

  Future<void> _clear() async {
    final ok = await _confirm(
      'Clear all logs',
      'Delete every captured record?',
    );
    if (!ok) return;
    state.clearAll();
  }

  Future<void> _export(String action) async {
    final xml = action.endsWith('xml');
    final all = action.startsWith('all');
    await _exportRecords(
        all ? state.all : state.visible, xml ? 'xml' : 'json');
  }

  Future<void> _exportRecords(
      List<LogRecord> records, String extension) async {
    final xml = extension == 'xml';
    if (records.isEmpty) {
      _snack('Nothing to export');
      return;
    }
    final suggested =
        'network-log-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null) return;

    final text = xml
        ? LogXml.serialize(records)
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(records.map((r) => r.toJson()).toList());
    await File(location.path).writeAsString(text);
    _snack('Exported ${records.length} records');
  }

  Future<void> _import() async {
    const typeGroup = XTypeGroup(
      label: 'Log files',
      extensions: ['json', 'xml'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final content = await file.readAsString();
    try {
      final trimmed = content.trimLeft();
      final records = trimmed.startsWith('<')
          ? LogXml.deserialize(content)
          : (jsonDecode(content) as List)
                .map((e) => LogRecord.fromJson(Map<String, dynamic>.from(e)))
                .toList();
      final added = state.importRecords(records);
      _snack('Imported $added records');
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  void _snack(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM_RIGHT,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  Future<String?> _promptText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: softDecoration(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ----------------------------------------------------------------------
// Sidebar row: white fill, hover border, selected border.
// ----------------------------------------------------------------------

class _SideRow extends StatefulWidget {
  const _SideRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  final SiteItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Null for the "All websites" aggregate row (no context menu).
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  State<_SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<_SideRow> {
  bool _hovered = false;

  bool get _hasMenu => widget.onRename != null || widget.onDelete != null;

  @override
  Widget build(BuildContext context) {
    final body = _rowBody(context);
    if (!_hasMenu) return body;
    // Right-click (desktop) / long-press (touch) opens Rename/Delete.
    return MenuAnchor(
      menuChildren: [
        if (widget.onRename != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: widget.onRename,
            child: const Text('Rename'),
          ),
        if (widget.onDelete != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.delete_outline, size: 18),
            onPressed: widget.onDelete,
            child: const Text('Delete'),
          ),
      ],
      builder: (context, controller, child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: controller.open,
        onSecondaryTapDown: (details) =>
            controller.open(position: details.globalPosition),
        child: child,
      ),
      child: body,
    );
  }

  Widget _rowBody(BuildContext context) {
    final border = widget.selected
        ? Border.all(color: AppColors.borderSelected)
        : _hovered
        ? Border.all(color: AppColors.borderHover)
        : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          height: AppSizes.sideRow,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sideRowPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: border,
          ),
          child: Row(
            children: [
              Icon(
                widget.item.isAll ? Icons.public : Icons.language,
                size: AppSizes.sideRowIcon,
                color: AppColors.text,
              ),
              const SizedBox(width: AppSizes.sideRowGap),
              Expanded(
                child: Text(
                  widget.item.display,
                  style: TextStyle(
                    fontSize: AppSizes.fontRowLabel,
                    fontWeight: widget.selected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              CountPill(widget.item.count),
            ],
          ),
        ),
      ),
    );
  }
}
