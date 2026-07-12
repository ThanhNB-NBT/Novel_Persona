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

class _SizeBar extends StatelessWidget {
  final int count, bytes;
  const _SizeBar({required this.count, required this.bytes});
  @override
  Widget build(BuildContext context) {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(children: [
        Icon(Icons.download_done_rounded,
            size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text('$count truyện · $mb MB',
            style: Theme.of(context).textTheme.titleMedium),
      ]),
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
