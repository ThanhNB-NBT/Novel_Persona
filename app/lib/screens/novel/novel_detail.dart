import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ambient.dart';
import '../../data.dart';
import '../../offline.dart';
import '../../theme.dart' show monoStyle;
import '../../widgets.dart';

class NovelDetailScreen extends ConsumerWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novel = ref.watch(novelProvider(novelId));
    return Scaffold(
      body: novel.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(novelProvider(novelId))),
        data: (n) {
          // nền khí quyển kiểu NEO: màu trích từ bìa loãng dần vào nền chung
          final amb = ref.watch(ambientProvider(n['cover_url'] as String?)).value ??
              Ambient.fallback;
          return AmbientBackdrop(
            ambient: amb,
            child: Stack(children: [
              DefaultTabController(
                length: 2,
                child: Column(children: [
                  _Header(n, novelId),
                  TabBar(
                    tabs: const [Tab(text: 'Giới thiệu'), Tab(text: 'Danh sách chương')],
                    labelStyle: Theme.of(context).textTheme.titleMedium,
                    dividerColor: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      _IntroTab(n),
                      _ChapterListTab(novelId: novelId),
                    ]),
                  ),
                ]),
              ),
              // Nút Lưu + Đọc nổi trên nội dung (bong bóng, đổ bóng)
              Positioned(left: 0, right: 0, bottom: 0, child: _BottomBar(n, novelId)),
            ]),
          );
        },
      ),
    );
  }
}

/// Header: ảnh bìa mờ làm nền + bìa nét + tiêu đề (không còn nút — nút xuống thanh dưới).
class _Header extends StatelessWidget {
  final Rec n;
  final int novelId;
  const _Header(this.n, this.novelId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cover = n['cover_url'] as String?;
    const onDark = Colors.white;
    // ClipRect: ảnh blur vẽ TRÀN ra ngoài biên widget nếu không clip → lem xuống hàng tab
    return ClipRect(
        child: Stack(children: [
      Positioned.fill(
        child: (cover == null || cover.isEmpty)
            ? Container(color: cs.primary.withValues(alpha: 0.35))
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Image.network(cover, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: cs.primary.withValues(alpha: 0.35))),
              ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // kết thúc bằng MÀU NỀN scaffold (không phải surface) → header liền mạch
              // với vùng tab bên dưới, ảnh không "tràn" thành dải lệch màu
              colors: [
                Colors.black.withValues(alpha: 0.4),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
      ),
      SafeArea(
        bottom: false,
        child: Column(children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: onDark),
              onPressed: () => context.pop(),
            ),
            const Spacer(),
            _DownloadButton(n),
            IconButton(
              tooltip: 'Thuật ngữ',
              icon: const Icon(Icons.translate_rounded, color: onDark),
              onPressed: () => context.push('/novel/$novelId/glossary'),
            ),
            const SizedBox(width: 4),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Hero(
                tag: 'cover-${n['id']}',
                child: Cover(url: cover, width: 112, label: n['title_vi'] ?? n['title_zh']),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n['title_vi'] ?? n['title_zh'] ?? '',
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: onDark, height: 1.2)),
                  const SizedBox(height: 6),
                  Text(n['author_vi'] ?? n['author_zh'] ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: onDark.withValues(alpha: 0.85))),
                  const SizedBox(height: 8),
                  TagChip(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra',
                      color: onDark),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]));
  }
}

/// Nút tải truyện về máy (đọc offline) / xoá bản đã tải — trên header, chữ trắng.
class _DownloadButton extends ConsumerWidget {
  final Rec n;
  const _DownloadButton(this.n);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(isDownloadedProvider(n['id'] as int)).value ?? false;
    return IconButton(
      tooltip: downloaded ? 'Đã tải — chạm để xoá bản offline' : 'Tải về đọc offline',
      icon: Icon(downloaded ? Icons.download_done_rounded : Icons.download_rounded,
          color: Colors.white),
      onPressed: () => toggleOffline(context, ref, n, downloaded),
    );
  }
}

