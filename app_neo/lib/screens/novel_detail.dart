import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';
import '../offline.dart';

/// Chi tiết truyện — logic (offline, dịch, tủ sách) port nguyên từ app cũ, khung HUD mới.
class NovelDetailScreen extends ConsumerWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novel = ref.watch(novelProvider(novelId));
    return NeoScaffold(
      body: novel.when(
        loading: () => const NeoLoading(label: 'NẠP HỒ SƠ TRUYỆN'),
        error: (e, _) => NeoMessage('Lỗi: $e', error: true),
        data: (n) => Stack(children: [
          DefaultTabController(
            length: 2,
            child: Column(children: [
              _Header(n, novelId),
              TabBar(
                tabs: const [Tab(text: 'HỒ SƠ'), Tab(text: 'MỤC LỤC')],
                labelStyle: Neo.mono(12, color: Neo.cyan, weight: FontWeight.w700, spacing: 2),
                unselectedLabelStyle: Neo.mono(12, spacing: 2),
                labelColor: Neo.cyan,
                unselectedLabelColor: Neo.dim,
                indicatorColor: Neo.cyan,
                dividerColor: Neo.faint,
              ),
              Expanded(
                child: TabBarView(children: [
                  _IntroTab(n),
                  _ChapterListTab(novelId: novelId),
                ]),
              ),
            ]),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _BottomBar(n, novelId)),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Rec n;
  final int novelId;
  const _Header(this.n, this.novelId);

  @override
  Widget build(BuildContext context) {
    final cover = n['cover_url'] as String?;
    return ClipRect(
      child: Stack(children: [
        Positioned.fill(
          child: (cover == null || cover.isEmpty)
              ? Container(color: Neo.surface)
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Image.network(cover, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: Neo.surface)),
                ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Neo.bg.withValues(alpha: 0.55), Neo.bg],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Neo.text),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              _DownloadButton(n),
              IconButton(
                tooltip: 'Thuật ngữ',
                icon: const Icon(Icons.translate, color: Neo.text),
                onPressed: () => context.push('/novel/$novelId/glossary'),
              ),
              const SizedBox(width: 4),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Hero(
                  tag: 'cover-${n['id']}',
                  child: NeoCover(url: cover, width: 108, label: n['title_vi'] ?? n['title_zh']),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n['title_vi'] ?? n['title_zh'] ?? '',
                        maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: Neo.display(20, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(n['author_vi'] ?? n['author_zh'] ?? '', style: Neo.mono(11)),
                    const SizedBox(height: 10),
                    NeoTag(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra'),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Nút tải offline / xoá bản đã tải — logic port từ widgets.dart app cũ.
class _DownloadButton extends ConsumerWidget {
  final Rec n;
  const _DownloadButton(this.n);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(isDownloadedProvider(n['id'] as int)).value ?? false;
    return IconButton(
      tooltip: downloaded ? 'Đã tải — chạm để xoá bản offline' : 'Tải về đọc offline',
      icon: Icon(downloaded ? Icons.download_done : Icons.download,
          color: downloaded ? Neo.cyan : Neo.text),
      onPressed: () => toggleOffline(context, ref, n, downloaded),
    );
  }
}

Future<void> toggleOffline(
    BuildContext context, WidgetRef ref, Map<String, dynamic> novel, bool downloaded) async {
  final id = novel['id'] as int;
  final messenger = ScaffoldMessenger.of(context);
  void refresh() {
    ref.invalidate(isDownloadedProvider(id));
    ref.invalidate(offlineNovelsProvider);
  }

  if (downloaded) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Neo.surface,
        shape: const NeoCutBorder(side: BorderSide(color: Neo.faint)),
        title: Text('XOÁ BẢN OFFLINE?', style: Neo.mono(14, color: Neo.text, weight: FontWeight.w700)),
        content: Text('Xoá các chương đã tải của truyện này khỏi máy.',
            style: Neo.mono(12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('HUỶ', style: Neo.mono(11, color: Neo.dim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('XOÁ', style: Neo.mono(11, color: Neo.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await offlineStore.deleteNovel(id);
    refresh();
    messenger.showSnackBar(const SnackBar(content: Text('Đã xoá bản offline')));
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: Neo.surface,
      shape: const NeoCutBorder(side: BorderSide(color: Neo.faint)),
      content: Row(children: [
        const SizedBox(width: 90, child: HudProgress()),
        const SizedBox(width: 16),
        Expanded(child: Text('ĐANG TẢI CHƯƠNG…', style: Neo.mono(11))),
      ]),
    ),
  );
  try {
    final count = await offlineStore.downloadNovel(novel);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    refresh();
    messenger.showSnackBar(SnackBar(
        content: Text(count > 0
            ? 'Đã tải $count chương để đọc offline'
            : 'Chưa có chương đã dịch nào để tải')));
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text('Lỗi tải: $e')));
  }
}

/// Hộp thoại "yêu cầu dịch" — logic port từ app cũ.
void translateRangeDialog(BuildContext context, WidgetRef ref, int novelId,
    {required int translated, required int source, VoidCallback? onDone}) {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return;
  }
  final custom = TextEditingController();

  Future<void> submit(int upTo) async {
    if (upTo <= translated) return;
    final n = await requestTranslation(novelId, upTo);
    ref.invalidate(chapterListProvider(novelId));
    ref.invalidate(translateQueueProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xếp $n chương vào hàng đợi dịch')));
    }
    onDone?.call();
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Neo.surface,
      shape: const NeoCutBorder(side: BorderSide(color: Neo.faint)),
      title: Text('YÊU CẦU DỊCH', style: Neo.mono(14, color: Neo.cyan, weight: FontWeight.w700, spacing: 2)),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đã dịch $translated/$source chương. Chọn dịch tới đâu:',
                style: Neo.mono(12)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final step in [50, 100, 200])
                if (translated + step <= source || translated < source)
                  ActionChip(
                    backgroundColor: Neo.surface2,
                    side: const BorderSide(color: Neo.faint),
                    shape: const RoundedRectangleBorder(),
                    label: Text('+$step', style: Neo.mono(11, color: Neo.text)),
                    onPressed: () => submit((translated + step).clamp(0, source)),
                  ),
              if (translated < source)
                ActionChip(
                  backgroundColor: Neo.surface2,
                  side: const BorderSide(color: Neo.cyan),
                  shape: const RoundedRectangleBorder(),
                  label: Text('ĐẾN HẾT', style: Neo.mono(11, color: Neo.cyan)),
                  onPressed: () => submit(source),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: custom,
              keyboardType: TextInputType.number,
              style: Neo.mono(13, color: Neo.text),
              decoration: const InputDecoration(
                  labelText: 'HOẶC DỊCH TỚI CHƯƠNG…', isDense: true),
              onSubmitted: (v) {
                final to = int.tryParse(v.trim());
                if (to != null) submit(to.clamp(0, source));
              },
            ),
          ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('ĐÓNG', style: Neo.mono(11, color: Neo.dim))),
        TextButton(
          onPressed: () {
            final to = int.tryParse(custom.text.trim());
            if (to != null) submit(to.clamp(0, source));
          },
          child: Text('DỊCH', style: Neo.mono(11, color: Neo.cyan, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// Tab Hồ sơ: số liệu + thể loại + giới thiệu.
class _IntroTab extends StatelessWidget {
  final Rec n;
  const _IntroTab(this.n);

  @override
  Widget build(BuildContext context) {
    final genres =
        (n['genres'] as List?)?.map((g) => '$g').where((g) => g.isNotEmpty).toList() ??
            const <String>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        _stats(),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('THỂ LOẠI', style: Neo.mono(9, spacing: 3)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final g in genres) NeoTag(g, color: Neo.plasma)]),
        ],
        const SizedBox(height: 22),
        Text('GIỚI THIỆU', style: Neo.mono(9, spacing: 3)),
        const SizedBox(height: 10),
        Text(n['description_vi'] ?? 'Chưa có giới thiệu.',
            textAlign: TextAlign.justify,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65)),
      ],
    );
  }

  Widget _stats() {
    final done = n['chapter_count_translated'] ?? 0;
    Widget cell(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: Neo.display(20, color: Neo.cyan)),
            const SizedBox(height: 3),
            Text(l.toUpperCase(), style: Neo.mono(8, spacing: 2)),
          ]),
        );
    return NeoPanel(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        cell('${n['chapter_count_source'] ?? 0}', 'Chương nguồn'),
        Container(width: 1, height: 30, color: Neo.faint),
        cell('$done', 'Đã dịch'),
        Container(width: 1, height: 30, color: Neo.faint),
        cell(n['status'] == 'completed' ? 'HOÀN' : 'ĐANG RA', 'Trạng thái'),
      ]),
    );
  }
}

/// Tab Mục lục: đảo thứ tự + nút yêu cầu dịch (logic app cũ).
class _ChapterListTab extends ConsumerStatefulWidget {
  final int novelId;
  const _ChapterListTab({required this.novelId});
  @override
  ConsumerState<_ChapterListTab> createState() => _ChapterListTabState();
}

class _ChapterListTabState extends ConsumerState<_ChapterListTab> {
  bool _asc = true;

  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(chapterListProvider(widget.novelId));
    final novel = ref.watch(novelProvider(widget.novelId)).value;
    return chapters.when(
      loading: () => const NeoLoading(label: 'NẠP MỤC LỤC'),
      error: (e, _) => NeoMessage('Lỗi mục lục: $e', error: true),
      data: (list) {
        final ordered = _asc ? list : list.reversed.toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(children: [
              Expanded(child: Text('${list.length} CHƯƠNG', style: Neo.mono(11, spacing: 2))),
              TextButton.icon(
                onPressed: () => translateRangeDialog(context, ref, widget.novelId,
                    translated: (novel?['chapter_count_translated'] ?? 0) as int,
                    source: (novel?['chapter_count_source'] ?? 0) as int,
                    onDone: () => ref.invalidate(chapterListProvider(widget.novelId))),
                icon: const Icon(Icons.playlist_add, size: 16, color: Neo.cyan),
                label: Text('DỊCH', style: Neo.mono(10, color: Neo.cyan, spacing: 2)),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _asc = !_asc),
                icon: Icon(_asc ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 16, color: Neo.dim),
                label: Text(_asc ? 'CŨ→MỚI' : 'MỚI→CŨ', style: Neo.mono(10, spacing: 1)),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
              itemCount: ordered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 7),
              itemBuilder: (_, i) => _ChapterTile(ordered[i], widget.novelId),
            ),
          ),
        ]);
      },
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final Rec c;
  final int novelId;
  const _ChapterTile(this.c, this.novelId);

  @override
  Widget build(BuildContext context) {
    final done = c['translation_status'] == 'done';
    return NeoTapGlow(
      onTap: () => context.push('/novel/$novelId/read/${c['chapter_index']}'),
      child: Container(
        decoration: ShapeDecoration(
          color: Neo.surface,
          shape: NeoCutBorder(
              cut: Neo.cutSm,
              side: BorderSide(color: done ? Neo.cyan.withValues(alpha: 0.3) : Neo.faint)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Text('${c['chapter_index']}'.padLeft(4, '0'),
              style: Neo.mono(10, color: done ? Neo.cyan : Neo.dim)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c['title_vi'] ?? 'Chương ${c['chapter_index']}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 14.5, color: done ? Neo.text : Neo.dim),
            ),
          ),
          const SizedBox(width: 8),
          _statusIcon(c['translation_status']),
        ]),
      ),
    );
  }

  Widget _statusIcon(String? status) {
    return switch (status) {
      'done' => const Icon(Icons.check, color: Neo.cyan, size: 16),
      'translating' => const SizedBox(width: 46, child: HudProgress()),
      'queued' => const Icon(Icons.hourglass_empty, size: 15, color: Neo.dim),
      'failed' => const Icon(Icons.error_outline, color: Neo.danger, size: 16),
      _ => Icon(Icons.lock_outline, size: 14, color: Neo.dim.withValues(alpha: 0.5)),
    };
  }
}

