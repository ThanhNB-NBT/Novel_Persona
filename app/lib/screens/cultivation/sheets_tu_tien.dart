import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../widgets.dart';
import 'cultivation.dart' show CultSectionLabel;
import 'pixel.dart';

/// Bộ sưu tập: đối chiếu catalog với lịch sử từng sở hữu. Dùng/luyện hóa hết đồ
/// không làm mất tiến độ sưu tập.
class CollectionSheet extends ConsumerWidget {
  const CollectionSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final catalog = ref.watch(cultCatalogProvider);
    final collection = ref.watch(cultCollectionProvider);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(cultCatalogProvider)),
        data: (items) {
          if (collection.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (collection.hasError) {
            return Center(child: Text('Lỗi: ${collection.error}'));
          }
          final owned = collection.value ?? const <int>{};
          final byType = <String, List<Rec>>{};
          for (final it in items) {
            (byType[it['type'] as String] ??= []).add(it);
          }
          final types = cultTypeNames.keys.where(byType.containsKey).toList();

          // .builder chứ KHÔNG phải ListView(children:): bản cũ dựng sẵn lưới ô của
          // MỌI loại vật phẩm (catalog vài trăm ô, mỗi ô một PixelIcon tự vẽ) ngay
          // cả khi chỉ nhìn thấy loại đầu tiên — và dựng lại mỗi lần sheet rebuild.
          // item 0 = khối tiêu đề, sau đó mỗi loại chiếm 2 item: nhãn mục rồi lưới ô.
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: 1 + types.length * 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sưu tập  ${owned.length}/${items.length}',
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vật phẩm đã gặp được lưu vĩnh viễn — dùng hoặc luyện hóa không mất dấu.',
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                );
              }
              final ty = types[(i - 1) ~/ 2];
              if (i.isOdd) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: CultSectionLabel(
                    '${cultTypeNames[ty]}  '
                    '${byType[ty]!.where((it) => owned.contains(it['id'])).length}'
                    '/${byType[ty]!.length}',
                    Icons.category_rounded,
                  ),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final it in byType[ty]!)
                    _CollectionTile(it: it, owned: owned.contains(it['id'])),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  final Rec it;
  final bool owned;
  const _CollectionTile({required this.it, required this.owned});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grade = it['grade'] as int;
    final gc = gradeColor(grade);
    final icon = PixelIcon(it['pixel'] as String, grade: grade, size: 38);
    return Tooltip(
      message: owned ? it['name'] as String : '??? (chưa thu thập)',
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surface,
          gradient: owned
              ? RadialGradient(
                  colors: [
                    gc.withValues(alpha: 0.25),
                    cs.surface,
                  ],
                  stops: const [0.0, 1.0],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: owned
                ? gc.withValues(alpha: 0.75)
                : cs.outlineVariant.withValues(alpha: 0.3),
            width: owned ? 1.4 : 1.0,
          ),
          boxShadow: owned && grade >= 3
              ? [
                  BoxShadow(
                    color: gc.withValues(alpha: 0.20),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: owned
            ? icon
            : ColorFiltered(
                colorFilter: ColorFilter.mode(
                  cs.onSurface.withValues(alpha: 0.28),
                  BlendMode.srcATop,
                ),
                child: icon,
              ),
      ),
    );
  }
}

class DongPhuSheet extends ConsumerStatefulWidget {
  final Rec st;
  const DongPhuSheet({super.key, required this.st});

  @override
  ConsumerState<DongPhuSheet> createState() => _DongPhuSheetState();
}

class _DongPhuSheetState extends ConsumerState<DongPhuSheet> {
  bool _busy = false;
  bool _showParticles = false;

  /// Gọi RPC thật (migration 124): server kiểm hồi 4h + trần bình cảnh.
  Future<void> _harvestQi() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showParticles = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      HapticFeedback.heavyImpact();
      final r = await cultHarvest();
      ref.invalidate(cultStateProvider);
      ref.invalidate(cultCooldownProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('Tụ linh thành công: +${gonSo(r['gain'] as num)} tu vi'),
        duration: const Duration(seconds: 2),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loiDeHieu(e))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showParticles = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = widget.st['realm'] as int;
    final ascended = widget.st['ascended_at'] != null;
    final rate = (widget.st['rate'] as num).toDouble();
    final last = DateTime.tryParse(
        '${ref.watch(cultCooldownProvider).value?['last_harvest_at'] ?? ''}');
    final nextAt = last?.add(const Duration(hours: 4)).toLocal();
    final ready = nextAt == null || nextAt.isBefore(DateTime.now());

    final dongPhuNames = [
      'Thảo Lư Sơ Cấp',
      'Thạch Động Tụ Khí',
      'Linh Nhai Phúc Địa',
      'Động Thiên Phúc Địa',
      'Tử Tiêu Cung',
      'Vân Mộng Tiên Đảo',
      'Côn Lôn Thần Điện',
      'Bồng Lai Cực Lạc Phủ',
      'Hỗn Nguyên Tiên Phủ',
      'Chư Thiên Khởi Nguyên Đạo Điện',
    ];
    final dongPhuName = ascended
        ? dongPhuNames.last
        : dongPhuNames[(realm - 1).clamp(0, dongPhuNames.length - 1)];

