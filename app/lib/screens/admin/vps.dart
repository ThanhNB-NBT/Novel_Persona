import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'tabs/shared.dart';

/// Theo dõi máy chủ chạy worker: CPU/RAM/disk/load/uptime — số liệu do worker tự đẩy
/// lên bảng host_metrics mỗi phút. ĐỔI VPS không phải sửa app: worker trên máy mới
/// tự xuất hiện thêm 1 dòng; nhãn/IP hiển thị chỉnh được ngay tại đây (lưu
/// worker_settings, key gắn hostname nên nhiều host không giẫm nhau).
class VpsMonitorScreen extends ConsumerWidget {
  const VpsMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostMetricsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const PageHeader('QUẢN TRỊ', 'Theo dõi VPS'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(hostMetricsProvider),
              child: hosts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => AppError(e,
                    onRetry: () => ref.invalidate(hostMetricsProvider)),
                data: (list) {
                  if (list.isEmpty) {
                    return ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Chưa có số liệu nào.\n\nWorker trên VPS cần bản mới '
                            '(có đẩy host_metrics) và đã chạy ít nhất 1 phút.'),
                      ),
                    ]);
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final h in list) ...[
                        _HostCard(h),
                        const SizedBox(height: 4),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HostCard extends ConsumerWidget {
  final Rec h;
  const _HostCard(this.h);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final host = '${h['host']}';
    final stale = DateTime.now().toUtc().difference(
            DateTime.parse('${h['updated_at']}').toUtc()) >
        const Duration(minutes: 5);
    final memTotal = (h['mem_total_mb'] as num?)?.toDouble();
    final memUsed = (h['mem_used_mb'] as num?)?.toDouble();
    final diskTotal = (h['disk_total_gb'] as num?)?.toDouble();
    final diskUsed = (h['disk_used_gb'] as num?)?.toDouble();
    final cpu = (h['cpu_pct'] as num?)?.toDouble();
    final load1 = (h['load1'] as num?)?.toDouble();
    // tính frac trước để null-promotion hoạt động (điều kiện ghép không promote được)
    final memFrac = (memTotal != null && memTotal > 0 && memUsed != null)
        ? memUsed / memTotal
        : null;
    final diskFrac = (diskTotal != null && diskTotal > 0 && diskUsed != null)
        ? diskUsed / diskTotal
        : null;

    Widget gauge(String label, double? frac, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(label, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(value, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac?.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation(
                    frac != null && frac > 0.9 ? cs.error : cs.primary),
              ),
            ),
          ],
        );

    // VPS 2GB hay chết vì RAM trước cả CPU → tô đỏ khi >90%.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(stale ? Icons.dns_outlined : Icons.dns_rounded,
                size: 17, color: stale ? cs.onSurfaceVariant : kLive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ((h['label'] as String?) ?? '').isEmpty ? host : '${h['label']}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TagChip(stale ? 'MẤT TÍN HIỆU' : 'SỐNG',
                color: stale ? cs.error : kLive),
            IconButton(
              tooltip: 'Sửa nhãn / địa chỉ hiển thị',
              icon: const Icon(Icons.edit_outlined, size: 17),
              onPressed: () => _editLabels(context, ref, h),
            ),
          ]),
          if ('${h['address'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('IP ${h['address']} · cập nhật ${elapsed(h['updated_at'])} trước',
                  style: monoStyle(context, size: 11, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 14),
          gauge('CPU', cpu == null ? null : cpu / 100,
              cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%'),
          const SizedBox(height: 12),
          gauge('RAM', memFrac,
              memUsed == null ? '—' : '$memUsed/${memTotal ?? '?'} MB'),
          const SizedBox(height: 12),
          gauge('Disk', diskFrac,
              diskUsed == null ? '—' : '$diskUsed/${diskTotal ?? '?'} GB'),
          const SizedBox(height: 14),
          Text(
            [
              if (load1 != null) 'load $load1',
              if (h['cpu_count'] != null) '${h['cpu_count']} core',
              if (h['uptime_h'] != null)
                'uptime ${(h['uptime_h'] as num).toStringAsFixed(0)} giờ',
            ].join(' · '),
            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Future<void> _editLabels(BuildContext context, WidgetRef ref, Rec h) async {
    final host = '${h['host']}';
    final labelCtrl = TextEditingController(text: '${h['label'] ?? ''}');
    final addrCtrl = TextEditingController(text: '${h['address'] ?? ''}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nhãn máy chủ ($host)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: labelCtrl,
            decoration:
                const InputDecoration(labelText: 'Nhãn hiển thị (vd VPS chính)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addrCtrl,
            decoration:
                const InputDecoration(labelText: 'Địa chỉ / IP (hiển thị)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (saved == true) {
      await saveVpsLabels(host, label: labelCtrl.text.trim(), address: addrCtrl.text.trim());
      ref.invalidate(hostMetricsProvider);
    }
  }
}