/// Tab Giới thiệu: số liệu thật + thể loại + mô tả.
class _IntroTab extends StatelessWidget {
  final Rec n;
  const _IntroTab(this.n);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final genres =
        (n['genres'] as List?)?.map((g) => '$g').where((g) => g.isNotEmpty).toList() ??
            const <String>[];
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s,
              style: t.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant, letterSpacing: 0.3)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96), // chừa chỗ cho bong bóng nổi
      children: [
        _stats(context),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 22),
          label('Thể loại'),
          GenreChips(genres),
        ],
        const SizedBox(height: 22),
        label('Giới thiệu'),
        Text(n['description_vi'] ?? 'Chưa có giới thiệu.',
            textAlign: TextAlign.justify, // căn đều 2 bên cho gọn mắt
            style: t.bodyLarge?.copyWith(height: 1.65)),
      ],
    );
  }

  Widget _stats(BuildContext context) {
    final done = n['chapter_count_translated'] ?? 0;
    Widget cell(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(l, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
    final div = Container(
        width: 1, height: 34, color: Theme.of(context).colorScheme.outlineVariant);
    return Row(children: [
      cell('${n['chapter_count_source'] ?? 0}', 'Chương nguồn'),
      div,
      cell('$done', 'Đã dịch'),
      div,
      cell(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra', 'Trạng thái'),
    ]);
  }
}

/// Tab Danh sách chương: mặc định 1→hết, nút đảo thứ tự. Cuộn lười (truyện dài).
class _ChapterListTab extends ConsumerStatefulWidget {
  final int novelId;
  const _ChapterListTab({required this.novelId});
  @override
  ConsumerState<_ChapterListTab> createState() => _ChapterListTabState();
}

class _ChapterListTabState extends ConsumerState<_ChapterListTab> {
  bool _asc = true;

  /// Xác nhận rồi xếp lại MỌI chương đã dịch để dịch lại (prompt/glossary mới).
  Future<void> _retranslateAll({required int translated}) async {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (translated == 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Chưa có chương nào đã dịch để dịch lại')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dịch lại tất cả?'),
        content: Text('Xếp lại $translated chương đã dịch để dịch lại từ đầu bằng '
            'bản dịch mới. Bản cũ vẫn đọc được cho tới khi bản mới thay thế. '
            'Truyện dài sẽ mất nhiều thời gian.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Dịch lại')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await retranslateAll(widget.novelId);
      if (!mounted) return;
      ref.invalidate(chapterListProvider(widget.novelId));
      ref.invalidate(translateQueueProvider);
      messenger.showSnackBar(SnackBar(content: Text('Đã xếp lại $n chương để dịch lại')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(chapterListProvider(widget.novelId));
    final novel = ref.watch(novelProvider(widget.novelId)).value;
    final cs = Theme.of(context).colorScheme;
    return chapters.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppError(e, onRetry: () => ref.invalidate(chapterListProvider(widget.novelId))),
      data: (list) {
        final ordered = _asc ? list : list.reversed.toList();
        // Mục lục lười: truyện chưa ai đọc chỉ giữ vài chương đọc thử. Xem thông tin
        // KHÔNG tải mục lục (xem chưa chắc đọc) — chỉ khi bấm Đọc reader mới gọi
        // request_toc; quay lại tab này list tự refetch (autoDispose) nên số tự nhích.
        final total = (novel?['chapter_count_source'] ?? 0) as int;
        return Column(children: [
          if (list.isNotEmpty && list.length < total)
            _TocHint(have: list.length, total: total),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: Text('${list.length} chương',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
              TextButton.icon(
                // Chủ động yêu cầu dịch (song song với tự-dịch khi đọc, phòng khi quên).
                onPressed: () => translateRangeDialog(context, ref, widget.novelId,
                    translated: (novel?['chapter_count_translated'] ?? 0) as int,
                    source: (novel?['chapter_count_source'] ?? 0) as int,
                    onDone: () => ref.invalidate(chapterListProvider(widget.novelId))),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Dịch'),
              ),
              IconButton(
                tooltip: 'Dịch lại tất cả chương đã dịch',
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                onPressed: () => _retranslateAll(
                    translated: (novel?['chapter_count_translated'] ?? 0) as int),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _asc = !_asc),
                icon: Icon(_asc ? Icons.arrow_downward : Icons.arrow_upward, size: 18),
                label: Text(_asc ? 'Cũ → mới' : 'Mới → cũ'),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 96), // chừa chỗ cho bong bóng nổi
              itemCount: ordered.length,
              separatorBuilder: (_, _) => const RowDivider(),
              itemBuilder: (_, i) => _ChapterTile(ordered[i], widget.novelId),
            ),
          ),
        ]);
      },
    );
  }
}

/// Hint mục lục lười: chỉ thông báo, KHÔNG tự tải (tải khi bấm Đọc — reader lo).
class _TocHint extends StatelessWidget {
  final int have, total;
  const _TocHint({required this.have, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.auto_stories_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Đang có $have chương đọc thử — mục lục đầy đủ ($total chương) '
              'sẽ tự tải khi bạn bắt đầu đọc.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final Rec c;
  final int novelId;
  const _ChapterTile(this.c, this.novelId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = c['translation_status'] == 'done';
    // dòng thường + kẻ mảnh — không đóng khung từng chương
    return InkWell(
      onTap: () => context.push('/novel/$novelId/read/${c['chapter_index']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          // số thứ tự chương (mono, phải-căn cho thẳng cột khi số dài ngắn khác nhau)
          SizedBox(
            width: 34,
            child: Text('${c['chapter_index']}',
                textAlign: TextAlign.right,
                style: monoStyle(context,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c['title_vi'] ?? 'Chương ${c['chapter_index']}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: done ? null : cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          _statusIcon(context, c['translation_status']),
        ]),
      ),
    );
  }

  Widget _statusIcon(BuildContext context, String? status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'done' => Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
      'translating' => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      'queued' => Icon(Icons.hourglass_empty_rounded, size: 18, color: cs.onSurfaceVariant),
      'failed' => Icon(Icons.error_outline_rounded, color: cs.error, size: 18),
      _ => Icon(Icons.lock_outline_rounded, size: 16,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
    };
  }
}

/// Thanh dưới cố định: nút Đọc (chính) + nút lưu tủ. Thay cho nút full-width cũ.
class _BottomBar extends ConsumerWidget {
  final Rec n;
  final int novelId;
  const _BottomBar(this.n, this.novelId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider(novelId)).value;
    final inLib = ref.watch(inLibraryProvider(novelId)).value ?? false;
    final reading = progress != null && progress > 1;
    return SafeArea(
      top: false,
      child: Padding(
        // lề quanh để bong bóng "nổi" tách khỏi mép màn hình
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Row(children: [
          // Đọc bên TRÁI, Lưu (tròn, dấu cộng) bên PHẢI — cả hai thu gọn nhưng vẫn nổi
          Expanded(child: _readBubble(context, reading ? progress : 1, reading)),
          const SizedBox(width: 12),
          _saveBubble(context, ref, inLib),
        ]),
      ),
    );
  }

  /// Bong bóng "Đọc" — nổi, bo tròn nhiều, đổ bóng theo màu nhấn.
  Widget _readBubble(BuildContext context, int chapter, bool reading) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(23),
      elevation: 6,
      shadowColor: cs.primary.withValues(alpha: 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(23),
        onTap: () => context.push('/novel/$novelId/read/$chapter'),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_rounded, size: 18, color: cs.onPrimary),
            const SizedBox(width: 8),
            Text(reading ? 'Đọc tiếp chương $chapter' : 'Đọc truyện',
                style: TextStyle(
                    color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  /// Nút tròn Lưu tủ — dấu cộng; đã lưu thì thành dấu tick nền nhấn nhạt.
  Widget _saveBubble(BuildContext context, WidgetRef ref, bool inLib) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: inLib ? cs.primaryContainer : cs.surface,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        customBorder: const CircleBorder(),
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
          height: 46, width: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: inLib ? cs.primary : cs.outlineVariant),
          ),
          child: Icon(inLib ? Icons.check_rounded : Icons.add_rounded,
              size: 22, color: inLib ? cs.primary : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