    return Stack(
      children: [
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.temple_buddhist_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Động Phủ Tu Luyện', style: t.titleMedium),
                      Text(dongPhuName, style: t.labelSmall?.copyWith(color: cs.primary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  _row(
                    context,
                    icon: Icons.blur_on_rounded,
                    title: 'Tụ Linh Trận Pháp',
                    desc: 'Thu nạp linh khí đất trời: +${gonTocDo(rate)} tu vi/giây',
                  ),
                  const Divider(height: 20),
                  _row(
                    context,
                    icon: Icons.water_drop_rounded,
                    title: 'Linh Tuyền Trì',
                    desc: 'Tẩy rửa tâm cảnh, thanh lọc đan điền tự nhiên',
                  ),
                  const Divider(height: 20),
                  _row(
                    context,
                    icon: Icons.grass_rounded,
                    title: 'Linh Điền Dược Thảo',
                    desc: 'Hấp thu nhật nguyệt tinh hoa, nuôi dưỡng căn cơ',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // minHeight chứ không ghim cao 44: chữ to (cỡ chữ hệ thống) bị cắt đáy
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: FilledButton.icon(
                onPressed: _busy || !ready ? null : _harvestQi,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(ready
                    ? 'Thu nạp linh khí · +30 phút tu vi'
                    : 'Đang tụ linh · thu nạp lúc ${nextAt.hour.toString().padLeft(2, '0')}:${nextAt.minute.toString().padLeft(2, '0')}'),
              ),
            ),
          ],
        ),
      ),
    ),
    if (_showParticles)
      Positioned.fill(
        child: IgnorePointer(
          child: _QiParticlesOverlay(color: cs.primary),
        ),
      ),
    ],
  );
}

  Widget _row(BuildContext context, {required IconData icon, required String title, required String desc}) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 1),
              Text(desc, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sheet Thám Hiểm Bí Cảnh
class BiCanhSheet extends ConsumerStatefulWidget {
  final Rec st;
  const BiCanhSheet({super.key, required this.st});

  @override
  ConsumerState<BiCanhSheet> createState() => _BiCanhSheetState();
}

class _BiCanhSheetState extends ConsumerState<BiCanhSheet> {
  bool _busy = false;

  Future<void> _explore(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      HapticFeedback.mediumImpact();
      final r = await cultExplore(code);
      ref.invalidate(cultStateProvider);
      ref.invalidate(cultCooldownProvider);
      final item = r['item'] as Map?;
      if (item != null) ref.invalidate(cultInventoryProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('Thám hiểm xong: +${gonSo(r['gain'] as num)} tu vi'
            '${item != null ? ' · nhặt được ${item['name']}' : ''}'),
        duration: const Duration(seconds: 3),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loiDeHieu(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = widget.st['realm'] as int;
    final ascended = widget.st['ascended_at'] != null;
    final explored = (ref.watch(cultCooldownProvider).value?['explore_at'] as Map?) ?? const {};
    final today = cultTodayVn();

    // code + minRealm PHẢI khớp bảng trong cult_explore (migration 124) — server mới là chuẩn.
    final biCanhList = [
      (
        code: 'u_minh',
        name: 'U Minh Cổ Động',
        minRealm: 1,
        hours: 1,
        desc: 'Hang động cổ xưa ẩn chứa linh khí và yêu thú sơ cấp.',
      ),
      (
        code: 'van_kiem',
        name: 'Vạn Kiếm Tiên Trủng',
        minRealm: 3,
        hours: 2,
        desc: 'Chiến trường cổ lưu lạc ngàn vạn linh kiếm và tàn kiếm.',
      ),
      (
        code: 'thai_hu',
        name: 'Thái Hư Hư Không Tháp',
        minRealm: 5,
        hours: 3,
        desc: 'Tháp ngưng đọng dòng thời gian, ngập tràn thiên đạo tàn chương.',
      ),
      (
        code: 'chu_thien',
        name: 'Chư Thiên Tinh Hải',
        minRealm: 9,
        hours: 4,
        desc: 'Vực sâu giữa các vì sao, ẩn giấu bí mật hồng mông đại đạo.',
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.explore_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Thám Hiểm Bí Cảnh', style: t.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final bc in biCanhList) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        (ascended || realm >= bc.minRealm) ? Icons.landscape_rounded : Icons.lock_outline_rounded,
                        size: 20,
                        color: (ascended || realm >= bc.minRealm) ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bc.name, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(bc.desc, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text('+${bc.hours} giờ tu vi · 25% nhặt bảo vật · 1 lần/ngày',
                              style: t.labelSmall?.copyWith(color: cs.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (explored[bc.code] == today)
                      Text('Mai quay lại',
                          style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                    else if ((ascended || realm >= bc.minRealm))
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _explore(bc.code),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Thám hiểm'),
                      )
                    else
                      Text(
                        'Cần ${realmNames[bc.minRealm - 1]}',
                        style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sheet Thành Tựu Thiên Đạo — danh sách + điều kiện do SERVER định nghĩa (cult_achievements,
/// migration 124); nhận thưởng qua RPC, PK chặn nhận trùng. 1.x lưu prefs trên máy, không thưởng.
class ThanhTuuSheet extends ConsumerStatefulWidget {
  final Rec st;
  const ThanhTuuSheet({super.key, required this.st});

  @override
  ConsumerState<ThanhTuuSheet> createState() => _ThanhTuuSheetState();
}

class _ThanhTuuSheetState extends ConsumerState<ThanhTuuSheet> {
  String? _busy; // code đang nhận

  Future<void> _claim(Rec a) async {
    if (_busy != null) return;
    setState(() => _busy = a['code'] as String);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await cultClaimAchievement(a['code'] as String);
      HapticFeedback.lightImpact();
      ref.invalidate(cultAchievementsProvider);
      ref.invalidate(cultStateProvider);
      ref.invalidate(cultInventoryProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('${a['title']}: +${gonSo(r['gain'] as num)} tu vi'
            ' · ${(r['item'] as Map?)?['name'] ?? ''}'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loiDeHieu(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final async = ref.watch(cultAchievementsProvider);
    final list = async.value ?? const <Rec>[];
    final done = list.where((a) => a['achieved'] == true).length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.military_tech_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thành Tựu Thiên Đạo', style: t.titleMedium),
                      if (list.isNotEmpty)
                        Text('$done / ${list.length} hoàn thành',
                            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (async.isLoading && list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (async.hasError && list.isEmpty)
              AppError(async.error!, onRetry: () => ref.invalidate(cultAchievementsProvider)),
            for (final a in list) _tile(context, a),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Rec a) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final achieved = a['achieved'] == true;
    final claimed = a['claimed'] == true;
    final goal = (a['goal'] as num).toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: achieved && !claimed ? cs.primary : cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            achieved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: achieved ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a['title']}',
                    style: t.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: achieved ? cs.onSurface : cs.onSurfaceVariant,
                    )),
                const SizedBox(height: 1),
                Text(
                  // mốc đếm (chương, món) thì hiện tiến độ; mốc cảnh giới chỉ cần mô tả
                  goal >= 25 && !achieved
                      ? '${a['desc']} · ${gonSo(a['progress'] as num)}/${gonSo(goal)}'
                      : '${a['desc']}',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 1),
                Text('Thưởng: ${a['hours']} giờ tu vi + 1 bảo vật',
                    style: t.labelSmall?.copyWith(color: cs.primary)),
              ],
            ),
          ),
          if (achieved)
            claimed
                ? Text('Đã nhận', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                : FilledButton.tonal(
                    onPressed: _busy == null ? () => _claim(a) : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: _busy == a['code']
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Nhận'),
                  ),
        ],
      ),
    );
  }
}

/// Hiệu ứng đốm sáng linh khí hội tụ về tâm khi tụ linh khí / thiền định
class _QiParticlesOverlay extends StatefulWidget {
  final Color color;
  const _QiParticlesOverlay({required this.color});

  @override
  State<_QiParticlesOverlay> createState() => _QiParticlesOverlayState();
}

class _QiParticlesOverlayState extends State<_QiParticlesOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: painter đổi mỗi frame suốt 600ms. Không có ranh giới thì
    // lớp chứa nó (cả sheet: chữ, nút, danh sách) bị vẽ lại theo từng frame —
    // đúng vào lúc người dùng vừa bấm nút và đang nhìn.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _QiParticlePainter(
            progress: _ctrl.value,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _QiParticlePainter extends CustomPainter {
  final double progress;
  final Color color;
  _QiParticlePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    final maxRadius = math.min(size.width, size.height) * 0.45;

    // 24 hạt linh khí xoắn ốc hội tụ về tâm
    const count = 24;
    for (var i = 0; i < count; i++) {
      final angle = (i * 2 * math.pi / count) + (progress * math.pi);
      final dist = maxRadius * (1.0 - progress);
      final x = center.dx + math.cos(angle) * dist;
      final y = center.dy + math.sin(angle) * dist;

      final alpha = (math.sin(progress * math.pi) * 0.85).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: alpha);
      final pRadius = (1.5 + 2.5 * (1.0 - progress)).clamp(1.0, 4.0);
      canvas.drawCircle(Offset(x, y), pRadius, paint);
    }

    // Quầng sáng tâm nở ra ở đoạn cuối
    if (progress > 0.4) {
      final glowProgress = (progress - 0.4) / 0.6;
      final glowAlpha = (math.sin(glowProgress * math.pi) * 0.4).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: glowAlpha);
      canvas.drawCircle(center, 40 * glowProgress, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _QiParticlePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

