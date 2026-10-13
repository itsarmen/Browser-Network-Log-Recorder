/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import '../capture/classification.dart';
import '../models.dart';

String humanBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

String formatDuration(double? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '${ms.toStringAsFixed(0)} ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

String shortType(LogRecord r) => kindLabel(classifyRequest(r));

String readableDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final l = d.toLocal();
  return '${l.year}-${_pad2(l.month)}-${_pad2(l.day)} ${_pad2(l.hour)}:${_pad2(l.minute)}:${_pad2(l.second)}';
}

String _pad2(int n) => n.toString().padLeft(2, '0');
