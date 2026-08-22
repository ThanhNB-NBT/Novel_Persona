import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cultivation.dart';
import '../../../data.dart';
import '../../../widgets.dart';
import '../../cultivation/pixel.dart';
import 'shared.dart';

// ---------------- Tu Tiên: catalog vật phẩm ----------------

/// Kho vật phẩm hệ thống tu tiên: toàn bộ catalog nhóm theo loại — soi nhanh
/// tên/phẩm/trọng số rơi/hiệu ứng khi cân bằng game. Chỉ xem (seed nằm trong
/// migration 039, đổi số liệu thì sửa migration mới).
class CultTab extends ConsumerWidget {
  const CultTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return AdminRefreshable(
      async: ref.watch(cultCatalogProvider),
      onRefresh: () async => ref.invalidate(cultCatalogProvider),
      emptyText: 'Catalog trống — migration 039 đã chạy chưa?',
      builder: (items) {
        // nhóm theo loại, giữ thứ tự khai báo trong cultTypeNames
        final byType = <String, List<Rec>>{};
        for (final it in items) {
          byType.putIfAbsent(it['type'] as String, () => []).add(it);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Text('${items.length} vật phẩm trong catalog',
                style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            // thu gọn theo loại — catalog ~90 món, trải phẳng cuộn mỏi tay
            for (final type in cultTypeNames.keys)
              if (byType[type] case final list?)
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: const Border(), // bỏ viền mặc định lúc mở cho đỡ rối
                  title: Text(
                      '${cultTypeNames[type]!.toUpperCase()} (${list.length})',
                      style: t.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant, letterSpacing: 0.8)),
                  children: [
                for (final it in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                      child: Row(children: [
                        PixelIcon(it['pixel'] as String,
                            grade: it['grade'] as int, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(it['name'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 6),
                                  TagChip(
                                      gradeNames[(it['grade'] as int) - 1],
                                      color:
                                          gradeColor(it['grade'] as int)),
                                ]),
                                Text(cultEffectText(it),
                                    style: t.labelMedium
                                        ?.copyWith(color: cs.onSurface)),
                                Text(it['descr'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant)),
                              ]),
                        ),
                        const SizedBox(width: 8),
                        // trọng số rơi — to = dễ rơi (trong nhóm phẩm được phép)
                        Column(children: [
                          Text('${it['weight']}',
                              style: t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurfaceVariant)),
                          Text('rơi',
                              style: t.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ]),
                      ]),
                    ),
                  ),
                  ],
                ),
          ],
        );
      },
    );
  }
}
