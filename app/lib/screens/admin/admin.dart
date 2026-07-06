import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Màn Quản trị (chỉ admin vào được — RLS + isAdminProvider chặn ở cả 2 đầu).
/// 4 tab: Worker (hàng đợi/lỗi), Truyện (ẩn/sửa), Token (chi phí LLM), Báo cáo.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(isAdminProvider);
    return admin.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Lỗi: $e'))),
      data: (ok) {
        if (!ok) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quản trị')),
            body: const Center(child: Text('Bạn không có quyền quản trị.')),
          );
        }
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Quản trị'),
              actions: [
                IconButton(
                  tooltip: 'Quét lỗi dịch (chương còn tiếng Trung / cụt / mất đoạn)',
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await requestAudit();
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Đã bắt đầu quét — chương lỗi sẽ tự '
                              'xếp lại dịch, xem tab Worker.')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  },
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Worker'),
                  Tab(text: 'Đang đọc'),
                  Tab(text: 'Truyện'),
                  Tab(text: 'Token'),
                  Tab(text: 'Báo cáo'),
                ],
              ),
            ),
            body: const TabBarView(children: [
              _JobsTab(),
              _ReadingNowTab(),
              _NovelsTab(),
              _TokensTab(),
              _ReportsTab(),
            ]),
          ),
        );
      },
    );
  }
}

/// Bọc 1 provider list: loading/error/empty + kéo làm mới.
class _Refreshable extends StatelessWidget {
  final AsyncValue<List<Rec>> async;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final Widget Function(List<Rec>) builder;
  const _Refreshable(
      {required this.async,
      required this.onRefresh,
      required this.emptyText,
      required this.builder});

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
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

// ---------------- Worker: hàng đợi + job lỗi ----------------
class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Refreshable(
      async: ref.watch(adminJobsProvider),
      onRefresh: () async => ref.invalidate(adminJobsProvider),
      emptyText: 'Không có job đang chạy / chờ / lỗi.',
      builder: (jobs) {
        final running = jobs.where((j) => j['status'] == 'running').length;
        final pending = jobs.where((j) => j['status'] == 'pending').length;
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
              ? _JobStats(running: running, pending: pending, failed: failed)
              : _NovelJobsRow(entries[i - 1].key, entries[i - 1].value, ref),
        );
      },
    );
  }
}

/// Thống kê nhanh hàng đợi worker: đang dịch / chờ / lỗi (từ chính list job đã tải).
class _JobStats extends StatelessWidget {
  final int running, pending, failed;
  const _JobStats({required this.running, required this.pending, required this.failed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
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
        child: Row(children: [
          cell('$running', 'đang dịch', cs.primary),
          cell('$pending', 'đang chờ', null),
          cell('$failed', 'lỗi', failed > 0 ? cs.error : null),
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
    final pending = jobs.where((j) => j['status'] == 'pending').length;
    final failed = jobs.where((j) => j['status'] == 'failed').length;
    final parts = [
      if (running > 0) '$running đang dịch',
      if (pending > 0) '$pending chờ',
      if (failed > 0) '$failed lỗi',
    ];
    final (icon, color) = failed > 0
        ? (Icons.error_outline, cs.error)
        : running > 0
            ? (Icons.sync_rounded, cs.primary)
            : (Icons.schedule_rounded, cs.onSurfaceVariant);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
      subtitle: Text(parts.join(' · '), style: t.labelSmall),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _showNovelJobs(context, ref, novelId, title),
    );
  }
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
      _priorityLabel(j['priority'] as int),
      if ((j['attempts'] ?? 0) > 0) '${j['attempts']} lần thử',
      // Đang chạy → khoe thời gian đã chạy (token chỉ có khi dịch xong, ghi 1 lần ở cuối).
      if (status == 'running' && j['started_at'] != null) 'chạy ${_elapsed(j['started_at'])}',
    ].join(' · ');
    final color = switch (status) {
      'failed' => cs.error,
      'running' => cs.primary,
      _ => cs.onSurfaceVariant,
    };

    return ListTile(
      leading: Icon(
          switch (status) {
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
          if (v == 'retry') await retryJob(id);
          if (v == 'top') await reprioritizeJob(id, 1);
          if (v == 'cancel') await cancelJob(id, j['chapter_id'] as int?);
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

// ---------------- Đang đọc: truyện có reader gần đây (bám ưu tiên dịch) ----------------
class _ReadingNowTab extends ConsumerWidget {
  const _ReadingNowTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _Refreshable(
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
            subtitle: Text('Đang đọc chương ${r['chapter_index']} · ${_elapsed(r['updated_at'])} trước',
                style: t.labelSmall),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/admin/novel/${r['novel_id']}'),
          );
        },
      ),
    );
  }
}

/// priority nhỏ = ưu tiên cao (schema). Hiện bằng chữ cho đỡ nhầm với số chương.
String _priorityLabel(int p) =>
    p <= 1 ? 'ưu tiên cao nhất' : (p < 100 ? 'ưu tiên cao' : 'ưu tiên thường');

/// "2 phút", "1 giờ 5 phút"… từ mốc thời gian ISO tới giờ.
String _elapsed(String isoStart) {
  final d = DateTime.now().toUtc().difference(DateTime.parse(isoStart).toUtc());
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (h == 0) return '$m phút';
  if (h >= 24) return '${d.inDays} ngày'; // mốc cũ (chương mới, lần OK) — khỏi "49 giờ"
  return '$h giờ $m phút';
}

// ---------------- Truyện: tìm + ẩn/hiện + sửa + xoá ----------------
class _NovelsTab extends ConsumerStatefulWidget {
  const _NovelsTab();
  @override
  ConsumerState<_NovelsTab> createState() => _NovelsTabState();
}

class _NovelsTabState extends ConsumerState<_NovelsTab> {
  String _q = '';
  int _filter = 0; // 0 = tất cả, 1 = đang hiển thị, 2 = đã ẩn

