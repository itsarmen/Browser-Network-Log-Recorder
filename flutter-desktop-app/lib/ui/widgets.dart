/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'app_theme.dart';
import 'code_format.dart';

export 'app_theme.dart';

// ---------------------------------------------------------------------------
// Semantic colours
// ---------------------------------------------------------------------------

Color methodColor(String method) {
  switch (method.toUpperCase()) {
    case 'GET':
      return AppColors.info;
    case 'POST':
      return AppColors.success;
    case 'PUT':
      return AppColors.warning;
    case 'PATCH':
      return AppColors.purple;
    case 'DELETE':
      return AppColors.error;
    default:
      return AppColors.secondary;
  }
}

Color statusColor(int? status, {String? error}) {
  if (status == null) {
    return error != null && error.isNotEmpty
        ? AppColors.secondary
        : AppColors.secondary;
  }
  if (status < 300) return AppColors.success;
  if (status < 400) return AppColors.info;
  if (status < 500) return AppColors.warning;
  return AppColors.error;
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color kBorder(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorder : AppColors.border;

Color kDivider(BuildContext context) =>
    _isDark(context) ? AppColors.darkDivider : AppColors.divider;

Color kBorderField(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderField : AppColors.borderField;

Color kBorderHover(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderHover : AppColors.borderHover;

Color kBorderSelected(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorderSelected : AppColors.borderSelected;

Color kBorderOuter(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorder : AppColors.borderOuter;

Color kSurface(BuildContext context) => Theme.of(context).colorScheme.surface;

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

/// The single reusable badge. Height fixed, optionally fixed width, white fill,
/// 1px border in the badge colour at 40% opacity, full-colour text.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    this.width,
    this.height = AppSizes.badgeH,
  });

  final String label;
  final Color color;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Center(
        child: Container(
          height: height,
          width: width,
          alignment: Alignment.center,
          padding: width == null
              ? const EdgeInsets.symmetric(horizontal: 8)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: kSurface(context),
            borderRadius: BorderRadius.circular(AppSizes.radiusBadge),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: AppSizes.fontBadge,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class MethodBadge extends StatelessWidget {
  const MethodBadge(this.method, {super.key});

  final String method;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: method.isEmpty ? '?' : method.toUpperCase(),
      color: methodColor(method),
      width: AppSizes.badgeMethodW,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.status,
    this.error,
    this.failedLabel = false,
  });

  final int? status;
  final String? error;

  /// When true a failed request shows "failed" instead of "ERR".
  final bool failedLabel;

  @override
  Widget build(BuildContext context) {
    final label =
        status?.toString() ??
        (error != null && error!.isNotEmpty
            ? (failedLabel ? 'failed' : 'ERR')
            : '…');
    return AppBadge(
      label: label,
      color: statusColor(status, error: error),
      width: AppSizes.badgeStatusW,
    );
  }
}

class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.countBadgeH,
      constraints: const BoxConstraints(minWidth: AppSizes.countBadgeMinW),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusCount),
        border: Border.all(color: kBorder(context)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: AppSizes.fontBadge,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.size = AppSizes.iconButton,
    this.iconSize = AppSizes.iconButtonIcon,
    this.tooltip = 'Copy',
    this.bordered = true,
  });

  final String text;
  final double size;
  final double iconSize;
  final String tooltip;
  final bool bordered;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _done = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    if (widget.text.isEmpty) {
      _snack('Nothing to copy');
      return;
    }
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _done = true);
    _snack('Copied');
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _done = false);
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSizes.radius);
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: _copy,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: widget.bordered
                      ? Border.all(
                          color: _hovered
                              ? kBorderHover(context)
                              : kBorder(context),
                        )
                      : null,
                ),
                child: Icon(
                  _done ? Icons.check : Icons.copy_outlined,
                  size: widget.iconSize,
                  color: _done ? AppColors.success : AppColors.secondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white bordered card with a label (top-left), optional trailing widget and
/// a copy button (top-right).
class CopyableBlock extends StatelessWidget {
  const CopyableBlock({
    super.key,
    this.title,
    required this.copyText,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
  });

  final String? title;
  final String copyText;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (title != null)
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: AppSizes.fontSection,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Spacer(),
              ?trailing,
              CopyButton(
                text: copyText,
                size: AppSizes.popupIconButton,
                iconSize: AppSizes.popupIconButtonIcon,
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

enum CodeKind { json, headers, plain, http }

/// Selectable, syntax-coloured, copyable code block with an optional wrap toggle.
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.title,
    required this.copyText,
    required this.code,
    this.kind = CodeKind.plain,
    this.height,
    this.showWrapToggle = false,
  });

  final String title;
  final String copyText;
  final String code;
  final CodeKind kind;
  final double? height;
  final bool showWrapToggle;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _wrap = true;

  List<TextSpan> _spans() {
    switch (widget.kind) {
      case CodeKind.json:
        return jsonSpans(widget.code);
      case CodeKind.headers:
        return headerSpans(widget.code);
      case CodeKind.http:
        return httpSpans(widget.code);
      case CodeKind.plain:
        return plainSpans(widget.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rich = SelectableText.rich(
      TextSpan(children: _spans()),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: AppSizes.fontMono,
        height: 1.5,
        color: AppColors.text,
      ),
    );
    Widget content = _wrap
        ? rich
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: rich);
    if (widget.height != null) {
      content = SizedBox(
        height: widget.height,
        child: SingleChildScrollView(child: content),
      );
    }
    return CopyableBlock(
      title: widget.title,
      copyText: widget.copyText,
      trailing: widget.showWrapToggle
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _wrap,
                      onChanged: (v) => setState(() => _wrap = v ?? true),
                    ),
                    const Text('Wrap lines', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            )
          : null,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class Card2 extends StatelessWidget {
  const Card2({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      child: child,
    );
  }
}

InputDecoration softDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSizes.radius),
    borderSide: BorderSide(color: color, width: width),
  );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: false,
    fillColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    border: border(Colors.transparent, 0),
    enabledBorder: border(kBorderField(context), 1),
    focusedBorder: border(AppColors.accent, 1.5),
    errorBorder: border(const Color(0xFFD9534F), 1),
    focusedErrorBorder: border(const Color(0xFFD9534F), 1),
    hintStyle: const TextStyle(
      color: AppColors.placeholder,
      fontSize: AppSizes.fontBody,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: AppSizes.fontSection,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class MonoBox extends StatelessWidget {
  const MonoBox({
    super.key,
    required this.text,
    this.height,
    this.selectable = true,
  });

  final String text;
  final double? height;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: AppSizes.fontMono,
      height: 1.5,
      color: AppColors.text,
    );
    final content = (text.isEmpty ? '(none)' : text);
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface(context),
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: kBorder(context)),
      ),
      child: SingleChildScrollView(
        child: selectable
            ? SelectableText(content, style: style)
            : Text(content, style: style),
      ),
    );
  }
}

void copyToClipboard(BuildContext context, String text, String label) {
  if (text.isEmpty) {
    Fluttertoast.showToast(
      msg: 'Nothing to copy ($label)',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM_RIGHT,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
    return;
  }
  Clipboard.setData(ClipboardData(text: text));
  Fluttertoast.showToast(
    msg: 'Copied $label (${text.length} chars)',
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM_RIGHT,
    timeInSecForIosWeb: 2,
    backgroundColor: Colors.black87,
    textColor: Colors.white,
  );
}
