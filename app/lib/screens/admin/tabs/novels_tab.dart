import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data.dart';
import '../../../widgets.dart';
import 'shared.dart';

// ---------------- Truyện: tìm + ẩn/hiện + sửa + xoá ----------------
class NovelsTab extends ConsumerStatefulWidget {
  const NovelsTab({super.key});
  @override
  ConsumerState<NovelsTab> createState() => _NovelsTabState();
}

class _NovelsTabState extends ConsumerState<NovelsTab> {
  final _scroll = ScrollController();
  final _qCtrl = TextEditingController();
  final _items = <Rec>[];
  Timer? _debounce;
  String _q = '';
  int _filter = 0; // 0 = tất cả, 1 = đang hiển thị, 2 = đã ẩn
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  AdminNovelFilter get _f => (q: _q, tab: _filter);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _qCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _load();
    }
  }

  /// Đổi ô tìm / chip phân loại → về trang đầu. Gõ phím thì đợi 300ms mới bắn query,
  /// không thì mỗi ký tự là một lượt đi-về.
  void _reset({String? q, int? filter, bool debounced = false}) {
    _debounce?.cancel();
    apply() {
      setState(() {
        if (q != null) _q = q;
        if (filter != null) _filter = filter;
        _items.clear();
        _hasMore = true;
        _error = null;
      });
      _load();
    }

    if (debounced) {
      _debounce = Timer(const Duration(milliseconds: 300), apply);
    } else {
      apply();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final f = _f;
    try {
      final rows = await fetchAdminNovelPage(f, _items.length, kAdminNovelsPage);
      if (!mounted || f != _f) return; // bộ lọc đổi giữa chừng → lô này đã lạc hậu
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == kAdminNovelsPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(appStatsProvider);
    ref.invalidate(adminNovelCountsProvider(_q));
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    // Thao tác ẩn/sửa/xoá ở dòng con → nạp lại từ trang đầu.
    ref.listen(adminNovelsRevProvider, (_, _) => _refresh());

    // Chỉ nhường cả màn cho lỗi. KHÔNG nhường cho vòng quay: mỗi lần gõ ô tìm là
    // danh sách rỗng tạm thời, thay cả trang thì ô tìm biến mất và mất luôn con trỏ.
    if (_items.isEmpty && _error != null) {
      return AppError(_error!, onRetry: _refresh);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + 1 + (_hasMore || _loading ? 1 : 0),
        separatorBuilder: (_, i) =>
            i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == 0) return _header();
          if (i > _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _NovelRow(_items[i - 1], ref);
        },
      ),
    );
  }

  /// item 0 = thống kê + ô tìm + chip phân loại.
  Widget _header() {
    // Số đếm lấy từ máy chủ (count head) — trước đây đếm độ dài danh sách đã tải nên
    // bây giờ chỉ tải 1 trang thì đếm kiểu cũ sẽ nói dối.
    final counts = ref.watch(adminNovelCountsProvider(_q)).value;
    String n(int? v) => v == null ? '…' : fmtThousands(v);
    return Column(children: [
      const _StatsCard(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _qCtrl,
          onChanged: (v) => _reset(q: v.trim(), debounced: true),
          decoration: InputDecoration(
            hintText: 'Tìm truyện (tên Việt/Trung, tác giả)…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _qCtrl.clear();
                      _reset(q: '');
                    }),
          ),
        ),
      ),
      // cuộn ngang: số đếm dài (nghìn truyện) làm 3 chip tràn bề ngang
      // vài px trên máy hẹp (lỗi "right overflowed by 2.9px")
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          for (final (i, label) in [
            'Tất cả (${n(counts?.all)})',
            'Hiển thị (${n(counts?.visible)})',
            'Đã ẩn (${n(counts?.hidden)})',
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(label),
              selected: _filter == i,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _reset(filter: i),
            ),
          ],
        ]),
      ),
      if (_items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : const Text('Không có truyện nào khớp.'),
          ),
        ),
    ]);
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
            // "hiện ở Khám phá" = canonical + không ẩn (mỗi truyện 1 bản) — KHÁC chip
            // "Hiển thị" bên dưới (đếm mọi bản ghi không ẩn, kể cả bản trùng nguồn khác)
            cell(fmtThousands(s['visible'] ?? 0), 'hiện ở Khám phá', color: cs.primary),
            cell(fmtThousands(s['novels'] ?? 0), 'tổng bản ghi'),
            cell(fmtThousands(s['completed'] ?? 0), 'hoàn thành'),
            cell(fmtThousands(s['metaPending'] ?? 0), 'chờ dịch tên',
                color: (s['metaPending'] ?? 0) > 0 ? cs.tertiary : null),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            cell(fmtThousands(s['done'] ?? 0), 'chương đã dịch', color: cs.primary),
            cell(fmtThousands(s['chapters'] ?? 0), 'dòng mục lục lưu'),
            cell(fmtThousands(s['doneToday'] ?? 0), 'dịch hôm nay'),
            cell(fmtThousands(s['failed'] ?? 0), 'chương lỗi',
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
    final genres = ((n['genres'] as List?) ?? const []).join(', ');
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      horizontalTitleGap: 10, // chữ sát bìa hơn (mặc định 16 hở quá)
      leading: Opacity(
        opacity: hidden ? 0.5 : 1, // truyện đã ẩn → bìa mờ đi
        child: Cover(url: n['cover_url'], width: 42, aspect: 1.5, label: title),
      ),
      title: Text(title,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: t.titleMedium?.copyWith(
              color: hidden ? cs.onSurfaceVariant : cs.onSurface)),
      subtitle: Text(
        [
          '${n['chapter_count_translated'] ?? 0}/${n['chapter_count_source'] ?? 0} chương',
          if (genres.isNotEmpty) genres,
          if (hidden) 'đã ẩn',
        ].join(' · '),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          // dùng context TRƯỚC await (edit/delete mở dialog ngay, không qua async gap)
          if (v == 'edit') return _editNovel(context, n, ref);
          if (v == 'delete') return _deleteNovel(context, n, ref);
          await setNovelHidden(n['id'], !hidden);
          ref.read(adminNovelsRevProvider.notifier).bump();
          // Khám phá/trang chủ/tìm kiếm đang cache → invalidate để back ra là mất ngay.
          ref.invalidate(novelsProvider);
          ref.invalidate(homeSectionsProvider);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'hide',
              child: Text(hidden ? 'Hiện lại' : 'Ẩn khỏi Khám phá')),
          const PopupMenuItem(value: 'edit', child: Text('Sửa')),
          const PopupMenuItem(value: 'delete', child: Text('Xoá vĩnh viễn')),
        ],
      ),
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
              ref.read(adminNovelsRevProvider.notifier).bump();
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
        // maxFinite: dialog bung hết bề ngang cho phép (khỏi co giật theo nội dung);
        // scroll: bàn phím che thì cuộn được thay vì tràn
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: titleVi,
                  decoration: const InputDecoration(labelText: 'Tên tiếng Việt')),
              const SizedBox(height: 12),
              TextField(
                  controller: authorVi,
                  decoration: const InputDecoration(labelText: 'Tác giả (Việt)')),
              const SizedBox(height: 12),
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
          ),
        ),
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
              ref.read(adminNovelsRevProvider.notifier).bump();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
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
    // Gate đầu vào như màn Quản trị: deep-link thẳng vào đây cũng bị chặn UI
    // (RLS vẫn là lớp chặn dữ liệu cuối cùng).
    final admin = ref.watch(isAdminProvider);
    return admin.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: AppError(e, onRetry: () => ref.invalidate(isAdminProvider))),
      data: (ok) => ok
          ? _AdminNovelBody(novelId: novelId)
          : Scaffold(
              appBar: AppBar(title: const Text('Quản trị truyện')),
              body: const Center(child: Text('Bạn không có quyền quản trị.')),
            ),
    );
  }

}

