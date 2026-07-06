import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../errorlog.dart';

/// Nhật ký lỗi runtime của app (bắt tại chỗ, lưu local). Xem khi test trên máy thật.
class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký lỗi'),
        actions: [
          IconButton(
            tooltip: 'Xoá hết',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: AppErrorLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: AppErrorLog.entries,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 52, color: cs.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text('Chưa ghi nhận lỗi nào.', style: t.bodyMedium),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _ErrorTile(list[i]),
          );
        },
      ),
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
