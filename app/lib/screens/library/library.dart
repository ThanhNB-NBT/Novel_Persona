import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../offline.dart';
import '../../widgets.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(readingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tủ truyện'), actions: [
        IconButton(
          tooltip: 'Bản offline',
          icon: const Icon(Icons.download_done_rounded),
          onPressed: () => context.push('/offline'),
        ),
        IconButton(
          tooltip: 'Thông báo',
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () => context.push('/notifications'),
        ),
        const SizedBox(width: 4),
      ]),
      body: reading.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) {
          if (sb.auth.currentUser == null) {
            return _Empty(
              icon: Icons.login_rounded,
              text: 'Đăng nhập để lưu truyện đang đọc',
              action: FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Đăng nhập'),
              ),
            );
          }
          if (list.isEmpty) {
            return const _Empty(
              icon: Icons.auto_stories_rounded,
              text:
                  'Chưa có truyện đang đọc.\nMở một truyện ở Khám phá để bắt đầu.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(readingProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 110), // chừa chỗ dock nổi
              itemCount: list.length,
              separatorBuilder: (_, _) => const RowDivider(),
              itemBuilder: (_, i) => _ReadingRow(list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReadingRow extends ConsumerWidget {
  final Rec n;
  const _ReadingRow(this.n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cur = (n['cur_chapter'] ?? 1) as int;
    final total = (n['chapter_count_source'] ?? 0) as int;
    final progress = total > 0 ? cur / total : 0.0;
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    return InkWell(
      onTap: () => context.push(
        '/novel/${n['id']}',
      ), // → trang thông tin (đồng bộ với mọi nơi)
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(url: n['cover_url'], width: 58, aspect: 1.36, label: title),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tên truyện thấp hơn bìa một chút (nhìn như ngang nhau nhưng lệch nhẹ)
                  const SizedBox(height: 2),
                  // Tên truyện + menu cùng một hàng
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium,
                        ),
                      ),
                      _menu(context, ref),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Số chương nhỏ, một màu nhạt hơn tên truyện
                  Text(
                    'Đã đọc $cur${total > 0 ? '/$total' : ''}',
                    style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  ProgressRibbon(progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(isDownloadedProvider(n['id'] as int)).value ?? false;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(
        Icons.more_vert_rounded,
        size: 22,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: (v) async {
        if (v == 'offline') {
          await toggleOffline(context, ref, n, downloaded);
        } else if (v == 'remove') {
          await removeReading(n['id']);
          ref.invalidate(readingProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã xóa khỏi Tủ truyện')),
            );
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'offline',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(downloaded
                ? Icons.download_done_rounded
                : Icons.download_for_offline_outlined),
            title: Text(downloaded ? 'Xoá bản offline' : 'Tải truyện về máy'),
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bookmark_remove_outlined),
            title: Text('Xóa khỏi tủ (xóa lịch sử đọc)'),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Empty({required this.icon, required this.text, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: cs.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
