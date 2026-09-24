import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../widgets.dart';
import '../../theme.dart' show monoStyle;
import 'pixel.dart';
import 'silk.dart';

// ---- đọc chỉ số từ state (mirror công thức server, chỉ để hiển thị) ----
num? _cpMult(Rec st) {
  final g = (st['equipped'] as Rec?)?['congphap']?['grade'] as int?;
  return const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[g];
}

/// Chip thông tin nhỏ (icon + chữ) trong bảng nhân vật; [on] để nhấn màu nhấn.
Widget infoChip(
  BuildContext context,
  IconData icon,
  String text, {
  bool on = false,
  VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final c = on ? cs.primary : cs.onSurfaceVariant;
  final chip = Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center, // trong ô lưới thì căn giữa
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis, // chữ dài (Ngũ Hành Tạp Căn) khỏi tràn ô
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.info_outline_rounded, size: 11, color: c),
        ],
      ],
    ),
  );
  if (onTap == null) return chip;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: chip,
  );
}

/// Popup phân tích các yếu tố ảnh hưởng TỐC ĐỘ TU LUYỆN (mirror cult_base_rate 067).
/// Số tổng là 'rate' server trả; các dòng chỉ để người chơi hiểu vì sao nhanh/chậm.
void _showSpeedBreakdown(BuildContext context, Rec st) {
  final elements = (st['elements'] as List?)?.cast<String>() ?? const <String>[];
  final variant = st['variant'] as String?;
  final refine = ((st['linh_can'] as num?)?.toInt() ?? 1) - 1;
  final tienTier = (st['tien_tier'] as num?)?.toInt() ?? 0;
  final ascended = st['ascended_at'] != null;
  final eq = (st['equipped'] as Rec?) ?? const {};
  final cpGrade = (eq['congphap'] as Rec?)?['grade'] as int?;
  final cpElem = (eq['congphap'] as Rec?)?['effect']?['element'];
  final match = cpElem != null &&
      (cpElem == 'all' || variant == 'hon' || elements.contains(cpElem));
  final isMa = st['race'] == 'ma';
  final now = DateTime.now();
  final buffUntil = DateTime.tryParse(st['buff_until'] as String? ?? '');
  final stoneUntil = DateTime.tryParse(st['stone_until'] as String? ?? '');
  final buffPct = (st['buff_pct'] as num?)?.toInt() ?? 0;
  final stonePct = (st['stone_pct'] as num?)?.toInt() ?? 0;
  double ratePct = 0;
  for (final k in const ['vukhi', 'phapbao']) {
    final v = (eq[k] as Rec?)?['effect']?['rate_pct'];
    if (v is num) ratePct += v;
  }
  final rate = (st['rate'] as num).toDouble();

  final rows = <(String, String, bool)>[
    if (cpGrade != null)
      ('Công pháp (phẩm ${gradeNames[cpGrade - 1]})',
          '×${const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[cpGrade]}', true)
    else
      ('Chưa học công pháp', '×1', false),
    (
      'Hợp linh căn${match ? '' : ' (không hợp)'}',
      match ? '×1.3' : '×1',
      match
    ),
    (
      'Linh căn (${rootName(elements.length, variant, refine + 1)})',
      '×${linhCanMult(elements, variant, refine + 1).toStringAsFixed(1)}',
      variant != null,
    ),
    if (refine > 0)
      ('Luyện căn', '$refine điểm (đã gộp vào bậc)', true),
    if (isMa) ('Tà tốc Ma tộc', '×1.10', true),
    if (ascended && tienTier > 0)
      ('Tiên uy (${tienTierNames[tienTier]})',
          '×${(1 + 0.2 * tienTier).toStringAsFixed(1)}', true),
    if (ratePct > 0)
      ('Pháp khí (vũ khí·pháp bảo)', '+${ratePct.toStringAsFixed(0)}%', true),
    if (buffUntil != null && buffUntil.isAfter(now) && buffPct > 0)
      ('Đan tăng tốc', '+$buffPct%', true),
    if (stoneUntil != null && stoneUntil.isAfter(now) && stonePct > 0)
      ('Linh thạch', '+$stonePct%', true),
  ];

  showBlurDialog(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Tốc độ tu luyện'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, value, on) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: Theme.of(ctx).textTheme.bodyMedium),
                    ),
                    Text(value,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: on ? cs.primary : cs.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('Tốc độ tu luyện',
                      style: Theme.of(ctx).textTheme.titleSmall),
                ),
                Text('${gonTocDo(rate)}/giây',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        )),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      );
    },
  );
}