/// Thanh dưới: nút Đọc HUD + nút lưu tủ.
class _BottomBar extends ConsumerWidget {
  final Rec n;
  final int novelId;
  const _BottomBar(this.n, this.novelId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider(novelId)).value;
    final inLib = ref.watch(inLibraryProvider(novelId)).value ?? false;
    final reading = progress != null && progress > 1;
    final chapter = reading ? progress : 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Row(children: [
          // nút lưu tủ
          InkWell(
            onTap: () async {
              if (sb.auth.currentUser == null) {
                context.push('/login');
                return;
              }
              await setInLibrary(novelId, !inLib);
              ref.invalidate(inLibraryProvider(novelId));
              ref.invalidate(libraryProvider);
            },
            child: Container(
              height: 52, width: 52,
              decoration: ShapeDecoration(
                color: Neo.surface,
                shape: NeoCutBorder(
                    cut: Neo.cutSm,
                    side: BorderSide(color: inLib ? Neo.plasma : Neo.faint)),
                shadows: inLib ? Neo.glow(Neo.plasma, blur: 16, alpha: 0.35) : null,
              ),
              child: Icon(inLib ? Icons.bookmark : Icons.bookmark_border,
                  color: inLib ? Neo.plasma : Neo.dim),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NeoButton(
              label: reading ? 'ĐỌC TIẾP CH.$chapter' : 'BẮT ĐẦU ĐỌC',
              onPressed: () => context.push('/novel/$novelId/read/$chapter'),
            ),
          ),
        ]),
      ),
    );
  }
}
