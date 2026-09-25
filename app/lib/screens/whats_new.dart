import 'package:flutter/material.dart';

import '../data.dart';

/// "Có gì mới ở 2.0" — hiện MỘT lần cho người nâng cấp từ 1.x. Người cài mới không cần
/// (với họ chưa có gì "cũ"), họ đã có lời mời xem Hướng dẫn ở shell.
const _key = 'whats_new_seen';
const _ver = '2.0';

Future<void> maybeShowWhatsNew(BuildContext context) async {
  if (prefs.getString(_key) == _ver) return;
  // 'guide_offered' chỉ có ở máy đã chạy 1.x → dấu hiệu người dùng cũ
  final upgraded = prefs.getBool('guide_offered') == true;
  await prefs.setString(_key, _ver);
  if (!upgraded || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const WhatsNewSheet(),
  );
}

class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key});

  static const items = [
    (Icons.touch_app_rounded, 'Đọc êm hơn',
        'Chạm để ẩn/hiện thanh công cụ. Muốn sửa bản dịch thì NHẤN GIỮ vào từ.'),
    (Icons.format_list_bulleted_rounded, 'Mục lục ngay trong chương',
        'Nút mục lục trên thanh trên, mở ra là thấy chương đang đọc.'),
    (Icons.bookmarks_rounded, 'Tủ truyện gộp một chỗ',
        'Truyện đang đọc và truyện bấm Theo dõi nằm chung, kèm số chương đã dịch.'),
    (Icons.self_improvement_rounded, 'Tu Tiên thật',
        'Động Phủ, Bí Cảnh, Thành Tựu cho tu vi thật. Thêm 5 bậc Siêu Thoát tới Vô Thượng Chí Tôn.'),
    (Icons.palette_rounded, 'Giao diện giấy dó · 5 bộ màu · 4 nền',
        'Nền giấy, chữ mực, chế độ Mực đêm. Đổi màu chủ đạo và nền (Trắng ngà, Tuyết, Trúc) ở Tôi → Giao diện.'),
    (Icons.notifications_rounded, 'Tab Thông báo',
        'Chương mới của truyện theo dõi báo ở tab riêng. Cài đặt đổi thành tab Tôi.'),
  ];

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
            Text('Gác Truyện 2.0', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
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
