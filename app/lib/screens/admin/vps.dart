import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'tabs/shared.dart';

/// Theo dõi máy chủ chạy worker: CPU/RAM/disk/mạng/load/uptime — số liệu do worker
/// tự đẩy lên bảng host_metrics mỗi phút, màn này TỰ LÀM MỚI mỗi 15 giây.
///
/// ĐỔI VPS không phải sửa app: worker trên máy mới (định danh ổn định qua
/// /etc/machine-id) tự xuất hiện thêm 1 dòng; dòng host cũ/chết xoá bằng nút thùng rác.
/// Nhãn + IP hiển thị chỉnh được ngay tại đây (lưu worker_settings).
class VpsMonitorScreen extends ConsumerStatefulWidget {
  const VpsMonitorScreen({super.key});

  @override
  ConsumerState<VpsMonitorScreen> createState() => _VpsMonitorScreenState();
}

class _VpsMonitorScreenState extends ConsumerState<VpsMonitorScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // "Realtime" mức hợp lý: số liệu worker đẩy mỗi phút, mình soi mới mỗi 15s.
    _timer = Timer.periodic(const Duration(seconds: 15),
        (_) => ref.invalidate(hostMetricsProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostMetricsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi VPS'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(hostMetricsProvider),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
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
              padding: const EdgeInsets.only(top: 8, bottom: 24),
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
    final age = DateTime.now().toUtc().difference(
        DateTime.parse('${h['updated_at']}').toUtc());
    final stale = age > const Duration(minutes: 5);
    final memTotal = (h['mem_total_mb'] as num?)?.toDouble();
    final memUsed = (h['mem_used_mb'] as num?)?.toDouble();
    final swapUsed = (h['swap_used_mb'] as num?)?.toDouble() ?? 0;
    final diskTotal = (h['disk_total_gb'] as num?)?.toDouble();
    final diskUsed = (h['disk_used_gb'] as num?)?.toDouble();
    final cpu = (h['cpu_pct'] as num?)?.toDouble();
    final load1 = (h['load1'] as num?)?.toDouble();
    final cores = h['cpu_count'] as int?;
    final rxK = (h['net_rx_kbps'] as num?)?.toDouble();
    final txK = (h['net_tx_kbps'] as num?)?.toDouble();
    // tính frac trước để null-promotion hoạt động (điều kiện ghép không promote được)
    final memFrac = (memTotal != null && memTotal > 0 && memUsed != null)
        ? memUsed / memTotal
        : null;
    final diskFrac = (diskTotal != null && diskTotal > 0 && diskUsed != null)
        ? diskUsed / diskTotal
        : null;
    final label = ((h['label'] as String?) ?? '').isEmpty ? host : '${h['label']}';

    Widget gauge(String label, double? frac, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(label, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(value,
                  style: monoStyle(context, size: 11.5, w: FontWeight.w600)),
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
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TagChip(stale ? 'MẤT TÍN HIỆU' : 'SỐNG',
                color: stale ? cs.error : kLive),
            IconButton(
              tooltip: 'Sửa nhãn / địa chỉ hiển thị',
              icon: const Icon(Icons.edit_outlined, size: 17),
              onPressed: () => _editLabels(context, ref, h),
            ),
            IconButton(
              tooltip: 'Xoá dòng này (host cũ/không còn dùng)',
              icon: Icon(Icons.delete_outline,
                  size: 17, color: cs.onSurfaceVariant),
              onPressed: () => _confirmDelete(context, ref, host),
            ),
          ]),
          if ('${h['address'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                  'IP ${h['address']} · cập nhật ${elapsed(h['updated_at'])} trước'
                  '${stale ? ' (nghi ngờ chết)' : ''}',
                  style: monoStyle(context, size: 11, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 14),
          gauge('CPU', cpu == null ? null : cpu / 100,
              cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%'),
          const SizedBox(height: 12),
          gauge('RAM', memFrac,
              memUsed == null ? '—' : '$memUsed/${memTotal ?? '?'} MB'),
          if (swapUsed > 0) ...[
            const SizedBox(height: 12),
            Text('Swap đang dùng: $swapUsed MB',
                style: t.labelSmall?.copyWith(
                    color: swapUsed > 200 ? cs.error : cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          gauge('Disk', diskFrac,
              diskUsed == null ? '—' : '$diskUsed/${diskTotal ?? '?'} GB'),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.south_rounded, size: 13, color: cs.primary),
            const SizedBox(width: 3),
            Text(rxK == null ? '↓ —' : '↓ ${_rate(rxK)}',
                style: monoStyle(context, size: 11.5)),
            const SizedBox(width: 16),
            Icon(Icons.north_rounded, size: 13, color: cs.tertiary),
            const SizedBox(width: 3),
            Text(txK == null ? '↑ —' : '↑ ${_rate(txK)}',
                style: monoStyle(context, size: 11.5)),
            const Spacer(),
            if ((h['net_rx_gb'] as num?) != null)
              Text(
                  'tổng ↓ ${(h['net_rx_gb'] as num).toStringAsFixed(1)} · '
                  '↑ ${(h['net_tx_gb'] as num).toStringAsFixed(1)} GB',
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 14),
          Text(
            [
              if (load1 != null && cores != null)
                'load $load1/$cores (${(load1 / cores).toStringAsFixed(2)}/core)',
              if (cores != null) '$cores core',
              if (h['uptime_h'] != null)
                'uptime ${(h['uptime_h'] as num).toStringAsFixed(0)} giờ',
            ].join(' · '),
            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  static String _rate(double kbps) => kbps >= 1024
      ? '${(kbps / 1024).toStringAsFixed(1)} MB/s'
      : '${kbps.toStringAsFixed(0)} kB/s';

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
      await saveVpsLabels(host,
          label: labelCtrl.text.trim(), address: addrCtrl.text.trim());
      ref.invalidate(hostMetricsProvider);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, String host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá dòng host này?'),
        content: Text(
            '$host sẽ biến mất khỏi màn theo dõi. Nếu worker thật vẫn chạy và đẩy '
            'số liệu thì dòng mới sẽ lại xuất hiện ở lần đẩy kế.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok == true) {
      await deleteHostMetrics(host);
      ref.invalidate(hostMetricsProvider);
    }
  }
}