  @override
  Widget build(BuildContext context) {
    return _Refreshable(
      async: ref.watch(adminNovelsProvider),
      onRefresh: () async {
        ref.invalidate(adminNovelsProvider);
        ref.invalidate(appStatsProvider);
      },
      emptyText: 'Chưa có truyện nào.',
      builder: (novels) {
        // lọc client-side trên 200 truyện đã tải — đủ nhanh, khỏi query
        final q = _q.trim().toLowerCase();
        final list = q.isEmpty
            ? novels
            : novels.where((n) =>
                '${n['title_vi'] ?? ''} ${n['title_zh'] ?? ''} ${n['author_vi'] ?? ''}'
                    .toLowerCase()
                    .contains(q)).toList();
        // nút phân loại: tất cả / đang hiển thị / đã ẩn
        final nVisible = list.where((n) => n['hidden'] != true).length;
        final nHidden = list.length - nVisible;
        final shown = switch (_filter) {
          1 => list.where((n) => n['hidden'] != true).toList(),
          2 => list.where((n) => n['hidden'] == true).toList(),
          _ => list,
        };
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: shown.length + 1,
          separatorBuilder: (_, i) =>
              i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i > 0) return _NovelRow(shown[i - 1], ref);
            // item 0 = thống kê + ô tìm + chip phân loại
            return Column(children: [
                const _StatsCard(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Tìm truyện (tên Việt/Trung, tác giả)…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => setState(() => _q = '')),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    for (final (i, label) in [
                      'Tất cả (${list.length})',
                      'Hiển thị ($nVisible)',
                      'Đã ẩn ($nHidden)',
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == i,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _filter = i),
                      ),
                    ],
                  ]),
                ),
              ]);
          },
        );
      },
    );
  }
}

/// Thống kê toàn app: lưới 2×4 con số lớn — nhìn 1 phát biết kho đang thế nào.
class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(appStatsProvider).value;
    if (s == null) return const SizedBox(height: 8);

    Widget cell(String v, String label, {Color? color}) => Expanded(
          child: Column(children: [
            Text(v, style: t.headlineSmall?.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: t.labelSmall, textAlign: TextAlign.center),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Row(children: [
            cell(_fmt(s['visible'] ?? 0), 'truyện hiện', color: cs.primary),
            cell(_fmt(s['novels'] ?? 0), 'tổng bản ghi'),
            cell(_fmt(s['completed'] ?? 0), 'hoàn thành'),
            cell(_fmt(s['metaPending'] ?? 0), 'chờ dịch tên',
                color: (s['metaPending'] ?? 0) > 0 ? cs.tertiary : null),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            cell(_fmt(s['done'] ?? 0), 'chương đã dịch', color: cs.primary),
            cell(_fmt(s['chapters'] ?? 0), 'chương đã sync'),
            cell(_fmt(s['doneToday'] ?? 0), 'dịch hôm nay'),
            cell(_fmt(s['failed'] ?? 0), 'chương lỗi',
                color: (s['failed'] ?? 0) > 0 ? cs.error : null),
          ]),
        ]),
      ),
    );
  }
}

