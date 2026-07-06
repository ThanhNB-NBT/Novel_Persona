import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';
import '../offline.dart';

/// Bản offline — danh sách + dung lượng + xoá (logic port từ app cũ).
class OfflineLibraryScreen extends ConsumerWidget {
  const OfflineLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novels = ref.watch(offlineNovelsProvider);
    final size = ref.watch(offlineSizeProvider).value ?? 0;
    return NeoScaffold(
      body: SafeArea(
        child: Column(children: [
          const NeoAppBar(title: 'Bản offline'),
          Expanded(
            child: novels.when(
              loading: () => const NeoLoading(),
              error: (e, _) => NeoMessage('Lỗi: $e', error: true),
              data: (list) {
                if (list.isEmpty) {
                  return const NeoMessage(
                      'CHƯA TẢI TRUYỆN NÀO VỀ MÁY\nMỞ MỘT TRUYỆN → NÚT TẢI ĐỂ ĐỌC OFFLINE');
                }
                final mb = (size / (1024 * 1024)).toStringAsFixed(1);
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(children: [
                      const Icon(Icons.storage, size: 18, color: Neo.cyan),
                      const SizedBox(width: 10),
                      Text('${list.length} TRUYỆN · $mb MB',
                          style: Neo.mono(12, color: Neo.text, weight: FontWeight.w600, spacing: 1.5)),
                    ]),
                  ),
                  const NeoDivider(),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const NeoDivider(),
                      itemBuilder: (_, i) => _OfflineRow(list[i]),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _OfflineRow extends ConsumerWidget {
  final Rec n;
  const _OfflineRow(this.n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = n['novel_id'] as int;
    final title = (n['title'] as String?) ?? 'Truyện';
    return InkWell(
      onTap: () => context.push('/novel/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          NeoCover(url: n['cover_url'], width: 48, aspect: 1.36, label: title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Neo.display(15, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${n['total'] ?? 0} chương đã tải', style: Neo.mono(9, spacing: 1.5)),
            ]),
          ),
          IconButton(
            tooltip: 'Xoá bản offline',
            icon: const Icon(Icons.delete_outline, color: Neo.danger),
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
