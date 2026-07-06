import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Hàng đợi = tiến độ DỊCH theo chương (đồng bộ chung, không chia user):
/// tốc độ gần đây + các truyện đang được dịch, gộp theo truyện kèm tiến độ.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(translateQueueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hàng đợi dịch')),
      body: q.when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (state) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(translateQueueProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), // chừa chỗ dock nổi
            children: [
              _Summary(state),
              const SizedBox(height: 8),
              if (state.active.isEmpty && state.recentDone.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('Hàng đợi trống — chưa có chương nào đang xử lý.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                )
              else ...[
                if (state.active.isNotEmpty) ...[
                  // header đồng kiểu với "Vừa dịch xong" bên dưới
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
                    child: Row(children: [
                      Icon(Icons.hourglass_bottom_rounded,
                          size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Hàng đợi',
                              style: Theme.of(context).textTheme.titleMedium)),
                    ]),
                  ),
                  for (final g in _groupByNovel(state.active)) _NovelQueueCard(g),
                ],
                if (state.recentDone.isNotEmpty) _RecentDone(state.recentDone),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bấm 1 truyện → sheet liệt kê chương đang dịch (lên trước) + chương đang chờ.
void _showChapters(BuildContext context, _NovelGroup g) {
  final title = g.novel['title_vi'] ?? g.novel['title_zh'] ?? 'Truyện';
    int rank(Rec c) => switch (c['translation_status']) {
          'translating' => 0,
          'downloading' => 1,
          _ => 2,
        };
  final items = [...g.chapters]..sort((a, b) => rank(a) != rank(b)
      ? rank(a) - rank(b)
      : (a['chapter_index'] as int).compareTo(b['chapter_index'] as int));
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('$title', style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = items[i];
                  final st = c['translation_status'];
                  final (label, color) = switch (st) {
                    'translating' => ('Đang dịch', cs.primary),
                    'downloading' => ('Đang tải về', cs.tertiary),
                    _ => ('Chờ dịch', cs.onSurfaceVariant),
                  };
                  return ListTile(
                    dense: true,
                    leading: st == 'translating'
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                        : Icon(
                            st == 'downloading'
                                ? Icons.cloud_download_rounded
                                : Icons.schedule_rounded,
                            size: 18, color: color),
                    title: Text('Chương ${c['chapter_index']}', style: t.bodyMedium),
                    subtitle: c['title_vi'] != null
                        ? Text('${c['title_vi']}', maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Text(label,
                        style: t.labelMedium?.copyWith(
                            color: color, fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
          ]),
        ),
      );
    },
  );
}

/// Gộp các chương đang dịch/chờ theo truyện; truyện ĐANG DỊCH lên đầu,
/// kế là đang tải nguồn, đang chờ xuống cuối.
List<_NovelGroup> _groupByNovel(List<Rec> active) {
  final map = <int, _NovelGroup>{};
  for (final c in active) {
    final id = c['novel_id'] as int;
    (map[id] ??= _NovelGroup(id, (c['novels'] as Map?) ?? const {})).add(c);
  }
  int rank(_NovelGroup g) =>
      g.translating.isNotEmpty ? 0 : (g.downloading > 0 ? 1 : 2);
  return map.values.toList()..sort((a, b) => rank(a) - rank(b));
}

class _NovelGroup {
  final int novelId;
  final Map novel;
  final List<Rec> chapters = []; // đủ chương active (để mở list khi bấm vào)
  final List<int> translating = []; // chương đang dịch
  final List<int> downloadingIdx = []; // chương đang tải nguồn về (chưa có content_zh)
  final List<int> queuedIdx = []; // chương đã tải, đang chờ tới lượt dịch
  _NovelGroup(this.novelId, this.novel);

  int get queued => queuedIdx.length;
  int get downloading => downloadingIdx.length;

  void add(Rec c) {
    chapters.add(c);
    final idx = c['chapter_index'] as int;
    switch (c['translation_status']) {
      case 'translating':
        translating.add(idx);
      case 'downloading':
        downloadingIdx.add(idx);
      default:
        queuedIdx.add(idx);
    }
  }

  String get queuedText => _rangeText(queuedIdx, 'chờ dịch');
  String get downloadingText => _rangeText(downloadingIdx, 'đang tải về');

  /// "chờ dịch chương 5" / "chờ dịch 4 chương (5–8)".
  static String _rangeText(List<int> idx, String verb) {
    if (idx.isEmpty) return '';
    final sorted = [...idx]..sort();
    if (sorted.length == 1) return '$verb chương ${sorted.first}';
    return '$verb ${sorted.length} chương (${sorted.first}–${sorted.last})';
  }
}

class _Summary extends StatelessWidget {
  final QueueState s;
  const _Summary(this.s);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final translating = s.active.where((c) => c['translation_status'] == 'translating').length;
    final queued = s.active.length - translating;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        _cell(context, '${s.doneLastHour}', 'chương/giờ', cs.primary),
        _divider(cs),
        _cell(context, '$translating', 'đang dịch', null),
        _divider(cs),
        _cell(context, '$queued', 'đang chờ', null),
      ]),
    );
  }

  Widget _cell(BuildContext context, String v, String label, Color? c) => Expanded(
        child: Column(children: [
          Text(v,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _divider(ColorScheme cs) =>
      Container(width: 1, height: 30, color: cs.outlineVariant);
}

/// Thẻ 1 truyện đang trong hàng đợi: bìa + trạng thái chương + thanh tiến độ dịch
/// (đã dịch / tổng chương). Bấm mở trang truyện.
class _NovelQueueCard extends StatelessWidget {
  final _NovelGroup g;
  const _NovelQueueCard(this.g);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = g.novel['title_vi'] ?? g.novel['title_zh'] ?? 'Truyện';
    final done = (g.novel['chapter_count_translated'] ?? 0) as int;
    final total = (g.novel['chapter_count_source'] ?? 0) as int;
    final busy = g.translating.isNotEmpty;
    final loading = g.downloading > 0;

    // Dòng trạng thái: đang dịch / đang tải nguồn về / còn bao nhiêu chờ.
    final parts = <String>[
      if (g.translating.length == 1) 'Đang dịch chương ${g.translating.first}'
      else if (g.translating.length > 1) 'Đang dịch ${g.translating.length} chương',
      if (loading) g.downloadingText,
      if (g.queued > 0) g.queuedText,
    ];
    final status = parts.isEmpty ? 'Trong hàng đợi' : parts.join(' · ');
    // màu/icon theo trạng thái ưu thế: đang dịch > đang tải > chờ
    final accent = busy ? cs.primary : (loading ? cs.tertiary : cs.onSurfaceVariant);

    // dòng phẳng đồng kiểu "Vừa dịch xong": bìa nhỏ + tên + trạng thái, không đóng khung
    return InkWell(
      onTap: () => _showChapters(context, g), // bấm → list chương đang dịch/chờ của truyện
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Cover(url: g.novel['cover_url'], width: 40, aspect: 1.36, label: title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 2),
              Text(status,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: accent)),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy)
            SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
          else
            Icon(loading ? Icons.cloud_download_rounded : Icons.schedule_rounded,
                size: 16, color: accent),
          if (total > 0) ...[
            const SizedBox(width: 8),
            Text('$done/$total',
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

/// "vừa xong" / "5 phút trước" / "2 giờ trước" từ mốc ISO.
String _ago(Object? iso) {
  if (iso == null) return '';
  final d = DateTime.now().toUtc().difference(DateTime.parse('$iso').toUtc());
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  return '${d.inHours} giờ trước';
}

/// Mục "Vừa dịch xong" — GỘP THEO TRUYỆN (như Quản trị nhưng gọn), có nút Xoá lịch sử.
/// Chỉ là thông báo → "Xoá" chỉ ẩn hiển thị trên máy, không đụng dữ liệu dịch.
class _RecentDone extends ConsumerWidget {
  final List<Rec> items;
  const _RecentDone(this.items);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // gộp theo truyện, giữ thứ tự xuất hiện (mới nhất trước)
    final groups = <int, List<Rec>>{};
    for (final c in items) {
      (groups[c['novel_id'] as int] ??= []).add(c);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 0, 6),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Vừa dịch xong', style: t.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              await clearQueueDone();
              ref.invalidate(translateQueueProvider);
            },
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Xoá'),
          ),
        ]),
      ),
      for (final e in groups.entries) _DoneNovel(e.value),
    ]);
  }
}

/// 1 truyện trong "Vừa dịch xong": bìa + tên + số chương vừa dịch + chương mới nhất.
class _DoneNovel extends StatelessWidget {
  final List<Rec> chapters; // các chương của 1 truyện (mới → cũ)
  const _DoneNovel(this.chapters);
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Cover(url: novel['cover_url'], width: 40, aspect: 1.36, label: '$title'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 2),
              Text('${chapters.length} chương vừa dịch · mới nhất chương $latest',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(_ago(chapters.first['translated_at']),
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
