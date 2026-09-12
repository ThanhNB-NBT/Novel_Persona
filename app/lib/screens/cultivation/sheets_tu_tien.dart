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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
              for (final ty in types) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: CultSectionLabel(
                    '${cultTypeNames[ty]}  '
                    '${byType[ty]!.where((it) => owned.contains(it['id'])).length}'
                    '/${byType[ty]!.length}',
                    Icons.category_rounded,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final it in byType[ty]!)
                      _CollectionTile(it: it, owned: owned.contains(it['id'])),
                  ],
                ),
              ],
            ],
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

  Future<void> _harvestQi(double rate) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showParticles = true;
    });
    final gain = (rate * 30).clamp(50, 10000).toDouble();
    try {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 600));
      ref.invalidate(cultStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tụ linh thành công: Thu nạp +${gain.toInt()} tu vi!'),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
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
    final rate = (widget.st['rate'] as num).toDouble();

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
                    desc: 'Thu nạp linh khí đất trời: +${rate.toStringAsFixed(1)} tu vi/s',
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
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _harvestQi(rate),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Thu nạp linh khí thiền định'),
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

  Future<void> _explore(String name, int baseExp) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      HapticFeedback.mediumImpact();
      final events = [
        'Thu phục yêu thú tàn hồn, cảm ngộ thiên đạo: +$baseExp tu vi!',
        'Phát hiện linh tuyền cổ tích, tâm cảnh đột phá: +${(baseExp * 1.2).toInt()} tu vi!',
        'Nhặt được di vật của tiền bối tu chân: +$baseExp tu vi!',
      ];
      final msg = events[math.Random().nextInt(events.length)];
      ref.invalidate(cultStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = widget.st['realm'] as int;

    final biCanhList = [
      (
        name: 'U Minh Cổ Động',
        minRealm: 1,
        exp: 200,
        desc: 'Hang động cổ xưa ẩn chứa linh khí và yêu thú sơ cấp.',
      ),
      (
        name: 'Vạn Kiếm Tiên Trủng',
        minRealm: 3,
        exp: 800,
        desc: 'Chiến trường cổ lưu lạc ngàn vạn linh kiếm và tàn kiếm.',
      ),
      (
        name: 'Thái Hư Hư Không Tháp',
        minRealm: 5,
        exp: 3000,
        desc: 'Tháp ngưng đọng dòng thời gian, ngập tràn thiên đạo tàn chương.',
      ),
      (
        name: 'Chư Thiên Tinh Hải',
        minRealm: 8,
        exp: 15000,
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
                        realm >= bc.minRealm ? Icons.landscape_rounded : Icons.lock_outline_rounded,
                        size: 20,
                        color: realm >= bc.minRealm ? cs.primary : cs.onSurfaceVariant,
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
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (realm >= bc.minRealm)
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _explore(bc.name, bc.exp),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Thám hiểm'),
                      )
                    else
                      Text(
                        'Cần ${realmNames[bc.minRealm]}',
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

/// Sheet Thành Tựu Thiên Đạo
class ThanhTuuSheet extends StatefulWidget {
  final Rec st;
  const ThanhTuuSheet({super.key, required this.st});

  @override
  State<ThanhTuuSheet> createState() => _ThanhTuuSheetState();
}

class _ThanhTuuSheetState extends State<ThanhTuuSheet> {
  final Set<int> _claimed = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 6; i++) {
      if (prefs.getBool('achieve_claimed_$i') == true) {
        _claimed.add(i);
      }
    }
  }

  Future<void> _claim(int index, String title) async {
    await prefs.setBool('achieve_claimed_$index', true);
    HapticFeedback.lightImpact();
    setState(() => _claimed.add(index));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã nhận thành tựu: $title!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = widget.st['realm'] as int;
    final ascended = widget.st['ascended_at'] != null;

    final achievements = [
      (title: 'Nhập Đạo Sơ Tâm', desc: 'Bắt đầu con đường tu tiên vấn đạo', achieved: true),
      (title: 'Trúc Cơ Đại Nghiệp', desc: 'Đột phá Trúc Cơ, chính thức đắc đạo', achieved: realm >= 2 || ascended),
      (title: 'Kết Đan Lôi Kiếp', desc: 'Vượt thiên lôi kiếp số, kết thành Kim Đan', achieved: realm >= 3 || ascended),
      (title: 'Nguyên Anh Bất Diệt', desc: 'Thân vẫn thần bất diệt, tu thành Nguyên Anh', achieved: realm >= 4 || ascended),
      (title: 'Độ Kiếp Phi Thăng', desc: 'Vượt cửu trọng thiên kiếp, phi thăng Tiên Giới', achieved: ascended),
      (title: 'Hư Vô Đại Đạo', desc: 'Chạm tới cảnh giới tối cao Hư Vô Đại Đạo Tổ', achieved: ascended && ((widget.st['tien_tier'] as num?)?.toInt() ?? 0) >= 9),
    ];

    final completedCount = achievements.where((a) => a.achieved).length;

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
                      Text('$completedCount / ${achievements.length} Hoàn thành', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < achievements.length; i++) ...[
              Builder(builder: (context) {
                final a = achievements[i];
                final isClaimed = _claimed.contains(i);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a.achieved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: a.achieved ? cs.primary : cs.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: t.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: a.achieved ? cs.onSurface : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(a.desc, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (a.achieved)
                        isClaimed
                            ? Text('Đã nhận', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                            : FilledButton.tonal(
                                onPressed: () => _claim(i, a.title),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Nhận'),
                              ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _QiParticlePainter(
          progress: _ctrl.value,
          color: widget.color,
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