class _NovelRow extends StatelessWidget {
  final Rec n;
  final WidgetRef ref;
  const _NovelRow(this.n, this.ref);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = n['title_vi'] ?? n['title_zh'] ?? 'Truyện #${n['id']}';
    final hidden = n['hidden'] == true;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      leading: Opacity(
        opacity: hidden ? 0.5 : 1, // truyện đã ẩn → bìa mờ đi
        child: Cover(url: n['cover_url'], width: 38, aspect: 1.36, label: title),
      ),
      title: Text(title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: t.titleMedium?.copyWith(
              color: hidden ? cs.onSurfaceVariant : cs.onSurface)),
      subtitle: Text(
        [
          '${n['chapter_count_translated'] ?? 0}/${n['chapter_count_source'] ?? 0} chương',
          if ((n['sources'] as Map?)?['name'] != null) '${(n['sources'] as Map)['name']}',
          n['status'] == 'completed' ? 'hoàn thành' : 'đang ra',
          if (n['source_rank'] != null) 'hạng ${n['source_rank']}',
          if (n['meta_translated'] != true) 'chờ dịch tên',
          if (n['is_canonical'] != true) 'bản trùng',
          if (n['last_chapter_at'] != null) 'chương mới ${_elapsed(n['last_chapter_at'])} trước',
          if (hidden) 'đã ẩn',
        ].join(' · '),
        maxLines: 2, overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: hidden ? 'Hiện lại' : 'Ẩn khỏi Khám phá',
          icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () async {
            await setNovelHidden(n['id'], !hidden);
            ref.invalidate(adminNovelsProvider);
            // Khám phá/trang chủ/tìm kiếm đang cache → invalidate để back ra là mất ngay.
            ref.invalidate(novelsProvider);
            ref.invalidate(homeSectionsProvider);
          },
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _editNovel(context, n, ref);
            if (v == 'delete') _deleteNovel(context, n, ref);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Sửa')),
            const PopupMenuItem(value: 'delete', child: Text('Xoá vĩnh viễn')),
          ],
        ),
      ]),
      // Trong quản trị → xem thông tin DỊCH của chương, không phải trang đọc.
      onTap: () => context.push('/admin/novel/${n['id']}'),
    );
  }

  /// Xoá vĩnh viễn — cascade dọn sạch chương/glossary/tiến độ/tủ/job. Bắt gõ xác nhận
  /// bằng dialog rõ ràng vì không hoàn tác được (ẩn mới là thao tác "mềm" hằng ngày).
  void _deleteNovel(BuildContext context, Rec n, WidgetRef ref) {
    final title = n['title_vi'] ?? n['title_zh'] ?? 'Truyện #${n['id']}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá vĩnh viễn?'),
        content: Text('"$title" cùng TOÀN BỘ chương đã dịch, glossary, tiến độ đọc '
            'sẽ bị xoá — không hoàn tác được.\n\nNếu chỉ muốn giấu khỏi Khám phá, '
            'hãy dùng nút Ẩn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await deleteNovel(n['id'] as int);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(adminNovelsProvider);
              ref.invalidate(appStatsProvider);
              ref.invalidate(homeSectionsProvider);
              messenger.showSnackBar(
                  SnackBar(content: Text('Đã xoá "$title"')));
            },
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
  }

  void _editNovel(BuildContext context, Rec n, WidgetRef ref) {
    final titleVi = TextEditingController(text: n['title_vi'] ?? '');
    final authorVi = TextEditingController(text: n['author_vi'] ?? '');
    String status = n['status'] ?? 'ongoing';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa truyện'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: titleVi,
              decoration: const InputDecoration(labelText: 'Tên tiếng Việt')),
          TextField(
              controller: authorVi,
              decoration: const InputDecoration(labelText: 'Tác giả (Việt)')),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (_, set) => DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Trạng thái'),
              items: const [
                DropdownMenuItem(value: 'ongoing', child: Text('Đang ra')),
                DropdownMenuItem(value: 'completed', child: Text('Hoàn thành')),
                DropdownMenuItem(value: 'hiatus', child: Text('Tạm ngưng')),
              ],
              onChanged: (v) => set(() => status = v ?? 'ongoing'),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () async {
              await updateNovelFields(n['id'], {
                'title_vi': titleVi.text.trim(),
                'author_vi': authorVi.text.trim(),
                'status': status,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(adminNovelsProvider);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Token: chi phí LLM theo model ----------------
class _TokensTab extends ConsumerWidget {
  const _TokensTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final health = ref.watch(modelHealthProvider).value ?? const <Rec>[];
    return _Refreshable(
      async: ref.watch(tokenUsageProvider),
      onRefresh: () async {
        ref.invalidate(tokenUsageProvider);
        ref.invalidate(modelHealthProvider);
      },
      emptyText: 'Chưa có dữ liệu token.',
      builder: (rows) {
        int sumP = 0, sumC = 0, sumCh = 0;
        for (final r in rows) {
          sumP += (r['prompt_tokens'] ?? 0) as int;
          sumC += (r['completion_tokens'] ?? 0) as int;
          sumCh += (r['chapters'] ?? 0) as int;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                _stat(context, _fmt(sumP + sumC), 'token tổng', cs.primary),
                Container(width: 1, height: 30, color: cs.outlineVariant),
                _stat(context, _fmt(sumCh), 'chương dịch', null),
              ]),
            ),
            const SizedBox(height: 8),
            Text('NVIDIA NIM + OpenRouter (:free) = \$0 · chỉ token Fireworks mới tính phí.',
                style: t.labelSmall),
            const SizedBox(height: 12),
            for (final r in rows) _tokenRow(context, r),
            if (health.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('SỨC KHỎE MODEL',
                  style: t.labelSmall?.copyWith(letterSpacing: 1.5, color: cs.primary)),
              const SizedBox(height: 8),
              for (final h in health) _healthRow(context, h),
            ],
          ],
        );
      },
    );
  }

  Widget _stat(BuildContext c, String v, String label, Color? color) => Expanded(
        child: Column(children: [
          Text(v, style: Theme.of(c).textTheme.headlineSmall?.copyWith(color: color)),
          Text(label, style: Theme.of(c).textTheme.bodySmall),
        ]),
      );

  Widget _tokenRow(BuildContext context, Rec r) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r['model_used'] ?? '(?)', style: t.titleSmall),
        const SizedBox(height: 2),
        Text('${_fmt(r['chapters'] ?? 0)} chương · vào ${_fmt(r['prompt_tokens'] ?? 0)} · '
            'ra ${_fmt(r['completion_tokens'] ?? 0)}',
            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// 1 dòng sức khỏe model: chấm màu sống/chậm/chết + latency TB + % OK + lần OK cuối.
  Widget _healthRow(BuildContext context, Rec h) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ok = (h['ok_count'] ?? 0) as int;
    final fail = (h['fail_count'] ?? 0) as int;
    final total = ok + fail;
    final rate = total > 0 ? ok / total : 0.0;
    final avgMs = ok > 0 ? (h['total_latency_ms'] ?? 0) / ok : 0.0;
    final lastOk = h['last_ok_at'] as String?;
    final (dot, label) = (rate < 0.5 || lastOk == null)
        ? (cs.error, 'chết')
        : (avgMs > 90000 || rate < 0.85)
            ? (cs.tertiary, 'chậm')
            : (cs.primary, 'sống');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(width: 10, height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['model'] ?? '(?)', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
            const SizedBox(height: 2),
            Text('${(avgMs / 1000).toStringAsFixed(1)}s TB · ${(rate * 100).round()}% OK '
                '($ok/$total)${lastOk != null ? ' · OK ${_elapsed(lastOk)} trước' : ' · chưa OK'}',
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            if (label == 'chết' && h['last_error'] != null)
              Text('${h['last_error']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: cs.error)),
          ]),
        ),
        Text(label, style: t.labelMedium?.copyWith(color: dot, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Màn quản trị 1 truyện: thông tin SAU DỊCH theo từng chương (trạng thái, model,
/// token, thời điểm dịch) + nút yêu cầu dịch. KHÔNG phải trang đọc.
class AdminNovelScreen extends ConsumerWidget {
  final int novelId;
  const AdminNovelScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novel = ref.watch(novelProvider(novelId)).value;
    final chapters = ref.watch(adminChaptersProvider(novelId));
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = novel?['title_vi'] ?? novel?['title_zh'] ?? 'Truyện #$novelId';

    return Scaffold(
      appBar: AppBar(
        title: Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Yêu cầu dịch',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () => translateRangeDialog(context, ref, novelId,
                translated: (novel?['chapter_count_translated'] ?? 0) as int,
                source: (novel?['chapter_count_source'] ?? 0) as int,
                onDone: () => ref.invalidate(adminChaptersProvider(novelId))),
          ),
          IconButton(
            tooltip: 'Huỷ toàn bộ chương đang chờ dịch',
            icon: const Icon(Icons.playlist_remove_rounded),
            onPressed: () async {
              await cancelNovelQueue(novelId);
              ref.invalidate(adminChaptersProvider(novelId));
              ref.invalidate(translateQueueProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã huỷ các chương đang chờ dịch')));
              }
            },
          ),
        ],
      ),
      body: chapters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminChaptersProvider(novelId)),
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = list[i];
              final st = c['translation_status'] as String;
              final tok = (c['prompt_tokens'] ?? 0) + (c['completion_tokens'] ?? 0);
              final info = [
                if (c['model_used'] != null) c['model_used'],
                if (tok > 0) '${_fmt(tok)} token',
                if (c['translated_at'] != null) _date(c['translated_at']),
              ].join(' · ');
              return ListTile(
                dense: true,
                leading: _statusDot(cs, st),
                title: Text('${c['chapter_index']}. ${c['title_vi'] ?? '(chưa có tên)'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                subtitle: info.isEmpty
                    ? Text(_statusText(st), style: t.labelSmall)
                    : Text('${_statusText(st)} · $info', style: t.labelSmall),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusDot(ColorScheme cs, String st) {
    final c = switch (st) {
      'done' => cs.primary,
      'translating' => cs.tertiary,
      'failed' => cs.error,
      'queued' => cs.secondary,
      _ => cs.outlineVariant,
    };
    return Container(width: 10, height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  String _statusText(String st) => switch (st) {
        'done' => 'Đã dịch',
        'translating' => 'Đang dịch',
        'queued' => 'Trong hàng đợi',
        'failed' => 'Lỗi',
        _ => 'Chưa dịch',
      };

  String _date(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Chèn dấu chấm phân cách hàng nghìn (12345 → 12.345). Đủ cho số token.
String _fmt(Object n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

// ---------------- Báo cáo term dịch sai ----------------
class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _Refreshable(
      async: ref.watch(reportsProvider),
      onRefresh: () async => ref.invalidate(reportsProvider),
      emptyText: 'Không có báo cáo nào chờ xử lý.',
      builder: (reports) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = reports[i];
          final term = (r['glossary_terms'] as Map?) ?? const {};
          final novel = (r['novels'] as Map?) ?? const {};
          final termText = term.isEmpty
              ? '(term đã bị xoá)'
              : '${term['term_zh'] ?? '(?)'} → ${term['correct_vi']}';
          return ListTile(
            title: Text(termText, style: t.titleMedium),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r['reason'] != null && '${r['reason']}'.isNotEmpty)
                Text('Lý do: ${r['reason']}',
                    style: t.labelSmall?.copyWith(color: cs.error)),
              Text(novel['title_vi'] ?? novel['title_zh'] ?? '', style: t.labelSmall),
            ]),
            trailing: IconButton(
              tooltip: 'Đánh dấu đã xử lý',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () async {
                await resolveReport(r['id']);
                ref.invalidate(reportsProvider);
              },
            ),
            onTap: r['novel_id'] == null
                ? null
                : () => context.push('/novel/${r['novel_id']}/glossary'),
          );
        },
      ),
    );
  }
}