/// Thẻ nghiêng 3D theo điểm chạm kiểu thẻ bài holographic: nghiêng nhẹ về phía
/// ngón tay, viền foil gradient xoay theo hướng nghiêng + vệt sáng lướt mặt
/// thẻ, thả tay đàn hồi về phẳng. Dùng Listener để không tranh gesture với
/// scroll của ListView.
class _TiltCard extends StatefulWidget {
  final Color rc; // màu cảnh giới — chủ đạo của foil
  final Widget child;
  const _TiltCard({required this.rc, required this.child});
  @override
  State<_TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<_TiltCard> {
  Offset _tilt = Offset.zero; // -1..1 mỗi trục, (0,0) = phẳng

  void _set(Offset local) {
    final s = context.size;
    if (s == null) return;
    setState(
      () => _tilt = Offset(
        (local.dx / s.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / s.height * 2 - 1).clamp(-1.0, 1.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final silk = Silk.of(context);
    final rc = widget.rc;
    return Listener(
      onPointerDown: (e) => _set(e.localPosition),
      onPointerMove: (e) => _set(e.localPosition),
      onPointerUp: (_) => setState(() => _tilt = Offset.zero),
      onPointerCancel: (_) => setState(() => _tilt = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        // retarget liên tục theo _tilt → chuyển động trễ nhẹ, mượt như lò xo
        tween: Tween(begin: Offset.zero, end: _tilt),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, o, child) {
          final mag = o.distance.clamp(0.0, 1.0);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016) // perspective nhẹ
              ..rotateX(-o.dy * 0.09)
              ..rotateY(o.dx * 0.11),
            child: Container(
              padding: const EdgeInsets.all(1.4), // độ dày viền foil
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                // viền lụa thếp: sweep mực nâu → màu cảnh giới → son, xoay theo hướng nghiêng
                gradient: SweepGradient(
                  transform: GradientRotation(math.atan2(o.dy, o.dx + 0.01)),
                  colors: [
                    rc.withValues(alpha: 0.55),
                    silk.line.withValues(alpha: 0.55 + 0.35 * mag),
                    silk.seal.withValues(alpha: 0.35),
                    rc.withValues(alpha: 0.55),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: rc.withValues(alpha: 0.10 + 0.20 * mag),
                    blurRadius: 22,
                    offset: Offset(-o.dx * 6, -o.dy * 6 + 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: Stack(
                  children: [
                    child!,
                    // vệt foil trắng mờ lướt theo vị trí ngón tay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(o.dx - 0.8, o.dy - 0.8),
                              end: Alignment(o.dx + 0.8, o.dy + 0.8),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(
                                  alpha: 0.04 + 0.09 * mag,
                                ),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Bảng tu vi trong thẻ tilt: chip thông tin, buff, thanh tu vi có số nằm
/// trong thanh, nút Lên Tầng/Đột Phá, dải 5 chỉ số chiến đấu ở đáy.
/// (Nhân vật + tên cảnh giới đã dời lên HeroStage.)
class RealmCard extends StatelessWidget {
  final Rec st;
  final ValueNotifier<double> exp;
  final VoidCallback onAdvance;
  final VoidCallback onAscend;
  final VoidCallback onAscendTier;
  final bool busy;
  final bool ascended;
  const RealmCard({super.key,
    required this.st,
    required this.exp,
    required this.onAdvance,
    required this.onAscend,
    required this.onAscendTier,
    required this.busy,
    required this.ascended,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final silk = Silk.of(context);
    final realm = st['realm'] as int;
    final stage = st['stage'] as int;
    final req = (st['req'] as num).toDouble();
    final rate = (st['rate'] as num).toDouble();
    final rc = gradeColor((realm + 1) ~/ 2); // màu phẩm/cảnh giới
    final major = stage >= 9 && realm < 9;
    final peak = stage >= 9 && realm >= 9;
    final tienTier = (st['tien_tier'] as num?)?.toInt() ?? 0;
    final canTier = ascended && tienTier < tienTierMax; // còn bậc tiên để độ kiếp
    // tỷ lệ đột phá hiển thị = công thức server (đan hộ thân + pháp chú + tộc đã cộng)
    final chance = cultBreakthroughChance(st);
    final now = DateTime.now();
    final buffUntil = DateTime.tryParse(st['buff_until'] as String? ?? '');
    final stoneUntil = DateTime.tryParse(st['stone_until'] as String? ?? '');
    final cpElem = (st['equipped'] as Rec?)?['congphap']?['effect']?['element'];
    // linh căn nay là BỘ HỆ cố định (067); hợp hệ nếu công pháp trùng 1 hệ, hoặc 'all',
    // hoặc chủ nhân là Hỗn Độn linh căn (hợp mọi công pháp)
    final elements = (st['elements'] as List?)?.cast<String>() ?? const <String>[];
    final variant = st['variant'] as String?;
    final match = cpElem != null &&
        (cpElem == 'all' || variant == 'hon' || elements.contains(cpElem));
    final hasBuff =
        (buffUntil != null && buffUntil.isAfter(now)) ||
        (stoneUntil != null && stoneUntil.isAfter(now));

    return _TiltCard(
      rc: rc,
      child: Container(
        // nền đục (alphaBlend) để viền foil phía sau không lộ xuyên qua
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(rc.withValues(alpha: 0.08), silk.paper),
              silk.paperEdge,
            ],
            stops: const [0, 0.55],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          children: [
            // chip thông tin: LƯỚI 2 CỘT đều nhau — Wrap cũ xuống dòng theo
            // độ dài chữ nên hàng lệch hàng, nhìn rất bất ổn
            Builder(
              builder: (_) {
                final chips = [
                  infoChip(
                    context,
                    Icons.spa_rounded,
                    rootName(elements.length, variant,
                        (st['linh_can'] as num?)?.toInt() ?? 1),
                    on: variant != null, // dị/thiên căn nổi bật
                  ),
                  if (elements.isNotEmpty)
                    infoChip(
                      context,
                      Icons.auto_awesome_rounded,
                      'hệ ${elements.map((e) => elementNames[e]).join('·')}${match ? ' ×1.3' : ''}',
                      on: match,
                    ),
                  if (ascended && tienTier > 0)
                    infoChip(
                      context,
                      Icons.auto_awesome_mosaic_rounded,
                      'tiên uy +${tienTier * 20}% tốc',
                      on: true,
                    ),
                  // bấm để xem chi tiết các yếu tố ảnh hưởng tốc độ tu luyện
                  infoChip(
                    context,
                    Icons.speed_rounded,
                    '${gonTocDo(rate)}/giây',
                    on: true,
                    onTap: () => _showSpeedBreakdown(context, st),
                  ),
                  if (_cpMult(st) != null)
                    infoChip(
                      context,
                      Icons.menu_book_rounded,
                      'công pháp ×${_cpMult(st)}',
                    ),
                ];
                return Column(
                  children: [
                    for (var i = 0; i < chips.length; i += 2)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                        child: Row(
                          children: [
                            Expanded(child: chips[i]),
                            const SizedBox(width: 6),
                            Expanded(
                              child: i + 1 < chips.length
                                  ? chips[i + 1]
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            // 5 chỉ số nằm CÙNG KHỐI với chip (trước ở đáy thẻ sau divider —
            // tốn 1 mục riêng), style pill đồng bộ chip cho liền mạch
            const SizedBox(height: 6),
            _StatsRow(stats: (st['stats'] as Map?) ?? const {}),
            // buff có thời hạn đang chạy → chip vàng nhỏ
            if (hasBuff) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (buffUntil != null && buffUntil.isAfter(now))
                      _BuffCountdown(
                        label: 'Đan lực',
                        pct: (st['buff_pct'] as num).toInt(),
                        until: buffUntil,
                      ),
                    if (stoneUntil != null && stoneUntil.isAfter(now))
                      _BuffCountdown(
                        label: 'Linh thạch',
                        pct: (st['stone_pct'] as num).toInt(),
                        until: stoneUntil,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: exp,
              builder: (_, e, _) {
                final full = e >= req;
                return Column(
                  children: [
                    // thanh tu vi kiểu game: số / trạng thái nằm TRONG thanh
                    Container(
                      height: 22,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: silk.line.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Stack(
                        children: [
                          FractionallySizedBox(
                            widthFactor: (e / req).clamp(0.0, 1.0).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: full ? rc : silk.seal,
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              full
                                  ? (peak
                                        ? (ascended
                                              ? (canTier
                                                    ? 'Viên mãn — có thể độ thiên kiếp'
                                                    : 'Hư Vô Đại Đạo Tổ · cực hạn chư thiên')
                                              : 'Viên mãn — có thể phi thăng')
                                        : 'Bình cảnh · ${major ? 'sẵn sàng đột phá' : 'sẵn sàng lên tầng'}')
                                  : '${gonSo(e)} / ${gonSo(req)}',
                              style: monoStyle(
                                context,
                                size: 11,
                                w: FontWeight.w700,
                                color: full ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy || !full
                            ? null
                            : peak
                            ? (ascended
                                  ? (canTier ? onAscendTier : null)
                                  : onAscend)
                            : onAdvance,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                peak
                                    ? (ascended
                                          ? Icons.auto_awesome
                                          : Icons.flight_takeoff_rounded)
                                    : major
                                    ? Icons.bolt_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 18,
                              ),
                        label: Text(
                          peak
                              ? (ascended
                                    ? (canTier
                                          ? 'Độ Thiên Kiếp · ${tienTierNames[tienTier + 1]}'
                                          : 'Hư Vô Đại Đạo Tổ · Tiên đạo viên mãn')
                                    : 'Phi Thăng')
                              : major
                              ? 'Đột phá ${realmNames[realm]} ($chance%)'
                              : 'Lên tầng ${stage + 1}',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Đếm ngược hiệu ứng có thời hạn (đan dược / linh thạch) — tự vẽ lại mỗi giây.
class _BuffCountdown extends StatefulWidget {
  final String label;
  final int pct;
  final DateTime until;
  const _BuffCountdown({
    required this.label,
    required this.pct,
    required this.until,
  });
  @override
  State<_BuffCountdown> createState() => _BuffCountdownState();
}

class _BuffCountdownState extends State<_BuffCountdown> {
  late final Timer _t = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final left = widget.until.difference(DateTime.now());
    if (left.isNegative) return const SizedBox.shrink();
    final h = left.inHours, m = left.inMinutes % 60, s = left.inSeconds % 60;
    // chip vàng (secondary) — buff nổi khỏi bảng nhân vật
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            '${widget.label} +${widget.pct}% · ${h > 0 ? '${h}g ' : ''}$m′${s.toString().padLeft(2, '0')}″',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// 5 chỉ số cơ bản (server tính, cult_stats) — pill gọn đồng bộ infoChip,
/// nằm chung khối chip trong thẻ tu vi.
class _StatsRow extends StatelessWidget {
  final Map stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final key in statNames.keys) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                children: [
                  Text(
                    '${stats[key] ?? '—'}',
                    style: t.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    statNames[key]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(
                      fontSize: 8,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (key != 'than_thuc') const SizedBox(width: 6),
        ],
      ],
    );
  }
}
