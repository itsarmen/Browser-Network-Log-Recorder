/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../capture/classification.dart';
import '../models.dart';
import 'copy_as.dart';
import '../filter_query.dart';
import 'format.dart';
import 'widgets.dart';

/// The Firefox-DevTools-style network table card: toolbar, column titles,
/// compact one-line rows and a status footer, all in one bordered card.
class NetworkTableCard extends StatelessWidget {
  const NetworkTableCard({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onClear,
    required this.filterController,
    required this.filterFocusNode,
  });

  final AppState state;
  final ValueChanged<LogRecord> onOpen;
  final VoidCallback onClear;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            state: state,
            onClear: onClear,
            filterController: filterController,
            filterFocusNode: filterFocusNode,
          ),
          Divider(height: 1, color: AppColors.divider),
          _ColumnHeader(state: state),
          Divider(height: 1, color: AppColors.border),
          Expanded(child: _Body(state: state, onOpen: onOpen)),
          Divider(height: 1, color: AppColors.divider),
          _Footer(state: state),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.onClear,
    required this.filterController,
    required this.filterFocusNode,
  });

  final AppState state;
  final VoidCallback onClear;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.toolbar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear (Ctrl+Shift+C is Copy as cURL)',
              icon: const Icon(Icons.delete_outline),
              onPressed: onClear,
            ),
            _vsep(context),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                height: AppSizes.field,
                child: TextField(
                  controller: filterController,
                  focusNode: filterFocusNode,
                  style: const TextStyle(fontSize: AppSizes.fontBody),
                  decoration: softDecoration(
                    context,
                    hint: 'Filter URLs, method, status, headers...',
                    prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: filterController,
                      builder: (context, value, child) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Clear filter',
                              onPressed: () => state.setLogSearch(''),
                            ),
                    ),
                  ),
                  onChanged: state.setLogSearch,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: kFilterHelp,
              child: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showHelp(context),
              ),
            ),
            const SizedBox(width: 4),
            _vsep(context),
            Tooltip(
              message: state.live
                  ? 'Live on: new requests appear on page 1 automatically'
                  : 'Live off: list is frozen, arrivals buffer in background',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSizes.radius),
                onTap: () => state.setLive(!state.live),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: state.live,
                        onChanged: (v) => state.setLive(v ?? false),
                      ),
                      const Text(
                        'Live',
                        style: TextStyle(fontSize: AppSizes.fontBody),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh from database',
              icon: Badge(
                isLabelVisible: state.pending.isNotEmpty,
                label: Text('${state.pending.length}'),
                child: const Icon(Icons.refresh),
              ),
              onPressed: state.refresh,
            ),
            SkippedTypesButton(state: state),
            DropdownButton<String>(
              value: state.methodFilter,
              isDense: true,
              underline: const SizedBox.shrink(),
              iconEnabledColor: AppColors.secondary,
              dropdownColor: AppColors.surface,
              style: const TextStyle(
                fontSize: AppSizes.fontBody,
                color: AppColors.text,
              ),
              items: [
                for (final method in AppState.methodOptions)
                  DropdownMenuItem(
                    value: method,
                    child: Text(
                      method == 'All' ? 'Method: All' : method,
                      style: const TextStyle(
                        fontSize: AppSizes.fontBody,
                        color: AppColors.text,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) state.setMethodFilter(v);
              },
            ),
            Expanded(child: _TypeTabs(state: state)),
          ],
        ),
      ),
    );
  }

  Widget _vsep(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.divider,
      );

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter syntax'),
        content: SelectableText(kFilterHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tabs = state.typeTabs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            _TypeTab(
              label: tab,
              selected: state.typeTab == tab,
              onTap: () => state.setTypeTab(tab),
            ),
        ],
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  const _TypeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: AppSizes.toolbar,
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
            fontSize: AppSizes.fontMono,
            color: selected ? AppColors.text : AppColors.secondary,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// "Skipped types" popover (Part 2).
