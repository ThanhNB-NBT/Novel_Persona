import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'common.dart';

import '../data.dart';
import '../offline.dart';

/// Tải truyện về máy (đọc offline) hoặc xoá bản đã tải. Dùng chung ở chi tiết truyện
/// và tủ truyện. Tải = chỉ các chương ĐÃ DỊCH hiện có.
Future<void> toggleOffline(
    BuildContext context, WidgetRef ref, Map<String, dynamic> novel, bool downloaded) async {
  final id = novel['id'] as int;
  final messenger = ScaffoldMessenger.of(context);
  void refresh() {
    ref.invalidate(isDownloadedProvider(id));
    ref.invalidate(offlineNovelsProvider);
  }

  if (downloaded) {
    final ok = await showBlurDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá bản offline?'),
        content: const Text('Xoá các chương đã tải của truyện này khỏi máy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    await offlineStore.deleteNovel(id);
    refresh();
    messenger.showSnackBar(const SnackBar(content: Text('Đã xoá bản offline')));
    return;
  }

  // Tải: hiện vòng quay chặn thao tác tới khi xong (tải theo lô, vài giây).
  showBlurDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 18),
        Expanded(child: Text('Đang tải chương về máy…')),
      ]),
    ),
  );
  try {
    final count = await offlineStore.downloadNovel(novel);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // đóng loading
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

/// Hộp thoại "yêu cầu dịch": chọn dịch tới đâu (chạy song song với tự-dịch khi đọc).
/// [translated]/[source] để tính preset "+N chương" và "đến hết".
void translateRangeDialog(BuildContext context, WidgetRef ref, int novelId,
    {required int translated, required int source, VoidCallback? onDone}) {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return;
  }
  final custom = TextEditingController();

  Future<void> submit(int upTo) async {
    if (upTo <= translated) return; // đã dịch tới đó rồi
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

  showBlurDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Yêu cầu dịch'),
      // maxFinite + scroll: bề ngang ổn định, bàn phím che thì cuộn thay vì tràn
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đã dịch $translated/$source chương. Chọn dịch tới đâu:',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final step in [50, 100, 200])
                if (translated + step <= source || translated < source)
                  ActionChip(
                    label: Text('+$step chương'),
                    onPressed: () => submit((translated + step).clamp(0, source)),
                  ),
              if (translated < source)
                ActionChip(label: const Text('Đến hết'), onPressed: () => submit(source)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: custom,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Hoặc dịch tới chương…', isDense: true),
              onSubmitted: (v) {
                final to = int.tryParse(v.trim());
                if (to != null) submit(to.clamp(0, source));
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        FilledButton(
          onPressed: () {
            final to = int.tryParse(custom.text.trim());
            if (to != null) submit(to.clamp(0, source));
          },
          child: const Text('Dịch'),
        ),
      ],
    ),
  );
}
