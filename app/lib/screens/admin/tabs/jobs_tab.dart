import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data.dart';
import 'shared.dart';

// ---------------- Worker: hàng đợi + job lỗi ----------------
class JobsTab extends ConsumerWidget {
  const JobsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminRefreshable(
      async: ref.watch(adminJobsProvider),
      onRefresh: () async {
        ref.invalidate(adminJobsProvider);
        ref.invalidate(workerHeartbeatProvider);
      },
      emptyText: 'Không có job đang chạy / chờ / lỗi.',
      builder: (jobs) {
        final running = jobs.where((j) => j['status'] == 'running').length;
        final crawling = jobs
            .where((j) => j['status'] == 'pending' && j['downloading'] == true &&
                j['source_unavailable'] != true)
            .length;
        final blocked = jobs.where((j) => j['source_unavailable'] == true).length;
        // "chờ dịch" lấy count THẬT từ DB: danh sách này chỉ là cửa sổ 120 job đầu hàng
        // đợi, đếm độ dài nó ra đúng bằng .limit() nên trước đây luôn báo 120.
        final pendingTotal = ref.watch(pendingJobCountProvider).value;
        final pendingHere =
            jobs.where((j) => j['status'] == 'pending').length - crawling - blocked;
        final failed = jobs.where((j) => j['status'] == 'failed').length;
        // Gộp theo truyện: 1 dòng/truyện, bấm vào mới xem list chương (job) bên trong.
        final groups = <int, List<Rec>>{};
        for (final j in jobs) {
          (groups[j['novel_id'] as int] ??= []).add(j);
        }
        // truyện CÓ job đang chạy lên đầu, kế là chờ, lỗi xuống cuối
        int rank(List<Rec> js) => js.any((j) => j['status'] == 'running')
            ? 0
            : js.any((j) => j['status'] == 'pending') ? 1 : 2;
        final entries = groups.entries.toList()
          ..sort((a, b) => rank(a.value) - rank(b.value));
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: entries.length + 1,
          separatorBuilder: (_, i) =>
              i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
          itemBuilder: (_, i) => i == 0
              ? _JobStats(running: running, crawling: crawling,
                  blocked: blocked, pending: pendingTotal ?? pendingHere,
                  shown: jobs.length, failed: failed)
              : _NovelJobsRow(entries[i - 1].key, entries[i - 1].value, ref),
        );
      },
    );
  }
}

/// Thống kê nhanh hàng đợi worker + NHỊP TIM (crawler/translator điểm danh định kỳ
/// vào worker_heartbeat — biết chắc sống hay treo, không phải đoán qua job).
class _JobStats extends ConsumerWidget {
  final int running, crawling, blocked, pending, shown, failed;
  const _JobStats(
      {required this.running, required this.crawling,
       required this.blocked, required this.pending, required this.shown,
       required this.failed});