class SkippedTypesButton extends StatelessWidget {
  const SkippedTypesButton({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [_SkippedPanel(state: state)],
      builder: (context, controller, child) => Tooltip(
        message: 'Skipped types',
        child: IconButton(
          icon: const Icon(Icons.visibility_off_outlined),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}

class _SkippedPanel extends StatefulWidget {
  const _SkippedPanel({required this.state});

  final AppState state;

  @override
  State<_SkippedPanel> createState() => _SkippedPanelState();
}

class _SkippedPanelState extends State<_SkippedPanel> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final skip = state.skip;
    Widget row(String label, bool value, VoidCallback onTap) => InkWell(
          onTap: () {
            onTap();
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged: (_) {
                    onTap();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: AppSizes.fontBody)),
              ],
            ),
          ),
        );

    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Skip these types',
            style: TextStyle(
              fontSize: AppSizes.fontSection,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 4),
          row('Images', skip.images, state.toggleSkipImages),
          row('JavaScript', skip.scripts, state.toggleSkipScripts),
          row('Fonts', skip.fonts, state.toggleSkipFonts),
          row('Videos & audio', skip.media, state.toggleSkipMedia),
          row('Downloads and archives', skip.downloads, state.toggleSkipDownloads),
          Divider(height: 1, color: AppColors.divider),
          row('Hide CORS preflight (OPTIONS)', skip.hidePreflight,
              state.toggleHidePreflight),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column titles
// ---------------------------------------------------------------------------

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.columnHeader,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            _CheckCell(
              // null = dash: some (not all) of the page is checked.
              value: state.pageAnyChecked
                  ? (state.pageAllChecked ? true : null)
                  : false,
              onChanged: (_) =>
                  state.setPageChecked(!state.pageAllChecked),
            ),
            Expanded(
              child: ColumnLayout.buildHeader(
                constraints.maxWidth - _CheckCell.width,
                (column, label, flex, right, onTap) => Expanded(
                  flex: flex,
                  child: _HeaderCell(
                    label: label,
                    right: right,
                    active: state.sortColumn == column,
                    ascending: state.sortAscending,
                    onTap: onTap,
                  ),
                ),
                (column) => state.setSortColumn(column),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.right,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool right;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Row(
            mainAxisAlignment:
                right ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppSizes.fontMono,
                    fontWeight: FontWeight.w500,
                    color: active ? AppColors.text : AppColors.secondary,
                  ),
                ),
              ),
              if (active)
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: AppColors.text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body (rows)
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onOpen});

  final AppState state;
  final ValueChanged<LogRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final records = state.pageItems;
    if (records.isEmpty) {
      return _Empty(state: state);
    }
    // Indices stay global (position inside state.visible) so keyboard
    // navigation, selection and dialogs keep working across pages.
    final offset = state.pageStart;
    return LayoutBuilder(
      builder: (context, constraints) => ListView.builder(
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: records.length,
        itemBuilder: (context, index) => _Row(
          state: state,
          record: records[index],
          index: offset + index,
          width: constraints.maxWidth,
          onOpen: onOpen,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final captured = state.stored.isEmpty;
    final filtered = !captured &&
        (state.logSearch.trim().isNotEmpty ||
            state.typeTab != 'All' ||
            state.methodFilter != 'All');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 44, color: AppColors.placeholder),
            const SizedBox(height: 12),
            Text(
              captured
                  ? 'No requests captured yet'
                  : filtered
                      ? 'No requests match the filter'
                      : 'No requests captured yet',
              style: const TextStyle(
                fontSize: AppSizes.fontBody,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 4),
            if (captured) ...[
              const Text(
                'Images, JavaScript, fonts and videos are skipped.',
                style: TextStyle(
                  fontSize: AppSizes.fontSecondary,
                  color: AppColors.placeholder,
                ),
              ),
              const SizedBox(height: 4),
              SkippedTypesButton(state: state),
            ] else if (filtered)
              TextButton(
                onPressed: () {
                  state.setLogSearch('');
                  state.setTypeTab('All');
                  state.setMethodFilter('All');
                },
                child: const Text('Clear filter'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fixed-width checkbox cell for the header (select page) and the rows.
/// Lives outside the flex column layout so all columns stay aligned.
class _CheckCell extends StatelessWidget {
  const _CheckCell({required this.value, required this.onChanged});

  static const double width = 36;

  /// null renders the tristate dash (page partially checked).
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: Checkbox(
          value: value,
          tristate: true,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.state,
    required this.record,
    required this.index,
    required this.width,
    required this.onOpen,
  });

  final AppState state;
  final LogRecord record;
  final int index;
  final double width;
  final ValueChanged<LogRecord> onOpen;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final selected = widget.state.selectedIndex == widget.index;
    return MenuAnchor(
      menuChildren: _menu(context),
      builder: (context, controller, child) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.state.selectIndex(widget.index);
            widget.onOpen(r);
          },
          onSecondaryTapDown: (details) =>
              controller.open(position: details.globalPosition),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
              height: AppSizes.tableRow,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: (selected || _hovered)
                    ? Border.all(
                        color: selected
                            ? AppColors.borderSelected
                            : AppColors.borderHover,
                      )
                    : null,
              ),
              child: Row(
                children: [
                  _CheckCell(
                    value: widget.state.isChecked(r),
                    onChanged: (_) => widget.state.toggleChecked(r),
                  ),
                  Expanded(
                    child: ColumnLayout.buildRow(
                      widget.width - _CheckCell.width,
                      _cells(context, r, selected),
                    ),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
  }

  List<Widget> _menu(BuildContext context) {
    final r = widget.record;
    void copy(String text, String label) =>
        copyToClipboard(context, text, label);
    return [
      MenuItemButton(
        onPressed: () => copy(r.url, 'URL'),
        child: const Text('Copy URL'),
      ),
      SubmenuButton(
        menuChildren: [
          for (final kind in CopyAsKind.values)
            MenuItemButton(
              onPressed: () => copy(copyAs(kind, r), copyAsLabel(kind)),
              child: Text('Copy as ${copyAsLabel(kind)}'),
            ),
        ],
        child: const Text('Copy as'),
      ),
      MenuItemButton(
        onPressed: () => copy(requestBodyText(r.requestBody), 'request body'),
        child: const Text('Copy request body'),
      ),
      MenuItemButton(
        onPressed: () => copy(r.responseBody ?? '', 'response body'),
        child: const Text('Copy response body'),
      ),
      if (classifyRequest(r) == RequestKind.json)
        MenuItemButton(
          onPressed: () => copy(prettyResponseIfJson(r), 'pretty JSON'),
          child: const Text('Copy response as pretty JSON'),
        ),
    ];
  }

  List<Widget> _cells(
    BuildContext context,
    LogRecord r,
    bool selected,
  ) {
    final dim = isPreflight(r);
    final textColor = dim ? AppColors.placeholder : AppColors.text;
    final secondary = dim ? AppColors.placeholder : AppColors.secondary;

    final durationColor = isVerySlow(r)
        ? AppColors.error
        : isSlow(r)
            ? AppColors.warning
            : secondary;

    return [
      _cell(
        right: false,
        child: StatusPill(
          status: r.statusCode,
          error: r.error,
          failedLabel: true,
        ),
      ),
      _cell(right: false, child: MethodBadge(r.method)),
      _cell(
        right: false,
        child: Text(
          r.hostDisplay,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppSizes.fontMono, color: textColor),
        ),
      ),
      _cell(
        right: false,
        child: Tooltip(
          message: r.url,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            _fileLabel(r),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppSizes.fontMono,
              color: textColor,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
      _cell(
        right: false,
        child: Text(
          shortType(r),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppSizes.fontMono, color: secondary),
        ),
      ),
      _cell(
        right: true,
        child: Text(
          humanBytes(transferredBytes(r)),
          style: TextStyle(fontSize: AppSizes.fontMono, color: secondary),
        ),
      ),
      _cell(
        right: true,
        child: Text(
          r.timeDisplay,
          style: TextStyle(fontSize: AppSizes.fontMono, color: secondary),
        ),
      ),
      _cell(
        right: true,
        child: Text(
          formatDuration(r.durationMs),
          style: TextStyle(fontSize: AppSizes.fontMono, color: durationColor),
        ),
      ),
    ];
  }

  static String _fileLabel(LogRecord r) {
    if (classifyRequest(r) == RequestKind.gql) {
      final op = graphqlOperation(r);
      final type = graphqlType(r);
      if (op != null) return 'gql${type != null ? ' $type' : ''} $op';
      return 'gql ${r.pathDisplay}';
    }
    return r.pathDisplay;
  }

  Widget _cell({required bool right, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final records = state.visible;
    final filtered = state.logSearch.trim().isNotEmpty ||
        state.typeTab != 'All' ||
        state.methodFilter != 'All' ||
        state.viewSite != null;
    final totalBytes = records.fold<int>(0, (sum, r) => sum + (transferredBytes(r) ?? 0));
    final slowest = records
        .where((r) => r.durationMs != null)
        .fold<double>(0, (max, r) => r.durationMs! > max ? r.durationMs! : max);
    final success = records.where((r) => r.statusCode != null && r.statusCode! < 400).length;
    final errors = records.where(isError).length;
    final json = records.where((r) => classifyRequest(r) == RequestKind.json).length;

    Widget item(String text, {Color? color}) => Text(
          text,
          style: TextStyle(fontSize: AppSizes.fontSecondary, color: color ?? AppColors.secondary),
        );

    final parts = <Widget>[
      item(filtered
          ? '${records.length} of ${state.stored.length} requests (filtered)'
          : '${records.length} requests'),
      _sep(),
      item('${humanBytes(totalBytes)} total'),
      if (records.isNotEmpty) ...[_sep(), item('Finished in ${formatDuration(slowest)}')],
      if (json > 0) ...[_sep(), item('$json json')],
      if (state.skippedSession > 0) ...[
        _sep(),
        _skippedChip(context),
      ],
    ];

    return SizedBox(
      height: AppSizes.cardFooter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: parts),
              ),
            ),
            if (records.isNotEmpty) ...[
              if (success > 0)
                item('$success success', color: AppColors.success),
              if (success > 0 && errors > 0) const SizedBox(width: 12),
              if (errors > 0) item('$errors error', color: AppColors.error),
            ],
            const SizedBox(width: 8),
            _pager(context),
          ],
        ),
      ),
    );
  }

  Widget _pager(BuildContext context) {
    final last = state.pageCount - 1;
    final atFirst = state.pageIndex <= 0;
    final atLast = state.pageIndex >= last;
    IconButton btn(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon, size: 18), onPressed: onTap);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1, height: 14, color: AppColors.divider),
        const SizedBox(width: 4),
        btn(Icons.skip_previous, 'First page',
            atFirst ? null : () => state.setPage(0)),
        btn(Icons.chevron_left, 'Previous page',
            atFirst ? null : () => state.setPage(state.pageIndex - 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${state.pageRangeLabel} • ${state.pageLabel}',
            maxLines: 1,
            style: const TextStyle(
              fontSize: AppSizes.fontSecondary,
              color: AppColors.secondary,
            ),
          ),
        ),
        btn(Icons.chevron_right, 'Next page',
            atLast ? null : () => state.setPage(state.pageIndex + 1)),
        btn(Icons.skip_next, 'Last page',
            atLast ? null : () => state.setPage(last)),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value: state.pageSize,
          isDense: true,
          underline: const SizedBox.shrink(),
          iconEnabledColor: AppColors.secondary,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            fontSize: AppSizes.fontSecondary,
            color: AppColors.text,
          ),
          items: [
            for (final size in AppState.pageSizeOptions)
              DropdownMenuItem(
                value: size,
                child: Text(
                  '$size',
                  style: const TextStyle(
                    fontSize: AppSizes.fontSecondary,
                    color: AppColors.text,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) state.setPageSize(v);
          },
        ),
      ],
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.divider,
      );

  Widget _skippedChip(BuildContext context) {
    return InkWell(
      onTap: () => copyToClipboard(
        context,
        '${state.skippedSession} requests skipped this session',
        'skipped count',
      ),
      child: Text(
        '${state.skippedSession} skipped',
        style: const TextStyle(
          fontSize: AppSizes.fontSecondary,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column layout (shared by header + rows so they always line up)
// ---------------------------------------------------------------------------

class ColumnLayout {
  static const _statusFlex = 8;
  static const _methodFlex = 8;
  static const _domainFlex = 16;
  static const _fileFlex = 30;
  static const _typeFlex = 8;
  static const _sizeFlex = 8;
  static const _timeFlex = 9;
  static const _durationFlex = 8;

  static bool showDuration(double w) => w >= 900;
  static bool showTime(double w) => w >= 820;
  static bool showType(double w) => w >= 720;
  static bool showSize(double w) => w >= 640;

  /// Invokes [emit] for each visible column in order.
  static List<Widget> _build(
    double width,
    Widget Function(
      LogColumn column,
      String label,
      int flex,
      bool right,
      VoidCallback onTap,
    ) emit,
    void Function(LogColumn) onSort,
  ) {
    VoidCallback tap(LogColumn c) => () => onSort(c);
    return [
      emit(LogColumn.status, 'Status', _statusFlex, false, tap(LogColumn.status)),
      emit(LogColumn.method, 'Method', _methodFlex, false, tap(LogColumn.method)),
      emit(LogColumn.domain, 'Domain', _domainFlex, false, tap(LogColumn.domain)),
      emit(LogColumn.file, 'File', _fileFlex, false, tap(LogColumn.file)),
      if (showType(width))
        emit(LogColumn.type, 'Type', _typeFlex, false, tap(LogColumn.type)),
      if (showSize(width))
        emit(LogColumn.size, 'Size', _sizeFlex, true, tap(LogColumn.size)),
      if (showTime(width))
        emit(LogColumn.time, 'Time', _timeFlex, true, tap(LogColumn.time)),
      if (showDuration(width))
        emit(LogColumn.duration, 'Duration', _durationFlex, true, tap(LogColumn.duration)),
    ];
  }

  static Widget buildHeader(
    double width,
    Widget Function(LogColumn, String, int, bool, VoidCallback) emit,
    void Function(LogColumn) onSort,
  ) {
    return Row(children: _build(width, emit, onSort));
  }

  static Widget buildRow(double width, List<Widget> cells) {
    // `cells` is always built in the fixed column order; keep only the ones
    // visible at this width so rows line up with the header.
    final visible = <int>[0, 1, 2, 3];
    if (showType(width)) visible.add(4);
    if (showSize(width)) visible.add(5);
    if (showTime(width)) visible.add(6);
    if (showDuration(width)) visible.add(7);
    return Row(
      children: [
        for (final i in visible)
          Expanded(flex: _flexFor(i), child: cells[i]),
      ],
    );
  }

  static int _flexFor(int index) => switch (index) {
        0 => _statusFlex,
        1 => _methodFlex,
        2 => _domainFlex,
        3 => _fileFlex,
        4 => _typeFlex,
        5 => _sizeFlex,
        6 => _timeFlex,
        _ => _durationFlex,
      };
}