/// Thân màn quản trị 1 truyện. Stateful vì danh sách chương cuộn-tải-dần (truyện
/// 6.111 chương không thể kéo một phát) — cùng khuôn với tab Truyện.
class _AdminNovelBody extends ConsumerStatefulWidget {
  final int novelId;
  const _AdminNovelBody({required this.novelId});
  @override
  ConsumerState<_AdminNovelBody> createState() => _AdminNovelBodyState();
}

class _AdminNovelBodyState extends ConsumerState<_AdminNovelBody> {
  int get novelId => widget.novelId;
  final _scroll = ScrollController();
  final _items = <Rec>[];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final rows = await fetchAdminChapterPage(
          novelId, _items.length, kAdminChaptersPage);
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == kAdminChaptersPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _hasMore = true;
      _error = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adminChaptersRevProvider, (_, _) => _reload());
    final novel = ref.watch(novelProvider(novelId)).value;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = novel?['title_vi'] ?? novel?['title_zh'] ?? 'Truyện #$novelId';

    return Scaffold(
      appBar: AppBar(
        title: Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Dịch lại tên + mô tả (sau khi sửa prompt)',
            icon: const Icon(Icons.title_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await requestMetaRetranslate(novelId);
                messenger.showSnackBar(const SnackBar(
                    content: Text('Đã xếp dịch lại tên — cập nhật sau vài '
                        'giây, kéo làm mới để xem.')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
              }
            },
          ),
          IconButton(
            tooltip: 'Yêu cầu dịch',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () => translateRangeDialog(context, ref, novelId,
                translated: (novel?['chapter_count_translated'] ?? 0) as int,
                source: (novel?['chapter_count_source'] ?? 0) as int,
                onDone: () => ref.read(adminChaptersRevProvider.notifier).bump()),
          ),
          IconButton(
            tooltip: 'Huỷ toàn bộ chương đang chờ dịch',
            icon: const Icon(Icons.playlist_remove_rounded),
            onPressed: () async {
              await cancelNovelQueue(novelId);
              ref.read(adminChaptersRevProvider.notifier).bump();
              ref.invalidate(translateQueueProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã huỷ các chương đang chờ dịch')));
              }
            },
          ),
        ],
      ),
      body: _error != null && _items.isEmpty
          ? AppError(_error!, onRetry: _reload)
          : RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(novelProvider(novelId));
            await _reload();
          },
          child: ListView.separated(
            controller: _scroll,
            itemCount: _items.length + 1 + (_hasMore || _loading ? 1 : 0),
            separatorBuilder: (_, i) =>
                i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) return _NovelInfoCard(novel);
              if (i > _items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final c = _items[i - 1];
              final st = c['translation_status'] as String;
              final tok = (c['prompt_tokens'] ?? 0) + (c['completion_tokens'] ?? 0);
              final info = [
                if (c['model_used'] != null) c['model_used'],
                if (tok > 0) '${fmtThousands(tok)} token',
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

/// Thẻ thông tin đầu màn quản trị 1 truyện: nguồn, trạng thái, thể loại,
/// chương mới nhất, tiến độ dịch — thứ trước đây nhét hết vào dòng danh sách.
class _NovelInfoCard extends StatelessWidget {
  final Rec? novel;
  const _NovelInfoCard(this.novel);

  @override
  Widget build(BuildContext context) {
    final n = novel;
    if (n == null) return const SizedBox(height: 8);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final genres = ((n['genres'] as List?) ?? const []).join(', ');

    // baseline: nhãn (labelSmall) và giá trị (bodyMedium) cỡ chữ/line-height khác
    // nhau — căn top là lệch dòng ngay
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                  width: 92,
                  child: Text(label,
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
              Expanded(child: Text(value, style: t.bodyMedium?.copyWith(color: cs.onSurface))),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Column(children: [
          row('Nguồn', '${(n['sources'] as Map?)?['name'] ?? '—'}'),
          row('Trạng thái', statusLabel('${n['status'] ?? ''}')),
          if (genres.isNotEmpty) row('Thể loại', genres),
          row(
              'Chương mới',
              n['last_chapter_at'] != null
                  ? '${elapsed(n['last_chapter_at'])} trước'
                  : '—'),
          row('Đã dịch',
              '${n['chapter_count_translated'] ?? 0}/${n['chapter_count_source'] ?? 0} chương'),
        ]),
      ),
    );
  }
}
