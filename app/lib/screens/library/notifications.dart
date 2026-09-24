import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Thông báo: chương truyện trong tủ sách vừa dịch xong — gộp theo truyện,
/// bấm mở đọc chương mới nhất. Màn riêng (đủ cao) thay cho hiển thị đè menubar.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    markNotificationsSeen(); // mở màn = đã xem → dập chấm đỏ trên chuông
  }

  void _refresh() {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotifCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(notificationsProvider);
    final list = items.value ?? const <Rec>[];
    // 2.0: là một TAB dưới dock (shell.dart) → header editorial như các tab khác,
    // nền trong suốt lộ tầng khí quyển, chừa đáy cho dock nổi.
    final header = PageHeader(
      'THEO DÕI',
      'Thông báo',
      seal: '訊',
      actions: [
        if (list.isNotEmpty)
          IconButton(
            tooltip: 'Xoá tất cả',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              await dismissAllNotifications(list.map(notifKeyOf));
              _refresh();
            },
          ),
      ],
    );
    if (sb.auth.currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Đăng nhập rồi theo dõi truyện — chương mới dịch xong sẽ báo ở đây.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => context.push('/login'),
                          child: const Text('Đăng nhập'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: items.when(
                loading: () => const AppLoading(),
                error: (e, _) => AppError(
                  e,
                  onRetry: () => ref.invalidate(notificationsProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có thông báo nào.\nTruyện bạn theo dõi (hoặc chương bạn bấm dịch lại) dịch xong sẽ hiện ở đây.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }
                  // gộp theo truyện, giữ thứ tự mới nhất trước
                  final groups = <int, List<Rec>>{};
                  for (final c in list) {
                    (groups[c['novel_id'] as int] ??= []).add(c);
                  }
                  final entries = groups.entries.toList();
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(notificationsProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        110,
                      ), // chừa dock nổi
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const RowDivider(),
                      itemBuilder: (_, i) => _NovelDone(
                        entries[i].value,
                        onDismiss: () async {
                          for (final c in entries[i].value) {
                            await dismissNotification(
                              c['novel_id'] as int,
                              c['chapter_index'] as int,
                            );
                          }
                          _refresh();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NovelDone extends StatelessWidget {
  final List<Rec> chapters; // các chương của 1 truyện (mới → cũ)
  final VoidCallback onDismiss;
  const _NovelDone(this.chapters, {required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final novel = (chapters.first['novels'] as Map?) ?? const {};
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện';
    final novelId = chapters.first['novel_id'];
    final latest = chapters
        .map((c) => c['chapter_index'] as int)
        .reduce((a, b) => a > b ? a : b);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/novel/$novelId/read/$latest'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Cover(
              url: novel['cover_url'],
              width: 44,
              aspect: 1.36,
              label: '$title',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${chapters.length} chương mới dịch xong · mới nhất chương $latest',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // mốc giờ không co: ở 200% nó nuốt hết chỗ của tên truyện → chặn 1.3
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                timeAgo(chapters.first['translated_at']),
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: 'Xoá thông báo này',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
