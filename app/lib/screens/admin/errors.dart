import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data.dart';
import '../../errorlog.dart';

/// Nhật ký lỗi: LỖI WORKER (job dịch/crawl failed — đọc từ server, như màn Quản trị)
/// + lỗi runtime của app (bắt tại chỗ, lưu local).
class ErrorLogScreen extends ConsumerWidget {
  const ErrorLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final jobs = ref.watch(adminJobsProvider).value ?? const <Rec>[];
    final failed = [for (final j in jobs) if (j['status'] == 'failed') j];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký lỗi'),
        actions: [
          IconButton(
            tooltip: 'Xoá lỗi app (lỗi worker xoá ở Quản trị)',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: AppErrorLog.clear,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminJobsProvider),
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: AppErrorLog.entries,
          builder: (context, list, _) {
            if (list.isEmpty && failed.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 160),
                Icon(Icons.check_circle_outline_rounded,
                    size: 52, color: cs.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Center(child: Text('Chưa ghi nhận lỗi nào.', style: t.bodyMedium)),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (failed.isNotEmpty) ...[
                  _sectionLabel(context, 'Lỗi worker (dịch / crawl)'),
                  for (final j in failed) _JobErrorTile(j),
                ],
                if (list.isNotEmpty) ...[
                  _sectionLabel(context, 'Lỗi app (trên máy này)'),
                  for (final e in list) _ErrorTile(e),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}

/// 1 job worker lỗi: truyện + chương + thông báo lỗi từ server.
class _JobErrorTile extends StatelessWidget {
  final Rec j;
  const _JobErrorTile(this.j);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final novel = (j['novels'] as Map?) ?? const {};
    final title = novel['title_vi'] ?? novel['title_zh'] ?? 'Truyện #${j['novel_id']}';
    final idx = (j['chapters'] as Map?)?['chapter_index'];
    final err = '${j['error'] ?? 'Không rõ lỗi'}';
    return ExpansionTile(
      leading: Icon(Icons.cloud_off_rounded, color: cs.error),
      title: Text('$title${idx != null ? ' · chương $idx' : ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
      subtitle: Text(err, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SelectableText(err, style: t.bodySmall?.copyWith(color: cs.error)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Sao chép'),
            onPressed: () => Clipboard.setData(ClipboardData(text: err)),
          ),
        ),
      ],
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final Map<String, dynamic> e;
  const _ErrorTile(this.e);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final stack = (e['stack'] ?? '') as String;
    return ExpansionTile(
      leading: Icon(Icons.error_outline_rounded, color: cs.error),
      title: Text('${e['message']}',
          maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
      subtitle: Text(_fmt(e['time']), style: t.labelSmall),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SelectableText('${e['message']}',
            style: t.bodySmall?.copyWith(color: cs.error)),
        if (stack.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(stack,
              style: t.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant, fontFamily: 'monospace')),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Sao chép'),
            onPressed: () => Clipboard.setData(
                ClipboardData(text: '${e['message']}\n$stack')),
          ),
        ),
      ],
    );
  }

  String _fmt(Object? iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
