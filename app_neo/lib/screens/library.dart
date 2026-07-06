import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';
import '../offline.dart';
import 'novel_detail.dart' show toggleOffline;

/// Tab Tủ truyện — logic port từ app cũ.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(readingProvider);
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEO // TỦ TRUYỆN', style: Neo.mono(10, color: Neo.cyan, spacing: 3)),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(child: Text('Đang đọc', style: Neo.display(28))),
              IconButton(
                tooltip: 'Bản offline',
                icon: const Icon(Icons.download_done, color: Neo.text, size: 22),
                onPressed: () => context.push('/offline'),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: reading.when(
            loading: () => const NeoLoading(),
            error: (e, _) => NeoMessage('Lỗi: $e', error: true),
            data: (list) {
              if (sb.auth.currentUser == null) {
                return Center(
                  child: SizedBox(
                    width: 240,
                    child: NeoButton(
                        label: 'ĐĂNG NHẬP', onPressed: () => context.push('/login')),
                  ),
                );
              }
              if (list.isEmpty) {
                return const NeoMessage(
                    'CHƯA CÓ TRUYỆN ĐANG ĐỌC\nMỞ MỘT TRUYỆN Ở KHÁM PHÁ ĐỂ BẮT ĐẦU');
              }
              return RefreshIndicator(
                color: Neo.cyan,
                backgroundColor: Neo.surface,
                onRefresh: () async => ref.invalidate(readingProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.only(top: 6, bottom: 110),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const NeoDivider(),
                  itemBuilder: (_, i) => _ReadingRow(list[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ReadingRow extends ConsumerWidget {
  final Rec n;
  const _ReadingRow(this.n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = (n['cur_chapter'] ?? 1) as int;
    final total = (n['chapter_count_source'] ?? 0) as int;
    final progress = total > 0 ? cur / total : 0.0;
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    return NeoTapGlow(
      onTap: () => context.push('/novel/${n['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NeoCover(url: n['cover_url'], width: 58, aspect: 1.36, label: title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 2),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Neo.display(15, weight: FontWeight.w600)),
                ),
                _menu(context, ref),
              ]),
              const SizedBox(height: 2),
              Text('ĐÃ ĐỌC $cur${total > 0 ? '/$total' : ''}',
                  style: Neo.mono(10, spacing: 1.5)),
              const SizedBox(height: 8),
              HudProgress(value: progress.clamp(0, 1).toDouble()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(isDownloadedProvider(n['id'] as int)).value ?? false;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      color: Neo.surface2,
      shape: const NeoCutBorder(cut: Neo.cutSm, side: BorderSide(color: Neo.faint)),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: const Icon(Icons.more_vert, size: 20, color: Neo.dim),
      onSelected: (v) async {
        if (v == 'offline') {
          await toggleOffline(context, ref, n, downloaded);
        } else if (v == 'remove') {
          await removeReading(n['id']);
          ref.invalidate(readingProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã xóa khỏi Tủ truyện')),
            );
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'offline',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                downloaded ? Icons.download_done : Icons.download_for_offline_outlined,
                color: Neo.text),
            title: Text(downloaded ? 'Xoá bản offline' : 'Tải truyện về máy',
                style: const TextStyle(color: Neo.text, fontSize: 14)),
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bookmark_remove_outlined, color: Neo.danger),
            title: Text('Xóa khỏi tủ (xóa lịch sử đọc)',
                style: TextStyle(color: Neo.danger, fontSize: 14)),
          ),
        ),
      ],
    );
  }
}
