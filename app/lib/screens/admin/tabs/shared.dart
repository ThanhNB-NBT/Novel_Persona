import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data.dart';
import '../../../widgets.dart';

// Xanh "sống": nhịp tim worker + trạng thái nguồn crawl (không có trong ColorScheme M3).
const kLive = Color(0xFF34C77B);

/// Bọc 1 provider list: loading/error/empty + kéo làm mới.
class AdminRefreshable extends StatelessWidget {
  final AsyncValue<List<Rec>> async;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final Widget Function(List<Rec>) builder;
  const AdminRefreshable(
      {super.key,
      required this.async,
      required this.onRefresh,
      required this.emptyText,
      required this.builder});

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppError(e, onRetry: () => onRefresh()),
      data: (list) => RefreshIndicator(
        onRefresh: onRefresh,
        child: list.isEmpty
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(child: Text(emptyText)),
                ),
              ])
            : builder(list),
      ),
    );
  }
}

/// Một dòng nhịp tim worker: chấm màu + "hoạt động 12s trước". crawler beat mỗi ~10s
/// (mịn hơn khi đang tải chương), translator mỗi 60s; quá 3 phút im = coi như treo/tắt.
/// Dùng chung cho tab Worker và thẻ nhịp tab Crawl.
Widget workerPulse(BuildContext context, List<Rec> beats, String name, String label) {
  final cs = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  final row = beats.where((b) => b['name'] == name).firstOrNull;
  String text;
  Color dot;
  if (row == null) {
    text = '$label: chưa từng chạy';
    dot = cs.error;
  } else {
    final age = DateTime.now().toUtc()
        .difference(DateTime.parse(row['at'] as String).toUtc());
    final alive = age.inSeconds < 180;
    dot = alive ? kLive : cs.error;
    final ago = age.inSeconds < 60 ? '${age.inSeconds}s' : elapsed(row['at'] as String);
    final note = alive ? (row['note'] as String?) : null;
    text = alive
        ? '$label: hoạt động $ago trước${note != null ? ' — $note' : ''}'
        : '$label: KHÔNG phản hồi ($ago) — kiểm tra Docker';
  }
  return Row(children: [
    Container(width: 8, height: 8,
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: t.labelSmall),
    ),
  ]);
}

/// priority nhỏ = ưu tiên cao (schema). Hiện bằng chữ cho đỡ nhầm với số chương.
String priorityLabel(int p) =>
    p <= 1 ? 'ưu tiên cao nhất' : (p < 100 ? 'ưu tiên cao' : 'ưu tiên thường');

/// "2 phút", "1 giờ 5 phút"… từ mốc thời gian ISO tới giờ.
String elapsed(String isoStart) {
  final d = DateTime.now().toUtc().difference(DateTime.parse(isoStart).toUtc());
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (h == 0) return '$m phút';
  if (h >= 24) return '${d.inDays} ngày'; // mốc cũ (chương mới, lần OK) — khỏi "49 giờ"
  return '$h giờ $m phút';
}

/// Chèn dấu chấm phân cách hàng nghìn (12345 → 12.345). Đủ cho số token.
String fmtThousands(Object n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
