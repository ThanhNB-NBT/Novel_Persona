import 'dart:async';

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
          tooltip: 'Yêu cầu truyện mới',
          icon: const Icon(Icons.travel_explore_rounded),
          onPressed: () => showRequestSheet(context),
        ),
        IconButton(
          tooltip: 'Bản offline',
          icon: const Icon(Icons.download_done_rounded),
          onPressed: () => context.push('/offline'),
        ),
        IconButton(
          tooltip: 'Thông báo',
          // chấm đỏ khi có chương dịch xong chưa xem (từ lần mở màn Thông báo trước)
          icon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.notifications_none_rounded),
            if (ref.watch(unseenNotifProvider).value ?? false)
              Positioned(
                right: -1, top: -1,
                child: Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ]),
          onPressed: () async {
            await context.push('/notifications');
            ref.invalidate(unseenNotifProvider); // vừa xem xong → tắt chấm
          },
        ),
        const SizedBox(width: 4),
      ]),
      body: reading.when(
        loading: () => const SkeletonList(),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(readingProvider)),
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
    // Đọc đuổi: nguồn ra chương mới SAU lần đọc gần nhất → chip báo. Worker tự dịch
    // sẵn (queue_followed_new_chapters) nên bấm vào là đọc được luôn.
    final lastCh = DateTime.tryParse(n['last_chapter_at'] as String? ?? '');
    final readAt = DateTime.tryParse(n['read_at'] as String? ?? '');
    final hasNew = lastCh != null && readAt != null && lastCh.isAfter(readAt);
    return InkWell(
      onTap: () => context.push(
        '/novel/${n['id']}',
      ), // → trang thông tin (đồng bộ với mọi nơi)
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KHÔNG Hero ở đây: các tab sống chung 1 route (PageView keep-alive),
            // truyện nằm cả ở carousel Khám phá sẽ trùng tag 'cover-id' → crash.
            Cover(url: n['cover_url'], width: 64, aspect: 1.36, label: title),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tên truyện thấp hơn bìa một chút (nhìn như ngang nhau nhưng lệch nhẹ)
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  // Số chương nhỏ, một màu nhạt hơn tên truyện + chip chương mới
                  Row(children: [
                    Text(
                      'Đã đọc $cur${total > 0 ? '/$total' : ''}',
                      style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (hasNew) ...[
                      const SizedBox(width: 8),
                      const TagChip('Chương mới'),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  ProgressRibbon(progress),
                ],
              ),
            ),
            // Cột phải: menu 3 chấm trên, nút Đọc tiếp dưới — thẳng một trục dọc,
            // không chen vào hàng tên truyện nữa (tên được cả bề ngang).
            Column(children: [
              _menu(context, ref),
              IconButton(
                tooltip: 'Đọc tiếp chương $cur',
                visualDensity: VisualDensity.compact,
                // trần icon tam giác, không nền — nhẹ mắt, thẳng trục với 3 chấm
                icon: Icon(Icons.play_arrow_rounded, size: 26, color: cs.primary),
                // Đọc tiếp 1 chạm — vào thẳng chương đang dở, khỏi ghé trang thông tin
                // (tap cả dòng vẫn mở trang thông tin như mọi nơi).
                onPressed: () => context.push('/novel/${n['id']}/read/$cur'),
              ),
            ]),
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

/// Mở sheet "Yêu cầu truyện mới" từ bất kỳ đâu (Tủ truyện, màn tìm kiếm…),
/// `initialQuery` điền sẵn tên đang tìm. Chưa đăng nhập → đưa qua login.
void showRequestSheet(BuildContext context, {String? initialQuery}) {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RequestSheet(initialQuery: initialQuery),
  );
}

/// Sheet "Yêu cầu truyện mới": nhập tên tiếng Việt (worker nhờ LLM đoán tên gốc)
/// hoặc tên tiếng Trung → tìm trên các nguồn có search rồi crawl về + tự vào
/// tủ sách. Poll 5s khi còn yêu cầu đang tìm.
class _RequestSheet extends ConsumerStatefulWidget {
  final String? initialQuery;
  const _RequestSheet({this.initialQuery});
  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  late final _input = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _poll;
  bool _sending = false;

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = _input.text.trim();
    if (q.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await addNovelRequest(q);
      _input.clear();
      ref.invalidate(myNovelRequestsProvider);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final reqs = ref.watch(myNovelRequestsProvider).value ?? const <Rec>[];
    // còn yêu cầu chờ → poll; xong hết → tắt (kể cả tủ sách cũng cần làm mới)
    final waiting = reqs.any((r) => r['status'] == 'pending');
    if (waiting) {
      _poll ??= Timer.periodic(const Duration(seconds: 5), (_) {
        ref.invalidate(myNovelRequestsProvider);
        ref.invalidate(readingProvider);
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
    return Padding(
      // đẩy sheet lên trên bàn phím
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Yêu cầu truyện mới', style: t.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Nhập tên truyện tiếng Việt (Hán-Việt) hoặc tên gốc tiếng Trung. '
              'Hệ thống tự tìm tên gốc, crawl về và thêm vào tủ sách của bạn — '
              'thường xong trong dưới 1 phút.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  autofocus: true,
                  maxLength: 100,
                  decoration: const InputDecoration(
                      counterText: '', hintText: 'vd: Kiếm Lai / 剑来', isDense: true),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Tìm'),
              ),
            ]),
            if (reqs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('YÊU CẦU CỦA BẠN',
                  style: t.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(shrinkWrap: true, children: [
                  for (final r in reqs) _requestRow(context, r),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _requestRow(BuildContext context, Rec r) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final novel = r['novels'] as Map?;
    final (chip, color) = switch (r['status']) {
      'pending' => ('Đang tìm…', cs.primary),
      'done' => ('Đã thêm', const Color(0xFF2E9E5B)),
      'notfound' => ('Không nguồn nào có', cs.error),
      _ => ('Lỗi', cs.error),
    };
    return InkWell(
      // xong rồi thì bấm mở thẳng trang truyện
      onTap: r['status'] == 'done' && r['novel_id'] != null
          ? () => context.push('/novel/${r['novel_id']}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          if (r['status'] == 'pending') ...[
            const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                (novel?['title_vi'] ?? r['query']) as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium,
              ),
              Text('${r['query']} · ${timeAgo(r['created_at'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          TagChip(chip, color: color),
          if (r['status'] != 'pending')
            IconButton(
              tooltip: 'Xoá yêu cầu',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 16, color: cs.onSurfaceVariant),
              onPressed: () async {
                await deleteNovelRequest(r['id'] as int);
                ref.invalidate(myNovelRequestsProvider);
              },
            ),
        ]),
      ),
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