  Widget _pulse(BuildContext context, List<Rec> beats, String name, String label) =>
      workerPulse(context, beats, name, label);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final beats = ref.watch(workerHeartbeatProvider).value ?? const <Rec>[];
    Widget cell(String v, String label, Color? c) => Expanded(
          child: Column(children: [
            Text(v, style: t.headlineSmall?.copyWith(color: c)),
            const SizedBox(height: 2),
            Text(label, style: t.labelSmall),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Row(children: [
            cell('$running', 'đang dịch', cs.primary),
            cell('$crawling', 'đang crawl', crawling > 0 ? cs.tertiary : null),
            cell('$pending', 'chờ dịch', null),
            cell('$failed', 'lỗi', failed > 0 ? cs.error : null),
          ]),
          if (blocked > 0) ...[
            const SizedBox(height: 10),
            Text('$blocked job thiếu bản gốc, nguồn đang tắt',
                style: t.labelSmall?.copyWith(color: cs.error)),
          ],
          // Nói rõ danh sách bên dưới bị cắt — "đang crawl" cũng chỉ đếm trong cửa sổ này.
          if (pending > shown) ...[
            const SizedBox(height: 8),
            Text('Danh sách hiển thị $shown job đầu hàng đợi',
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(children: [
              _pulse(context, beats, 'crawler', 'Crawler'),
              const SizedBox(height: 6),
              _pulse(context, beats, 'translator', 'Translator'),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 1 dòng/truyện trong tab Worker: đếm đang dịch/chờ/lỗi; bấm mở list job của truyện.
class _NovelJobsRow extends StatelessWidget {
  final int novelId;
  final List<Rec> jobs;
  final WidgetRef ref;
  const _NovelJobsRow(this.novelId, this.jobs, this.ref);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final novel = (jobs.first['novels'] as Map?) ?? const {};
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện #$novelId';
    final running = jobs.where((j) => j['status'] == 'running').length;
    final crawling = jobs
        .where((j) => j['status'] == 'pending' && j['downloading'] == true &&
            j['source_unavailable'] != true)
        .length;
    final blocked = jobs.where((j) => j['source_unavailable'] == true).length;
    final pending =
        jobs.where((j) => j['status'] == 'pending').length - crawling - blocked;
    final failed = jobs.where((j) => j['status'] == 'failed').length;
    // Tiến độ tải nguồn: chương có content_zh (running + pending thường) / tổng.
    final haveSrc = running + pending;
    final totalSrc = haveSrc + crawling;
    final parts = [
      if (running > 0) '$running đang dịch',
      if (crawling > 0) 'nguồn $haveSrc/$totalSrc',
      if (pending > 0) '$pending chờ dịch',
      if (blocked > 0) '$blocked nguồn không khả dụng',
      if (failed > 0) '$failed lỗi',
    ];
    final (icon, color) = failed > 0 || blocked > 0
        ? (Icons.error_outline, cs.error)
        : running > 0
            ? (Icons.sync_rounded, cs.primary)
            : crawling > 0
                ? (Icons.cloud_download_rounded, cs.tertiary)
                : (Icons.schedule_rounded, cs.onSurfaceVariant);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(parts.join(' · '), style: t.labelSmall),
        if (crawling > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: totalSrc > 0 ? haveSrc / totalSrc : null,
                minHeight: 3,
                color: cs.tertiary,
                backgroundColor: cs.tertiary.withValues(alpha: 0.15),
              ),
            ),
          ),
      ]),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'delete') _confirmDeleteNovelFromJobs(context, ref, novelId, '$title');
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'delete', child: Text('Xoá truyện vĩnh viễn')),
        ],
      ),
      onTap: () => _showNovelJobs(context, ref, novelId, title),
    );
  }
}

/// Xoá vĩnh viễn 1 truyện từ tab Worker (truyện chết nguồn, job lỗi mãi) —
/// cùng cascade như tab Truyện, kèm xác nhận vì không hoàn tác được.
void _confirmDeleteNovelFromJobs(
    BuildContext context, WidgetRef ref, int novelId, String title) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá vĩnh viễn?'),
      content: Text('"$title" cùng TOÀN BỘ chương, glossary, tiến độ đọc và job '
          'sẽ bị xoá — không hoàn tác được.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await deleteNovel(novelId);
            if (ctx.mounted) Navigator.pop(ctx);
            ref.invalidate(adminJobsProvider);
            ref.invalidate(translateQueueProvider);
            ref.read(adminNovelsRevProvider.notifier).bump();
            ref.invalidate(appStatsProvider);
            ref.invalidate(homeSectionsProvider);
            messenger.showSnackBar(SnackBar(content: Text('Đã xoá "$title"')));
          },
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
}

