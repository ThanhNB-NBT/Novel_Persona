import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data.dart';
import 'shared.dart';

// ---------------- Báo cáo term dịch sai ----------------
class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AdminRefreshable(
      async: ref.watch(reportsProvider),
      onRefresh: () async => ref.invalidate(reportsProvider),
      emptyText: 'Không có báo cáo nào chờ xử lý.',
      builder: (reports) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = reports[i];
          final term = (r['glossary_terms'] as Map?) ?? const {};
          final novel = (r['novels'] as Map?) ?? const {};
          final termText = term.isEmpty
              ? '(term đã bị xoá)'
              : '${term['term_zh'] ?? '(?)'} → ${term['correct_vi']}';
          return ListTile(
            title: Text(termText, style: t.titleMedium),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r['reason'] != null && '${r['reason']}'.isNotEmpty)
                Text('Lý do: ${r['reason']}',
                    style: t.labelSmall?.copyWith(color: cs.error)),
              Text(novel['title_vi'] ?? novel['title_zh'] ?? '', style: t.labelSmall),
            ]),
            trailing: IconButton(
              tooltip: 'Đánh dấu đã xử lý',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () async {
                await resolveReport(r['id']);
                ref.invalidate(reportsProvider);
              },
            ),
            onTap: r['novel_id'] == null
                ? null
                : () => context.push('/novel/${r['novel_id']}/glossary'),
          );
        },
      ),
    );
  }
}
