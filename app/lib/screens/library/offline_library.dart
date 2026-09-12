import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../offline.dart';
import '../../widgets.dart';

/// Quản lý truyện đã tải về máy (đọc offline): danh sách + dung lượng + xoá.
class OfflineLibraryScreen extends ConsumerWidget {
  const OfflineLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novels = ref.watch(offlineNovelsProvider);
    final size = ref.watch(offlineSizeProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Bản offline')),
      body: novels.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(offlineNovelsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'Chưa tải truyện nào về máy.\nMở một truyện → nút tải để đọc offline.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(children: [
            _SizeBar(count: list.length, bytes: size),
            const RowDivider(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const RowDivider(),
                itemBuilder: (_, i) => _OfflineRow(list[i]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SizeBar extends ConsumerWidget {
  final int count, bytes;
  const _SizeBar({required this.count, required this.bytes});

  Future<void> _confirmClean(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dọn dẹp bộ nhớ offline?'),
        content: Text(
          'Thao tác này sẽ xoá toàn bộ $count truyện đã tải về máy để giải phóng dung lượng. Bạn có chắc chắn muốn tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await offlineStore.deleteAllNovels();
      ref.invalidate(offlineNovelsProvider);
      ref.invalidate(offlineSizeProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storage_rounded, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dung lượng đã tải', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('$mb MB · $count truyện', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: count > 0 ? () => _confirmClean(context, ref) : null,
                icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                label: const Text('Dọn dẹp'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (bytes / (100 * 1024 * 1024)).clamp(0.02, 1.0),
              minHeight: 6,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineRow extends ConsumerWidget {
  final Rec n;
  const _OfflineRow(this.n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final id = n['novel_id'] as int;
    final title = (n['title'] as String?) ?? 'Truyện';
    return InkWell(
      onTap: () => context.push('/novel/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Cover(url: n['cover_url'], width: 48, aspect: 1.36, label: title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              const SizedBox(height: 3),
              Text('${n['total'] ?? 0} chương đã tải',
                  style: t.labelSmall),
            ]),
          ),
          IconButton(
            tooltip: 'Xoá bản offline',
            icon: Icon(Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await offlineStore.deleteNovel(id);
              ref.invalidate(offlineNovelsProvider);
              ref.invalidate(offlineSizeProvider);
              ref.invalidate(isDownloadedProvider(id));
            },
          ),
        ]),
      ),
    );
  }
}
