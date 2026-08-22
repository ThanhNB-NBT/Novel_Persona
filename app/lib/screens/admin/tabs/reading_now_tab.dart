import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data.dart';
import 'shared.dart';

// ---------------- Đang đọc: truyện có reader gần đây (bám ưu tiên dịch) ----------------
class ReadingNowTab extends ConsumerWidget {
  const ReadingNowTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AdminRefreshable(
      async: ref.watch(readingNowProvider),
      onRefresh: () async => ref.invalidate(readingNowProvider),
      emptyText: 'Không có ai đang đọc (8 giờ qua).',
      builder: (rows) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = rows[i];
          final novel = (r['novels'] as Map?) ?? const {};
          final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện #${r['novel_id']}';
          return ListTile(
            leading: Icon(Icons.menu_book_outlined, color: cs.primary),
            title: Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
            subtitle: Text('Đang đọc chương ${r['chapter_index']} · ${elapsed(r['updated_at'])} trước',
                style: t.labelSmall),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/admin/novel/${r['novel_id']}'),
          );
        },
      ),
    );
  }
}
