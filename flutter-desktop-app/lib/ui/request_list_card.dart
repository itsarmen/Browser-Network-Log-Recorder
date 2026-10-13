/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';

import '../models.dart';
import 'widgets.dart';

/// Prompt 04: the whole request list lives inside one card with a 48px header,
/// a scrolling body and a 40px footer summary. No floating result label.
class RequestListCard extends StatelessWidget {
  const RequestListCard({
    super.key,
    required this.records,
    required this.totalCount,
    required this.onTap,
    required this.emptyTitle,
    required this.emptyHint,
    this.onClear,
    this.onExport,
  });

  final List<LogRecord> records;
  final int totalCount;
  final ValueChanged<LogRecord> onTap;
  final String emptyTitle;
  final String emptyHint;
  final VoidCallback? onClear;
  final VoidCallback? onExport;

  int get _successCount =>
      records.where((r) => r.statusCode != null && r.statusCode! < 400).length;

  int get _errorCount => records
      .where((r) =>
          (r.statusCode != null && r.statusCode! >= 400) ||
          (r.error != null && r.error!.isNotEmpty))
      .length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          Divider(height: 1, color: kBorder(context)),
          Expanded(child: _body(context)),
          Divider(height: 1, color: kBorder(context)),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SizedBox(
      height: AppSizes.header,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            const Text(
              'Requests',
              style: TextStyle(
                fontSize: AppSizes.fontTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            CountPill(records.length),
            const Spacer(),
            if (onExport != null)
              IconButton(
                tooltip: 'Export current view',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: onExport,
              ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear all logs',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: onClear,
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (records.isEmpty) {
      return _empty(context);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      itemCount: records.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: kDivider(context), indent: 12),
      itemBuilder: (context, index) => _LogRow(
        key: ValueKey('${records[index].id}|${records[index].timeStamp}'),
        record: records[index],
        onTap: () => onTap(records[index]),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 44,
              color: AppColors.placeholder,
            ),
            const SizedBox(height: 12),
            Text(
              emptyTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              emptyHint,
              style: const TextStyle(
                fontSize: AppSizes.fontBody,
                color: AppColors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Text(
              'Showing ${records.length} of $totalCount requests',
              style: const TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
            const Spacer(),
            if (records.isNotEmpty) ...[
              _summary(
                Icons.check_circle_outline,
                AppColors.success,
                '$_successCount success',
              ),
              const SizedBox(width: 16),
              _summary(
                Icons.error_outline,
                AppColors.error,
                '$_errorCount error',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: AppSizes.fontSecondary, color: color),
        ),
      ],
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({super.key, required this.record, required this.onTap});

  final LogRecord record;
  final VoidCallback onTap;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          height: AppSizes.listRow,
          decoration: BoxDecoration(
            color: kSurface(context),
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: _hovered
                ? Border.all(color: kBorderHover(context), width: 1)
                : null,
          ),
          child: Row(
            children: [
              MethodBadge(record.method),
              const SizedBox(width: 8),
              StatusPill(status: record.statusCode, error: record.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.pathDisplay,
                      style: const TextStyle(fontSize: AppSizes.fontRowLabel),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      record.hostDisplay,
                      style: const TextStyle(
                        fontSize: AppSizes.fontSecondary,
                        color: AppColors.secondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                record.timeDisplay,
                style: const TextStyle(
                  fontSize: AppSizes.fontSecondary,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
