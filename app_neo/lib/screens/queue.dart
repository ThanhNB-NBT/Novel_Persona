import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Tab Hàng đợi — tiến độ dịch theo chương (logic port từ app cũ).
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(translateQueueProvider);
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('HÀNG ĐỢI', style: Neo.mono(10, color: Neo.cyan, spacing: 3)),
            const SizedBox(height: 2),
            Text('Tiến trình dịch', style: Neo.display(28)),
          ]),
        ),
        Expanded(
          child: q.when(
            loading: () => const NeoLoading(label: 'Đang tải hàng đợi…'),
            error: (e, _) => NeoMessage('Lỗi: $e', error: true),
            data: (state) => RefreshIndicator(
              color: Neo.cyan,
              backgroundColor: Neo.surface,
              onRefresh: () async => ref.invalidate(translateQueueProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  _Summary(state),
                  const SizedBox(height: 8),
                  if (state.active.isEmpty && state.recentDone.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: NeoMessage('HÀNG ĐỢI TRỐNG\nCHƯA CÓ CHƯƠNG NÀO ĐANG XỬ LÝ'),
                    )
                  else ...[
                    for (final g in _groupByNovel(state.active))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _NovelQueueCard(g),
                      ),
                    if (state.recentDone.isNotEmpty) _RecentDone(state.recentDone),
                  ],
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

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
    isScrollControlled: true,
    backgroundColor: Neo.surface,
    shape: const Border(top: BorderSide(color: Neo.cyan, width: 1)),
    builder: (ctx) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('$title',
                  style: Neo.display(17, weight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const NeoDivider(),
                itemBuilder: (_, i) {
                  final c = items[i];
                  final st = c['translation_status'];
                  final (label, color) = switch (st) {
                    'translating' => ('Đang dịch', Neo.cyan),
                    'downloading' => ('Đang tải về', Neo.plasma),
                    _ => ('Chờ dịch', Neo.dim),
                  };
                  return ListTile(
                    dense: true,
                    leading: st == 'translating'
                        ? const SizedBox(width: 40, child: HudProgress())
                        : Icon(
                            st == 'downloading' ? Icons.cloud_download : Icons.schedule,
                            size: 18, color: color),
                    title: Text('Chương ${c['chapter_index']}',
                        style: const TextStyle(color: Neo.text, fontSize: 14)),
                    subtitle: c['title_vi'] != null
                        ? Text('${c['title_vi']}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Neo.mono(10))
                        : null,
                    trailing: Text(label,
                        style: Neo.mono(9, color: color, weight: FontWeight.w700, spacing: 1.5)),
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
  final List<Rec> chapters = [];
  final List<int> translating = [];
  final List<int> downloadingIdx = [];
  final List<int> queuedIdx = [];
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
    final translating =
        s.active.where((c) => c['translation_status'] == 'translating').length;
    final queued = s.active.length - translating;
    Widget cell(String v, String label, Color c) => Expanded(
          child: Column(children: [
            Text(v, style: Neo.display(20, color: c)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(), style: Neo.mono(8, spacing: 2)),
          ]),
        );
    return NeoPanel(
      padding: const EdgeInsets.symmetric(vertical: 14),
      glowColor: translating > 0 ? Neo.cyan : null,
      borderColor: translating > 0 ? Neo.cyan.withValues(alpha: 0.35) : Neo.faint,
      child: Row(children: [
        cell('${s.doneLastHour}', 'chương/giờ', Neo.cyan),
        Container(width: 1, height: 30, color: Neo.faint),
        cell('$translating', 'đang dịch', Neo.text),
        Container(width: 1, height: 30, color: Neo.faint),
        cell('$queued', 'đang chờ', Neo.text),
      ]),
    );
  }
}

class _NovelQueueCard extends StatelessWidget {
  final _NovelGroup g;
  const _NovelQueueCard(this.g);

  @override
  Widget build(BuildContext context) {
    final title = g.novel['title_vi'] ?? g.novel['title_zh'] ?? 'Truyện';
    final done = (g.novel['chapter_count_translated'] ?? 0) as int;
    final total = (g.novel['chapter_count_source'] ?? 0) as int;
    final busy = g.translating.isNotEmpty;
    final loading = g.downloading > 0;

    final parts = <String>[
      if (g.translating.length == 1) 'Đang dịch chương ${g.translating.first}'
      else if (g.translating.length > 1) 'Đang dịch ${g.translating.length} chương',
      if (loading) g.downloadingText,
      if (g.queued > 0) g.queuedText,
    ];
    final status = parts.isEmpty ? 'Trong hàng đợi' : parts.join(' · ');
    final accent = busy ? Neo.cyan : (loading ? Neo.plasma : Neo.dim);

    return NeoTapGlow(
      onTap: () => _showChapters(context, g),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: Neo.surface,
          shape: NeoCutBorder(
              cut: Neo.cutSm,
              side: BorderSide(color: busy ? Neo.cyan.withValues(alpha: 0.4) : Neo.faint)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NeoCover(url: g.novel['cover_url'], width: 46, aspect: 1.36, label: '$title'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Neo.display(15, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [
                if (busy)
                  const SizedBox(width: 34, child: HudProgress())
                else
                  Icon(loading ? Icons.cloud_download : Icons.schedule,
                      size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(status,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Neo.mono(10, color: accent, weight: FontWeight.w600)),
                ),
              ]),
              if (total > 0) ...[
                const SizedBox(height: 10),
                HudProgress(value: (done / total).clamp(0, 1).toDouble()),
                const SizedBox(height: 4),
                Text('$done / $total chương đã dịch', style: Neo.mono(9, spacing: 1.5)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

String _ago(Object? iso) {
  if (iso == null) return '';
  final d = DateTime.now().toUtc().difference(DateTime.parse('$iso').toUtc());
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  return '${d.inHours} giờ trước';
}

class _RecentDone extends ConsumerWidget {
  final List<Rec> items;
  const _RecentDone(this.items);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <int, List<Rec>>{};
    for (final c in items) {
      (groups[c['novel_id'] as int] ??= []).add(c);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 0, 6),
        child: Row(children: [
          const Icon(Icons.check_circle, size: 16, color: Neo.cyan),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Vừa dịch xong',
                  style: Neo.mono(11, color: Neo.text, weight: FontWeight.w700, spacing: 2))),
          TextButton.icon(
            onPressed: () async {
              await clearQueueDone();
              ref.invalidate(translateQueueProvider);
            },
            icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Neo.dim),
            label: Text('Xoá', style: Neo.mono(10, spacing: 1.5)),
          ),
        ]),
      ),
      for (final e in groups.entries) _DoneNovel(e.value),
    ]);
  }
}

class _DoneNovel extends StatelessWidget {
  final List<Rec> chapters;
  const _DoneNovel(this.chapters);
  @override
  Widget build(BuildContext context) {
    final novel = (chapters.first['novels'] as Map?) ?? const {};
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện';
    final novelId = chapters.first['novel_id'];
    final latest =
        chapters.map((c) => c['chapter_index'] as int).reduce((a, b) => a > b ? a : b);
    return InkWell(
      onTap: () => context.push('/novel/$novelId/read/$latest'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          NeoCover(url: novel['cover_url'], width: 40, aspect: 1.36, label: '$title'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Neo.text, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${chapters.length} chương vừa dịch · mới nhất ch.$latest',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Neo.mono(10)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(_ago(chapters.first['translated_at']), style: Neo.mono(9)),
        ]),
      ),
    );
  }
}
