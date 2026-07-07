import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Thông báo: chương truyện trong tủ sách vừa dịch xong — gộp theo truyện,
/// bấm mở đọc chương mới nhất. Màn riêng (đủ cao) thay cho hiển thị đè menubar.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: items.when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text('Chưa có thông báo nào.\nChương truyện trong tủ dịch xong sẽ hiện ở đây.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          // gộp theo truyện, giữ thứ tự mới nhất trước
          final groups = <int, List<Rec>>{};
          for (final c in list) {
            (groups[c['novel_id'] as int] ??= []).add(c);
          }
          final entries = groups.entries.toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const RowDivider(),
              itemBuilder: (_, i) => _NovelDone(entries[i].value),
            ),
          );
        },
      ),
    );
  }
}

class _NovelDone extends StatelessWidget {
  final List<Rec> chapters; // các chương của 1 truyện (mới → cũ)
  const _NovelDone(this.chapters);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final novel = (chapters.first['novels'] as Map?) ?? const {};
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện';
    final novelId = chapters.first['novel_id'];
    final latest =
        chapters.map((c) => c['chapter_index'] as int).reduce((a, b) => a > b ? a : b);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/novel/$novelId/read/$latest'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Cover(url: novel['cover_url'], width: 44, aspect: 1.36, label: '$title'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 2),
              Text('${chapters.length} chương mới dịch xong · mới nhất chương $latest',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(timeAgo(chapters.first['translated_at']),
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
