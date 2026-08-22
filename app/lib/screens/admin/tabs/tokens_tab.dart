import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data.dart';
import 'shared.dart';

// ---------------- Token: chi phí LLM theo model ----------------
class TokensTab extends ConsumerWidget {
  const TokensTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final health = ref.watch(modelHealthProvider).value ?? const <Rec>[];
    return AdminRefreshable(
      async: ref.watch(tokenUsageProvider),
      onRefresh: () async {
        ref.invalidate(tokenUsageProvider);
        ref.invalidate(modelHealthProvider);
      },
      emptyText: 'Chưa có dữ liệu token.',
      builder: (rows) {
        int sumP = 0, sumC = 0, sumCh = 0;
        for (final r in rows) {
          sumP += (r['prompt_tokens'] ?? 0) as int;
          sumC += (r['completion_tokens'] ?? 0) as int;
          sumCh += (r['chapters'] ?? 0) as int;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                _stat(context, fmtThousands(sumP + sumC), 'token tổng', cs.primary),
                Container(width: 1, height: 30, color: cs.outlineVariant),
                _stat(context, fmtThousands(sumCh), 'chương dịch', null),
              ]),
            ),
            const SizedBox(height: 8),
            Text('NVIDIA NIM + OpenRouter (:free) = \$0 · chỉ token Fireworks mới tính phí.',
                style: t.labelSmall),
            const SizedBox(height: 12),
            for (final r in rows) _tokenRow(context, r),
            if (health.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('SỨC KHỎE MODEL',
                  style: t.labelSmall?.copyWith(letterSpacing: 1.5, color: cs.primary)),
              const SizedBox(height: 8),
              for (final h in health) _healthRow(context, h),
            ],
          ],
        );
      },
    );
  }

  Widget _stat(BuildContext c, String v, String label, Color? color) => Expanded(
        child: Column(children: [
          Text(v, style: Theme.of(c).textTheme.headlineSmall?.copyWith(color: color)),
          Text(label, style: Theme.of(c).textTheme.bodySmall),
        ]),
      );

  Widget _tokenRow(BuildContext context, Rec r) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r['model_used'] ?? '(?)', style: t.titleSmall),
        const SizedBox(height: 2),
        Text('${fmtThousands(r['chapters'] ?? 0)} chương · vào ${fmtThousands(r['prompt_tokens'] ?? 0)} · '
            'ra ${fmtThousands(r['completion_tokens'] ?? 0)}',
            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// 1 dòng sức khỏe model: chấm màu sống/chậm/chết + latency TB + % OK + lần OK cuối.
  Widget _healthRow(BuildContext context, Rec h) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ok = (h['ok_count'] ?? 0) as int;
    final fail = (h['fail_count'] ?? 0) as int;
    final total = ok + fail;
    final rate = total > 0 ? ok / total : 0.0;
    final avgMs = ok > 0 ? (h['total_latency_ms'] ?? 0) / ok : 0.0;
    final lastOk = h['last_ok_at'] as String?;
    final (dot, label) = (rate < 0.5 || lastOk == null)
        ? (cs.error, 'chết')
        : (avgMs > 90000 || rate < 0.85)
            ? (cs.tertiary, 'chậm')
            : (cs.primary, 'sống');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(width: 10, height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h['model'] ?? '(?)', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
            const SizedBox(height: 2),
            Text('${(avgMs / 1000).toStringAsFixed(1)}s TB · ${(rate * 100).round()}% OK '
                '($ok/$total)${lastOk != null ? ' · OK ${elapsed(lastOk)} trước' : ' · chưa OK'}',
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            if (label == 'chết' && h['last_error'] != null)
              Text('${h['last_error']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: cs.error)),
          ]),
        ),
        Text(label, style: t.labelMedium?.copyWith(color: dot, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