/// Sheet list các job (chương) của 1 truyện — Consumer để retry/huỷ xong tự cập nhật.
void _showNovelJobs(BuildContext context, WidgetRef ref, int novelId, String title) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(builder: (ctx, ref, _) {
      final jobs = (ref.watch(adminJobsProvider).value ?? const <Rec>[])
          .where((j) => j['novel_id'] == novelId)
          .toList();
      final t = Theme.of(ctx).textTheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (jobs.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Text('Không còn job nào.'))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _JobRow(jobs[i], ref),
                ),
              ),
          ]),
        ),
      );
    }),
  );
}

class _JobRow extends StatelessWidget {
  final Rec j;
  final WidgetRef ref;
  const _JobRow(this.j, this.ref);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final status = j['status'] as String;
    final novel = (j['novels'] as Map?) ?? const {};
    final chIdx = (j['chapters'] as Map?)?['chapter_index'];
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện #${j['novel_id']}';
    final sub = [
      j['type'],
      if (j['source_unavailable'] == true)
        'nguồn không khả dụng'
      else if (status == 'pending' && j['downloading'] == true)
        'đang crawl nguồn',
      priorityLabel(j['priority'] as int),
      if ((j['attempts'] ?? 0) > 0) '${j['attempts']} lần thử',
      // Đang chạy → khoe thời gian đã chạy (token chỉ có khi dịch xong, ghi 1 lần ở cuối).
      if (status == 'running' && j['started_at'] != null) 'chạy ${elapsed(j['started_at'])}',
    ].join(' · ');
    final color = j['source_unavailable'] == true ? cs.error : switch (status) {
      'failed' => cs.error,
      'running' => cs.primary,
      _ => cs.onSurfaceVariant,
    };

    return ListTile(
      leading: Icon(
          j['source_unavailable'] == true ? Icons.cloud_off_rounded : switch (status) {
            'failed' => Icons.error_outline,
            'running' => Icons.sync_rounded,
            _ => Icons.schedule_rounded,
          },
          color: color),
      title: Text(chIdx != null ? 'Chương $chIdx — $title' : title,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sub, style: t.labelSmall),
        if (status == 'failed' && j['error'] != null)
          Text('${j['error']}',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(color: cs.error)),
        if (status == 'failed' && j['error'] != null)
          Text('Bấm để xem đầy đủ lỗi',
              style: t.labelSmall?.copyWith(
                  color: cs.primary, fontStyle: FontStyle.italic)),
      ]),
      onTap: status == 'failed' && j['error'] != null
          ? () => _showError(context, chIdx, j['error'] as String)
          : null,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final id = j['id'] as int;
          if (v == 'cancel') {
            // dialog trước mọi await → không dùng context qua async gap
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Huỷ job này?'),
                content: const Text(
                    'Job bị xoá khỏi hàng đợi, chương trở về "chưa dịch". '
                    'Không mất gì đã dịch xong — có thể xếp dịch lại bất cứ lúc nào '
                    'từ trang truyện.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Thôi')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Huỷ job')),
                ],
              ),
            );
            if (ok != true) return;
            await cancelJob(id, j['chapter_id'] as int?);
          }
          if (v == 'retry') await retryJob(id);
          if (v == 'top') await reprioritizeJob(id, 1);
          ref.invalidate(adminJobsProvider);
          ref.invalidate(translateQueueProvider); // hàng đợi đọc từ chapters → refetch cho khớp
        },
        itemBuilder: (_) => [
          if (status == 'failed')
            const PopupMenuItem(value: 'retry', child: Text('Chạy lại')),
          const PopupMenuItem(value: 'top', child: Text('Ưu tiên lên đầu')),
          const PopupMenuItem(value: 'cancel', child: Text('Huỷ job')),
        ],
      ),
    );
  }
}

/// Dialog hiện đầy đủ lỗi 1 job (có thể copy) — error DB cắt ở 2000 ký tự.
void _showError(BuildContext context, Object? chIdx, String error) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(chIdx != null ? 'Lỗi chương $chIdx' : 'Lỗi job'),
      content: SingleChildScrollView(child: SelectableText(error)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
      ],
    ),
  );
}
