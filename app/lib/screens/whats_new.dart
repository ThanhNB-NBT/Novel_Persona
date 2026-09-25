import 'package:flutter/material.dart';

import '../data.dart';

/// "Có gì mới" theo TỪNG bản phát hành: máy đã xem tới bản nào thì chỉ hiện các bản
/// sau đó (lên thẳng từ 1.x thấy cả 2.0 lẫn các bản sau). Người cài mới không cần
/// (với họ chưa có gì "cũ"), họ đã có lời mời xem Hướng dẫn ở shell.
/// Phát hành bản có điểm mới → thêm một dòng vào CUỐI [releases].
const _key = 'whats_new_seen';

typedef WhatsNewItem = (IconData, String, String);

const releases = <(String, List<WhatsNewItem>)>[
  ('2.0', [
    (Icons.touch_app_rounded, 'Đọc êm hơn',
        'Chạm để ẩn/hiện thanh công cụ. Muốn sửa bản dịch thì NHẤN GIỮ vào từ.'),
    (Icons.format_list_bulleted_rounded, 'Mục lục ngay trong chương',
        'Nút mục lục trên thanh trên, mở ra là thấy chương đang đọc.'),
    (Icons.bookmarks_rounded, 'Tủ truyện gộp một chỗ',
        'Truyện đang đọc và truyện bấm Theo dõi nằm chung, kèm số chương đã dịch.'),
    (Icons.self_improvement_rounded, 'Tu Tiên thật',
        'Động Phủ, Bí Cảnh, Thành Tựu cho tu vi thật. Thêm 5 bậc Siêu Thoát tới Vô Thượng Chí Tôn.'),
    (Icons.palette_rounded, 'Giao diện giấy dó · 5 bộ màu',
        'Nền giấy, chữ mực, chế độ Mực đêm. Đổi màu chủ đạo ở Tôi → Giao diện.'),
    (Icons.notifications_rounded, 'Tab Thông báo',
        'Chương mới của truyện theo dõi báo ở tab riêng. Cài đặt đổi thành tab Tôi.'),
  ]),
  ('2.0.2', [
    (Icons.wallpaper_rounded, 'Chọn nền cho cả app',
        'Tôi → Giao diện: Giấy dó, Trắng ngà, Tuyết, Trúc — có cả bản sáng lẫn tối.'),
    (Icons.text_fields_rounded, 'Cài đặt đọc gọn hơn',
        'Nút Aa trên thanh đọc. Hiện đủ 15 màu nền; căn đều và gạch chân thuật ngữ thành công tắc.'),
    (Icons.cloud_off_rounded, 'Font đọc có sẵn, không cần mạng',
        'Literata, Lora, Merriweather, Playfair Display, Be Vietnam Pro đã nằm trong app.'),
  ]),
];

/// Các bản phát hành máy này CHƯA xem, cũ trước mới sau. [seen] null = chưa xem bản nào.
List<(String, List<WhatsNewItem>)> unseenReleases(String? seen) {
  final i = releases.indexWhere((r) => r.$1 == seen);
  return releases.sublist(i + 1); // không thấy (-1) → tất cả
}

Future<void> maybeShowWhatsNew(BuildContext context) async {
  final seen = prefs.getString(_key);
  final latest = releases.last.$1;
  if (seen == latest) return;
  // người dùng cũ: từng xem bảng này, hoặc có cờ 'guide_offered' của máy chạy 1.x
  final existing = seen != null || prefs.getBool('guide_offered') == true;
  await prefs.setString(_key, latest);
  if (!existing || !context.mounted) return;
  final unseen = unseenReleases(seen);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WhatsNewSheet(
      version: latest,
      // mới nhất lên đầu
      items: [for (final r in unseen.reversed) ...r.$2],
    ),
  );
}

class WhatsNewSheet extends StatelessWidget {
  final String version;
  final List<WhatsNewItem> items;
  const WhatsNewSheet({super.key, required this.version, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Gác Truyện $version', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Có gì mới', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),
            for (final (icon, title, desc) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: cs.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(desc, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vào đọc thôi'),
            ),
          ],
        ),
      ),
    );
  }
}
