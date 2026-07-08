import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../theme.dart' show monoStyle;
import 'pixel.dart';

/// Màn Tu Tiên: card cảnh giới + exp bar tick sống, nút Lên Tầng/Đột Phá,
/// 4 slot trang bị, kho đồ. Server là chuẩn (cult_state đã tick); client chỉ
/// ước lượng exp chạy mượt giữa 2 lần gọi.
class CultivationScreen extends ConsumerStatefulWidget {
  const CultivationScreen({super.key});
  @override
  ConsumerState<CultivationScreen> createState() => _CultivationScreenState();
}

class _CultivationScreenState extends ConsumerState<CultivationScreen> {
  Timer? _timer;
  final _exp = ValueNotifier<double>(0);
  double _base = 0, _rate = 0, _req = 1;
  DateTime _since = DateTime.now();

  @override
  void dispose() {
    _timer?.cancel();
    _exp.dispose();
    super.dispose();
  }

  /// Đồng bộ ước lượng client với state server vừa fetch, khởi động tick 1s.
  void _sync(Rec st) {
    _base = (st['exp'] as num).toDouble();
    _rate = (st['rate'] as num).toDouble();
    _req = (st['req'] as num).toDouble();
    _since = DateTime.now();
    _exp.value = _base.clamp(0, _req).toDouble();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final s = DateTime.now().difference(_since).inMilliseconds / 1000;
      // ponytail: bỏ qua buff hết hạn giữa chừng — lệch vài % tới lần refetch
      _exp.value = (_base + _rate * s).clamp(0, _req).toDouble();
    });
  }

  Future<void> _advance(Rec st) async {
    final major = (st['stage'] as int) >= 9; // đột phá đại cảnh giới
    try {
      final r = await cultAdvance();
      if (!mounted) return;
      ref.invalidate(cultStateProvider);
      // dialog trong suốt tự vẽ hiệu ứng — thành công nổ vòng xung kích vàng,
      // thất bại rung đỏ; nền mờ đậm cho cảm giác "trời long đất lở"
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'đột phá',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => _AdvanceFxDialog(
            result: r, major: major, race: st['race'] as String?),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cultStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tu Tiên')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (st) {
          if (st == null) {
            return Center(
              child: FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Đăng nhập để bắt đầu tu luyện'),
              ),
            );
          }
          _sync(st);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(cultStateProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), // né dock
              children: [
                // chưa chọn chủng tộc → mời chọn (một lần duy nhất, server chặn đổi)
                if (st['race'] == null) ...[
                  _RacePickerCard(),
                  const SizedBox(height: 16),
                ],
                _RealmCard(st: st, exp: _exp, onAdvance: () => _advance(st)),
                const SizedBox(height: 20),
                const _SectionLabel('Trang bị', Icons.shield_moon_outlined),
                const SizedBox(height: 12),
                _EquipRow(st: st),
                const SizedBox(height: 20),
                const _SectionLabel('Túi càn khôn', Icons.backpack_rounded),
                const SizedBox(height: 12),
                const _InventoryGrid(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- đọc chỉ số từ state (mirror công thức server, chỉ để hiển thị) ----
num? _cpMult(Rec st) {
  final g = (st['equipped'] as Rec?)?['congphap']?['grade'] as int?;
  return const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[g];
}

/// Pill "tầng N" nhỏ cạnh tên cảnh giới, tô theo màu phẩm/cảnh giới.
Widget _tangPill(BuildContext context, int stage, Color rc) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: rc.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: rc.withValues(alpha: 0.5)),
      ),
      child: Text('tầng $stage',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: rc, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
    );

/// Chip thông tin nhỏ (icon + chữ) trong bảng nhân vật; [on] để nhấn màu nhấn.
Widget _infoChip(BuildContext context, IconData icon, String text,
    {bool on = false}) {
  final cs = Theme.of(context).colorScheme;
  final c = on ? cs.primary : cs.onSurfaceVariant;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: c),
      const SizedBox(width: 4),
      Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c, fontWeight: FontWeight.w600, letterSpacing: 0)),
    ]),
  );
}

/// Bảng nhân vật kiểu game: khung viền tô theo cảnh giới + gradient nhẹ,
/// nhân vật bên trái, thông tin (tên/tầng/đạo hiệu + chip) bên phải,
/// thanh tu vi có số nằm trong thanh, buff chip, nút Lên Tầng/Đột Phá,
/// và dải 5 chỉ số chiến đấu ở đáy.
class _RealmCard extends StatelessWidget {
  final Rec st;
  final ValueNotifier<double> exp;
  final VoidCallback onAdvance;
  const _RealmCard({required this.st, required this.exp, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = st['realm'] as int;
    final stage = st['stage'] as int;
    final req = (st['req'] as num).toDouble();
    final rate = (st['rate'] as num).toDouble();
    final rc = gradeColor((realm + 1) ~/ 2); // màu phẩm/cảnh giới
    final major = stage >= 9 && realm < 9;
    final peak = stage >= 9 && realm >= 9;
    // tỷ lệ đột phá hiển thị = công thức server (đan hộ thân + pháp chú đã cộng)
    final chance = (85 -
            8 * (realm - 1) +
            (st['bt_bonus_pct'] as num? ?? 0).toInt() +
            ((st['equipped'] as Rec?)?['phapchu']?['effect']?['bt_pct'] as num? ?? 0)
                .toInt())
        .clamp(10, 100);
    final now = DateTime.now();
    final buffUntil = DateTime.tryParse(st['buff_until'] as String? ?? '');
    final stoneUntil = DateTime.tryParse(st['stone_until'] as String? ?? '');
    final cpElem = (st['equipped'] as Rec?)?['congphap']?['effect']?['element'];
    final match = cpElem != null && (cpElem == st['element'] || cpElem == 'all');
    final hasBuff = (buffUntil != null && buffUntil.isAfter(now)) ||
        (stoneUntil != null && stoneUntil.isAfter(now));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: rc.withValues(alpha: 0.45)),
        // gradient loang màu cảnh giới từ đỉnh xuống → cảm giác "bảng hero"
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [rc.withValues(alpha: 0.18), cs.surface],
          stops: const [0, 0.5],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(children: [
        Row(children: [
          // nhân vật thu nhỏ vừa khung (moon halo + linh quang theo công pháp)
          SizedBox(
            width: 118,
            height: 134,
            child: FittedBox(
              fit: BoxFit.contain,
              child: _AnimatedCultivator(
                  realm: realm,
                  race: st['race'] as String?,
                  cpCode:
                      (st['equipped'] as Rec?)?['congphap']?['code'] as String?),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(realmNames[realm - 1],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.headlineSmall?.copyWith(color: cs.onSurface)),
                ),
                const SizedBox(width: 8),
                _tangPill(context, stage, rc),
              ]),
              const SizedBox(height: 3),
              Text('「${daoTitles[realm - 1]}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium),
              const SizedBox(height: 10),
              // 3 dòng chữ cũ → chip gọn: phẩm linh căn · hệ · tốc độ · công pháp
              Wrap(spacing: 6, runSpacing: 6, children: [
                _infoChip(context, Icons.spa_rounded,
                    linhCanTier((st['linh_can'] as num).toInt())),
                if (st['element'] != null)
                  _infoChip(context, Icons.auto_awesome_rounded,
                      'hệ ${elementNames[st['element']]}${match ? ' ×1.3' : ''}',
                      on: match),
                _infoChip(context, Icons.speed_rounded,
                    '${rate.toStringAsFixed(1)}/giây',
                    on: true),
                if (_cpMult(st) != null)
                  _infoChip(context, Icons.menu_book_rounded,
                      'công pháp ×${_cpMult(st)}'),
              ]),
            ]),
          ),
        ]),
        // buff có thời hạn đang chạy → chip vàng nhỏ
        if (hasBuff) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (buffUntil != null && buffUntil.isAfter(now))
                _BuffCountdown(
                    label: 'Đan lực',
                    pct: (st['buff_pct'] as num).toInt(),
                    until: buffUntil),
              if (stoneUntil != null && stoneUntil.isAfter(now))
                _BuffCountdown(
                    label: 'Linh thạch',
                    pct: (st['stone_pct'] as num).toInt(),
                    until: stoneUntil),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        ValueListenableBuilder<double>(
          valueListenable: exp,
          builder: (_, e, _) {
            final full = e >= req;
            return Column(children: [
              // thanh tu vi kiểu game: số / trạng thái nằm TRONG thanh
              Container(
                height: 22,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: rc.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Stack(children: [
                  FractionallySizedBox(
                    widthFactor: (e / req).clamp(0.0, 1.0).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: full ? cs.primary : rc,
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      full
                          ? (peak
                              ? 'Viên mãn — chờ phi thăng'
                              : 'Bình cảnh · ${major ? 'sẵn sàng đột phá' : 'sẵn sàng lên tầng'}')
                          : '${e.floor()} / ${req.floor()}',
                      style: monoStyle(context,
                          size: 11,
                          w: FontWeight.w700,
                          color: full ? cs.onPrimary : cs.onSurface),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: full && !peak ? onAdvance : null,
                  icon: Icon(
                      major ? Icons.bolt_rounded : Icons.arrow_upward_rounded,
                      size: 18),
                  label: Text(major
                      ? 'Đột phá ${realmNames[realm]} ($chance%)'
                      : peak
                          ? 'Đỉnh Độ Kiếp'
                          : 'Lên tầng ${stage + 1}'),
                ),
              ),
            ]);
          },
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 14),
        // dải 5 chỉ số chiến đấu — đáy "bảng nhân vật" (gộp từ mục CHỈ SỐ cũ)
        _StatsRow(stats: (st['stats'] as Map?) ?? const {}),
      ]),
    );
  }
}

/// Dialog kết quả lên tầng/đột phá, tự vẽ hiệu ứng chạy 1 lần (~1.1s):
/// thành công = chớp sáng + vòng xung kích + 12 tia lan ra + nhân vật hiện dần;
/// thất bại = rung ngang + quầng đỏ tắt dần.
class _AdvanceFxDialog extends StatefulWidget {
  final Rec result;
  final bool major;
  final String? race;
  const _AdvanceFxDialog({required this.result, required this.major, this.race});
  @override
  State<_AdvanceFxDialog> createState() => _AdvanceFxDialogState();
}

class _AdvanceFxDialogState extends State<_AdvanceFxDialog>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.result;
    final ok = r['success'] == true;
    final realm = r['realm'] as int;
    final grade = (realm + 1) ~/ 2;
    final color = ok ? gradeColor(grade) : const Color(0xFFE03131);
    // đột phá VÀO Kim Đan trở lên → thiên lôi giáng xuống (lore: kết đan dẫn kiếp)
    final loi = widget.major && (ok ? realm : realm + 1) >= 3;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final v = _ctrl.value;
            // thất bại: rung ngang tắt dần trong nửa đầu
            final dx = ok ? 0.0 : math.sin(v * math.pi * 10) * 8 * (1 - v);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: CustomPaint(
                painter: _BurstPainter(v, color, ok, loi),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(48), // chừa chỗ cho vòng xung kích
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // nhân vật/phù hiện dần sau chớp sáng
              FadeTransition(
                opacity: CurvedAnimation(
                    parent: _ctrl,
                    curve: const Interval(0.15, 0.6, curve: Curves.easeOut)),
                child: ok
                    ? _AnimatedCultivator(realm: realm, race: widget.race)
                    : const PixelIcon('talisman', grade: 1, size: 80),
              ),
              const SizedBox(height: 10),
              Text(
                widget.major
                    ? (ok
                        ? (loi ? 'VƯỢT LÔI KIẾP THÀNH CÔNG' : 'ĐỘT PHÁ THÀNH CÔNG')
                        : 'ĐỘT PHÁ THẤT BẠI')
                    : 'LÊN TẦNG',
                style: t.titleLarge?.copyWith(
                    color: ok ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                ok
                    ? '${realmNames[realm - 1]} · tầng ${r['stage']}'
                    : loi
                        ? 'Lôi kiếp đánh rớt, tâm ma quấy nhiễu — mất 30% tu vi tầng này.\nTĩnh tâm dưỡng thương rồi thử lại!'
                        : 'Tẩu hỏa nhập ma nhẹ, mất 30% tu vi tầng này.\nTĩnh tâm tu luyện tiếp!',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: Colors.white70),
              ),
              if (widget.major)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Tỷ lệ lúc roll: ${r['chance']}%',
                      style: t.labelMedium?.copyWith(color: Colors.white38)),
                ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: ok && grade >= 4 ? Colors.black87 : Colors.white),
                onPressed: () => Navigator.pop(context),
                child: Text(ok ? 'Tiếp tục tu luyện' : 'Tĩnh tâm'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Chớp sáng + 2 vòng xung kích + 12 tia lan ra (thành công); quầng đỏ tắt dần (bại).
/// loi = lôi kiếp: thiên lôi vàng giáng từ trên xuống trong nửa đầu hoạt ảnh.
class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final bool ok;
  final bool loi;
  _BurstPainter(this.t, this.color, this.ok, this.loi);

  /// Một tia sét gãy khúc tất định theo seed (không random — khỏi nhảy mỗi frame).
  void _bolt(Canvas canvas, Offset from, Offset to, int seed, Paint paint) {
    final path = Path()..moveTo(from.dx, from.dy);
    const n = 5;
    for (var i = 1; i <= n; i++) {
      final b = Offset.lerp(from, to, i / n)!;
      final jit = i == n ? 0.0 : (((seed * 73 + i * 37) % 17) - 8).toDouble();
      path.lineTo(b.dx + jit, b.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // tâm hiệu ứng đặt ở giữa vùng nhân vật (phía trên cột chữ)
    final c = Offset(size.width / 2, size.height * 0.32);
    // thiên lôi: 3 tia giáng xuống trong 45% đầu, nhấp nháy rồi tắt
    if (loi && t < 0.45) {
      final a = (1 - t / 0.45) * (math.sin(t * 60) > -0.5 ? 1.0 : 0.25);
      final bolt = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFE066).withValues(alpha: a);
      for (final (i, dx) in [-38.0, 4.0, 32.0].indexed) {
        bolt.strokeWidth = i == 1 ? 2.6 : 1.6; // tia giữa to nhất
        _bolt(canvas, Offset(c.dx + dx * 1.6, 0), c + Offset(dx * 0.2, -6), i + 3, bolt);
      }
      // lóe sáng nơi sét chạm
      canvas.drawCircle(c, 10 + t * 8,
          Paint()..color = const Color(0xFFFFE066).withValues(alpha: a * 0.4));
    }
    if (!ok) {
      // quầng đỏ phụt lên rồi tắt
      final a = (1 - t) * 0.35;
      canvas.drawCircle(
          c,
          70 + t * 30,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: a),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: 100 + t * 30)));
      return;
    }
    // chớp sáng trắng 15% đầu
    if (t < 0.15) {
      canvas.drawCircle(c, 140,
          Paint()..color = Colors.white.withValues(alpha: (1 - t / 0.15) * 0.75));
    }
    // 2 vòng xung kích lan ra, mảnh dần
    for (final delay in [0.0, 0.18]) {
      final v = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (v <= 0) continue;
      canvas.drawCircle(
          c,
          20 + v * 130,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (1 - v) * 5 + 0.5
            ..color = color.withValues(alpha: (1 - v) * 0.8));
    }
    // 12 tia sáng phóng ra rồi mờ
    final ray = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: (1 - t) * 0.85);
    for (var i = 0; i < 12; i++) {
      final ang = i * math.pi / 6 + 0.26; // xoay lệch cho khỏi thẳng đứng cứng
      final dir = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c + dir * (30 + t * 95), c + dir * (46 + t * 120), ray);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Kiểu hiệu ứng quanh người theo CÔNG PHÁP đang tu (mỗi công pháp một "hệ").
enum _Aura { qi, ice, wind, earth, sword, gold, star }

/// code công pháp → (hệ hiệu ứng, màu hệ). null màu = dùng màu cảnh giới.
(_Aura, Color?) _auraFor(String? code) => switch (code) {
      'cp_huyen_bang' => (_Aura.ice, const Color(0xFF74C0FC)),
      'cp_ngu_phong' => (_Aura.wind, const Color(0xFF63E6BE)),
      'cp_huyen_thien' => (_Aura.qi, const Color(0xFF748FFC)),
      'cp_dia_sat' => (_Aura.earth, const Color(0xFFB08968)),
      'cp_luyen_the' => (_Aura.gold, const Color(0xFFFFA94D)),
      'cp_cuu_chuyen' => (_Aura.gold, const Color(0xFFFFC94D)),
      'cp_thien_cang' => (_Aura.sword, const Color(0xFFCED4DA)),
      'cp_liet_hoa' => (_Aura.gold, const Color(0xFFFF7043)),
      'cp_xich_diem' => (_Aura.gold, const Color(0xFFFF5722)),
      'cp_thanh_moc' => (_Aura.qi, const Color(0xFF69DB7C)),
      'cp_dai_dien' => (_Aura.star, const Color(0xFFB197FC)),
      'cp_hon_don' => (_Aura.star, const Color(0xFF9775FA)),
      'cp_thai_co' => (_Aura.star, const Color(0xFFFFE066)),
      _ => (_Aura.qi, null), // chưa học / công pháp nhập môn
    };

/// Bản public của nhân vật động — cho test render soi hình + có thể tái dùng nơi khác.
class CultivatorPreview extends StatelessWidget {
  final int realm;
  final String? cpCode;
  final String? race;
  const CultivatorPreview({super.key, required this.realm, this.cpCode, this.race});
  @override
  Widget build(BuildContext context) =>
      _AnimatedCultivator(realm: realm, cpCode: cpCode, race: race);
}

/// Bóng tiên nhân động: lơ lửng lên xuống, quầng thở, hiệu ứng bay theo công pháp.
/// Cảnh TIẾN HÓA theo cảnh giới: trăng to dần, đá → đài sen → kiếm bay,
/// sao trời hiện từ Hóa Thần, nhị nguyệt luân từ Đại Thừa. Lặp 4 giây.
class _AnimatedCultivator extends StatefulWidget {
  final int realm; // 1..9
  final String? cpCode; // code công pháp đang tu → kiểu hiệu ứng
  final String? race; // dáng silhouette theo chủng tộc
  const _AnimatedCultivator({required this.realm, this.cpCode, this.race});
  @override
  State<_AnimatedCultivator> createState() => _AnimatedCultivatorState();
}

class _AnimatedCultivatorState extends State<_AnimatedCultivator>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (style, elem) = _auraFor(widget.cpCode);
    final grade = (widget.realm + 1) ~/ 2;
    final color = elem ?? gradeColor(grade);
    return SizedBox(
      width: 150,
      height: 145,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          // nền: vầng trăng cảnh giới + sương trôi + quầng thở
          painter: _SkyPainter(_ctrl.value, gradeColor(grade), color, widget.realm),
          // trước: hiệu ứng công pháp bay quanh (đè lên bóng người)
          foregroundPainter: _AuraPainter(_ctrl.value, color, style),
          child: Center(
            child: Transform.translate(
              // lơ lửng: nhấp nhô ±4px theo sin
              offset: Offset(0, math.sin(_ctrl.value * 2 * math.pi) * 4),
              child: CustomPaint(
                size: const Size(96, 112),
                painter: _SilhouettePainter(
                    rim: color, realm: widget.realm, race: widget.race),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nền "thủy mặc": vầng trăng lớn màu cảnh giới sau lưng + sương mù trôi ngang
/// + quầng linh khí thở. Vẽ TRƯỚC bóng người (background painter).
class _SkyPainter extends CustomPainter {
  final double t; // 0..1
  final Color moon; // màu cảnh giới
  final Color aura; // màu hệ công pháp (quầng thở)
  final int realm; // 1..9 — trăng to dần, sao từ Hóa Thần, nhị nguyệt từ Đại Thừa
  _SkyPainter(this.t, this.moon, this.aura, this.realm);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // sao trời từ Hóa Thần (realm 5+): vị trí tất định, nhấp nháy lệch pha
    if (realm >= 5) {
      final star = Paint();
      for (var i = 0; i < (realm - 3) * 2; i++) {
        final x = (i * 53 + 17) % 140 + 5.0;
        final y = (i * 37 + 11) % 52 + 6.0;
        final tw = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 5));
        star.color = Colors.white.withValues(alpha: 0.15 + 0.35 * tw);
        canvas.drawCircle(Offset(x, y), 1.0 + tw * 0.6, star);
      }
    }
    // vầng trăng: đĩa gradient mờ + vành khuyên mảnh, ôm đầu-vai bóng người;
    // bán kính lớn dần theo cảnh giới (Luyện Khí 41 → Độ Kiếp 49)
    final mr = 40.0 + realm;
    final mc = Offset(c.dx, c.dy - 16);
    canvas.drawCircle(
        mc,
        mr + 2,
        Paint()
          ..shader = RadialGradient(colors: [
            moon.withValues(alpha: 0.34),
            moon.withValues(alpha: 0.10),
            moon.withValues(alpha: 0),
          ], stops: const [0, 0.72, 1])
              .createShader(Rect.fromCircle(center: mc, radius: mr + 2)));
    canvas.drawCircle(
        mc,
        mr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = moon.withValues(alpha: 0.55));
    // nhị nguyệt luân từ Đại Thừa (realm 8+): vành ngoài thứ hai quay lệch pha
    if (realm >= 8) {
      canvas.drawArc(
          Rect.fromCircle(center: mc, radius: mr + 6),
          t * 2 * math.pi,
          math.pi * 1.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = moon.withValues(alpha: 0.35));
    }

    // quầng linh khí thở (theo màu công pháp) — chuyển từ _AuraPainter sang đây
    // để nằm SAU bóng người, không rửa trôi silhouette
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    for (final (r0, a) in [(40.0, 0.22), (58.0, 0.10)]) {
      final r = r0 + breathe * 6;
      canvas.drawCircle(
        Offset(c.dx, c.dy + 6),
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            aura.withValues(alpha: a),
            aura.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: Offset(c.dx, c.dy + 6), radius: r)),
      );
    }

    // 3 dải sương trôi ngang, mỗi dải tốc độ/độ cao khác nhau, lượn theo sin
    final mist = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (final (i, (y, w, speed)) in [(0, (0.62, 66.0, 1.0)), (1, (0.76, 88.0, 0.6)), (2, (0.50, 52.0, 1.4))]) {
      // x chạy vòng: -w → size.width+w rồi lặp
      final x = (((t * speed + i / 3) % 1) * (size.width + 2 * w)) - w;
      mist.color = Colors.white.withValues(alpha: 0.05 + 0.02 * i);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x, size.height * y + math.sin(t * 2 * math.pi + i) * 3),
              width: w,
              height: 10),
          mist);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.t != t || old.moon != moon || old.aura != aura || old.realm != realm;
}

/// Bóng tiên nhân thủy mặc: silhouette đen ngồi kiết già, dải đai bay, viền
/// sáng bắt trăng một bên. Không mặt — không bao giờ "xấu".
/// Chỗ ngồi theo cảnh giới: mỏm đá (1-3) → đài sen (4-6) → kiếm bay (7-9).
/// Dáng theo CHỦNG TỘC (nhìn là biết, khỏi cần chữ): Nhân búi tóc + trâm ·
/// Yêu tai thú + đuôi · Ma hai sừng cong · Linh tai nhọn + vòng linh quang.
class _SilhouettePainter extends CustomPainter {
  final Color rim; // màu viền sáng (theo hệ công pháp/cảnh giới)
  final int realm; // 1..9 — quyết định chỗ ngồi
  final String? race; // null/nhan → dáng người thường
  _SilhouettePainter({required this.rim, required this.realm, this.race});

  /// Mỏm đá lơ lửng góc cạnh + 2 mảnh vụn trôi (Luyện Khí → Kim Đan).
  void _rock(Canvas canvas, double cx, Paint p, Color ink) {
    final rock = Path()
      ..moveTo(cx - 28, 102)
      ..lineTo(cx + 30, 102)
      ..lineTo(cx + 21, 109)
      ..lineTo(cx + 4, 111.5)
      ..lineTo(cx - 18, 109)
      ..lineTo(cx - 25, 105)
      ..close();
    canvas.drawPath(rock, p..color = ink.withValues(alpha: 0.95));
    canvas.drawCircle(Offset(cx - 38, 106), 2.0, p..color = ink.withValues(alpha: 0.5));
    canvas.drawCircle(Offset(cx + 39, 103), 1.5, p..color = ink.withValues(alpha: 0.4));
    // ánh trăng hắt mép trên
    canvas.drawLine(
        Offset(cx + 6, 102.5),
        Offset(cx + 29, 102.5),
        Paint()
          ..isAntiAlias = true
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = rim.withValues(alpha: 0.45));
  }

  /// Đài sen: bệ + 5 cánh nhọn chĩa lên, mép cánh viền sáng (Nguyên Anh → Luyện Hư).
  void _lotus(Canvas canvas, double cx, Paint p, Color ink) {
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, 106), width: 62, height: 10),
        p..color = ink.withValues(alpha: 0.95));
    final edge = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = rim.withValues(alpha: 0.55);
    for (var k = -2; k <= 2; k++) {
      final bx = cx + k * 13.0;
      final tipY = 96.0 + k.abs() * 1.5; // cánh giữa cao nhất
      final petal = Path()
        ..moveTo(bx - 6, 105)
        ..quadraticBezierTo(bx - 4, 99, bx, tipY)
        ..quadraticBezierTo(bx + 4, 99, bx + 6, 105)
        ..close();
      canvas.drawPath(petal, p..color = ink);
      // viền sáng mép trái mỗi cánh (phía trăng)
      canvas.drawPath(
          Path()
            ..moveTo(bx + 4.5, 100)
            ..quadraticBezierTo(bx + 2, 97.5, bx, tipY + 0.5),
          edge);
    }
  }

  /// Kiếm bay: lưỡi dài mũi chếch phải, chuôi trái, vệt kiếm quang (Hợp Thể → Độ Kiếp).
  void _sword(Canvas canvas, double cx, Paint p, Color ink) {
    final blade = Path()
      ..moveTo(cx - 40, 101.5)
      ..lineTo(cx + 38, 100)
      ..lineTo(cx + 48, 103)
      ..lineTo(cx + 38, 106)
      ..lineTo(cx - 40, 104.5)
      ..close();
    canvas.drawPath(blade, p..color = ink.withValues(alpha: 0.95));
    // hộ thủ + chuôi
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 41, 103), width: 3, height: 9),
        p..color = ink);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 46, 103), width: 8, height: 3.4),
        p..color = ink);
    // sống kiếm bắt sáng + kiếm quang kéo sau đuôi
    final gleam = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: 0.6);
    canvas.drawLine(Offset(cx - 36, 102.2), Offset(cx + 45, 102.6), gleam);
    canvas.drawLine(Offset(cx - 52, 104.5), Offset(cx - 60, 105.5),
        gleam..color = rim.withValues(alpha: 0.3)..strokeWidth = 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const ink = Color(0xFF1E1B2E); // mực — tím than gần đen, nổi trên cả 2 theme
    final cx = size.width / 2;
    final p = Paint()
      ..isAntiAlias = true
      ..color = ink;

    // chỗ ngồi lơ lửng — TÁCH KHỎI thân (hở vài px, quầng sáng lọt qua khe)
    switch ((realm + 2) ~/ 3) {
      case 1:
        _rock(canvas, cx, p, ink);
      case 2:
        _lotus(canvas, cx, p, ink);
      default:
        _sword(canvas, cx, p, ink);
    }

    // Nhân vật PIXEL theo tộc (pixel.dart) — full body ngồi thiền chính diện.
    // Rộng 66px căn giữa, đáy sprite lún nhẹ vào mặt chỗ ngồi (~y100).
    drawCultivator(
        canvas, Rect.fromLTWH(cx - 33, 30, 66, 70), race);
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.rim != rim || old.realm != realm || old.race != race;
}

/// Hiệu ứng bay quanh theo HỆ công pháp (vẽ ĐÈ lên bóng người — quầng thở
/// nằm bên _SkyPainter phía sau):
/// qi đốm sáng · ice mảnh băng · wind cung gió xoáy · earth đá vụn ·
/// sword kiếm quang · gold vòng kim quang lan · star tinh tú nhấp nháy.
class _AuraPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final _Aura style;
  _AuraPainter(this.t, this.color, this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (style) {
      case _Aura.qi:
        _dots(canvas, c);
      case _Aura.ice:
        _shards(canvas, c);
      case _Aura.wind:
        _arcs(canvas, c);
      case _Aura.earth:
        _rocks(canvas, c);
      case _Aura.sword:
        _blades(canvas, c);
      case _Aura.gold:
        _rings(canvas, c);
        _dots(canvas, c);
      case _Aura.star:
        _stars(canvas, c);
    }
  }

  Paint _glow(double alpha) => Paint()
    ..color = color.withValues(alpha: alpha)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  /// đốm linh khí chạy quỹ đạo elip (mặc định)
  void _dots(Canvas canvas, Offset c) {
    for (var i = 0; i < 3; i++) {
      final ang = (t + i / 3) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 58, math.sin(ang) * 22);
      final front = math.sin(ang) > 0;
      canvas.drawCircle(p, front ? 3 : 2, _glow(front ? 0.9 : 0.35));
    }
  }

  /// mảnh băng hình thoi xoay quanh
  void _shards(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final ang = (t + i / 5) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 56, math.sin(ang) * 26);
      final front = math.sin(ang) > 0;
      final s = front ? 4.5 : 3.0;
      final shard = Path()
        ..moveTo(p.dx, p.dy - s)
        ..lineTo(p.dx + s * 0.6, p.dy)
        ..lineTo(p.dx, p.dy + s)
        ..lineTo(p.dx - s * 0.6, p.dy)
        ..close();
      canvas.drawPath(shard, _glow(front ? 0.9 : 0.4));
    }
  }

  /// cung gió xoáy quanh người
  void _arcs(Canvas canvas, Offset c) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final start = (t + i / 3) * 2 * math.pi;
      paint
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: 0.55);
      canvas.drawArc(Rect.fromCenter(center: c, width: 112, height: 52),
          start, 1.1, false, paint);
    }
  }

  /// đá vụn lơ lửng vòng quanh chân (quỹ đạo thấp, chậm)
  void _rocks(Canvas canvas, Offset c) {
    for (var i = 0; i < 4; i++) {
      final ang = (t * 0.5 + i / 4) * 2 * math.pi;
      final p = c +
          Offset(math.cos(ang) * 54, 22 + math.sin(ang) * 10); // lửng quanh đùi
      final s = math.sin(ang) > 0 ? 3.4 : 2.4;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 1.6),
          _glow(0.75));
      canvas.restore();
    }
  }

  /// kiếm quang: vạch sáng bay tiếp tuyến quỹ đạo
  void _blades(Canvas canvas, Offset c) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final ang = (t + i / 3) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 58, math.sin(ang) * 24);
      final dir = Offset(-math.sin(ang), math.cos(ang)); // tiếp tuyến
      final front = math.sin(ang) > 0;
      paint.color = color.withValues(alpha: front ? 0.95 : 0.4);
      canvas.drawLine(p - dir * 8, p + dir * 8, paint);
      // ánh lóe đầu kiếm
      canvas.drawCircle(p + dir * 8, 1.6, _glow(front ? 0.9 : 0.4));
    }
  }

  /// vòng kim quang lan từ người ra
  void _rings(Canvas canvas, Offset c) {
    for (final off in [0.0, 0.5]) {
      final v = (t + off) % 1;
      canvas.drawOval(
          Rect.fromCenter(
              center: c + const Offset(0, 26),
              width: 40 + v * 70,
              height: (40 + v * 70) * 0.38),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (1 - v) * 2.5 + 0.5
            ..color = color.withValues(alpha: (1 - v) * 0.55));
    }
  }

  /// tinh tú nhấp nháy quanh người (chữ thập 4 cánh)
  void _stars(Canvas canvas, Offset c) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final ang = i * math.pi / 3 + 0.4;
      final r = 46.0 + 14 * ((i * 37) % 3);
      final p = c + Offset(math.cos(ang) * r, math.sin(ang) * r * 0.5);
      final tw = (0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 6))));
      final s = 2.0 + tw * 2.5;
      paint
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: tw);
      canvas.drawLine(p - Offset(s, 0), p + Offset(s, 0), paint);
      canvas.drawLine(p - Offset(0, s), p + Offset(0, s), paint);
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.t != t || old.color != color || old.style != style;
}

/// Đếm ngược hiệu ứng có thời hạn (đan dược / linh thạch) — tự vẽ lại mỗi giây.
class _BuffCountdown extends StatefulWidget {
  final String label;
  final int pct;
  final DateTime until;
  const _BuffCountdown({required this.label, required this.pct, required this.until});
  @override
  State<_BuffCountdown> createState() => _BuffCountdownState();
}

class _BuffCountdownState extends State<_BuffCountdown> {
  late final Timer _t =
      Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
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
        color: cs.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bolt_rounded, size: 12, color: cs.secondary),
        const SizedBox(width: 4),
        Text(
          '${widget.label} +${widget.pct}% · ${h > 0 ? '${h}g ' : ''}$m′${s.toString().padLeft(2, '0')}″',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.secondary, fontWeight: FontWeight.w700, letterSpacing: 0),
        ),
      ]),
    );
  }
}

/// Tiêu đề mục kiểu game: thanh nhấn dọc + icon + nhãn viết hoa nhỏ.
class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionLabel(this.title, this.icon);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Container(
        width: 3,
        height: 15,
        decoration: BoxDecoration(
            color: cs.primary, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Icon(icon, size: 16, color: cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(title.toUpperCase(),
          style: t.labelSmall?.copyWith(color: cs.onSurface, letterSpacing: 1)),
    ]);
  }
}

/// Mời chọn chủng tộc (hiện khi race null) — chọn MỘT lần, server chặn đổi.
class _RacePickerCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Chọn xuất thân',
              style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
          Text('Chủng tộc định thiên hướng cả đời tu — chọn rồi không đổi được.',
              style: t.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
          const SizedBox(height: 10),
          for (final r in raceNames.keys)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(raceNames[r]!,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text(raceDescs[r]!, style: t.labelMedium),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await cultSetRace(r);
                    ref.invalidate(cultStateProvider);
                    messenger.showSnackBar(SnackBar(
                        content: Text('Đã nhập ${raceNames[r]} — bắt đầu tu hành!')));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// 5 chỉ số cơ bản: nền theo cảnh giới + tộc + trang bị (server tính, cult_stats).
class _StatsRow extends StatelessWidget {
  final Map stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(children: [
      for (final key in statNames.keys) ...[
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(children: [
              Text('${stats[key] ?? '—'}',
                  style: t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: cs.primary)),
              Text(statNames[key]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall
                      ?.copyWith(fontSize: 8.5, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
        if (key != 'than_thuc') const SizedBox(width: 6),
      ],
    ]);
  }
}

/// 6 slot trang bị (2 hàng): công pháp/vũ khí/pháp bảo · pháp chú/y phục/hài.
/// Dưới tên hiện bonus của món đó; tap món đang đeo → popup chi tiết.
class _EquipRow extends ConsumerWidget {
  final Rec st;
  const _EquipRow({required this.st});

  /// Bonus ngắn gọn: công pháp ×N, pháp bảo +N%, pháp chú +N% ĐP, đồ chỉ số +N.
  static String _bonus(Rec it) {
    final e = (it['effect'] as Map?) ?? const {};
    if (e['rate_pct'] != null) return '+${e['rate_pct']}%';
    if (e['bt_pct'] != null) return '+${e['bt_pct']}% ĐP';
    if (e['atk'] != null) return '+${e['atk']} Công';
    if (e['def'] != null) return '+${e['def']} Thủ';
    if (e['agi'] != null) return '+${e['agi']} Thân';
    return '×${const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[it['grade']] ?? 1}';
  }

  Widget _slot(BuildContext context, WidgetRef ref, String type) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final it = ((st['equipped'] as Rec?) ?? const {})[type] as Rec?;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: it == null ? null : () => _showItemSheet(context, ref, it, null),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: it != null
                  ? gradeColor(it['grade'] as int).withValues(alpha: 0.7)
                  : cs.outlineVariant),
        ),
        child: Column(children: [
          it != null
              ? PixelIcon(it['pixel'] as String, grade: it['grade'] as int, size: 34)
              : Icon(Icons.add_rounded, size: 34, color: cs.outlineVariant),
          const SizedBox(height: 4),
          Text(it?['name'] as String? ?? cultTypeNames[type]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: t.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: it != null ? cs.onSurface : cs.onSurfaceVariant)),
          if (it != null)
            Text(_bonus(it),
                style: t.labelSmall?.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: gradeColor(it['grade'] as int))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget row(List<String> types) => Row(children: [
          for (final type in types) ...[
            Expanded(child: _slot(context, ref, type)),
            if (type != types.last) const SizedBox(width: 8),
          ],
        ]);
    return Column(children: [
      row(const ['congphap', 'vukhi', 'phapbao']),
      const SizedBox(height: 8),
      row(const ['phapchu', 'yphuc', 'giay']),
    ]);
  }
}

/// Lưới kho đồ; tap → sheet chi tiết dùng/trang bị.
class _InventoryGrid extends ConsumerWidget {
  const _InventoryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final inv = ref.watch(cultInventoryProvider).value ?? const <Rec>[];
    if (inv.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Kho trống — đọc truyện để gặp cơ duyên nhận bảo vật.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 0.82),
      itemCount: inv.length,
      itemBuilder: (context, i) {
        final it = inv[i]['cult_items'] as Rec;
        final qty = inv[i]['qty'] as int;
        final grade = it['grade'] as int;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showItemSheet(context, ref, it, qty),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: gradeColor(grade).withValues(alpha: 0.55)),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              PixelIcon(it['pixel'] as String, grade: grade, size: 36),
              const SizedBox(height: 4),
              Text(it['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(fontSize: 9.5)),
              Text('${gradeNames[grade - 1]}${qty > 1 ? ' ×$qty' : ''}',
                  style: t.labelSmall?.copyWith(
                      fontSize: 9, color: gradeColor(grade),
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      },
    );
  }
}

/// Sheet chi tiết vật phẩm: hiệu ứng + mô tả + nút Dùng (đan dược) / Trang bị / Học.
/// qty null = mở từ slot đang đeo → chỉ xem, không có nút hành động.
void _showItemSheet(BuildContext context, WidgetRef ref, Rec it, int? qty) {
  // đồ tiêu hao (uống/kích hoạt): đan dược + linh thạch
  final isDan = it['type'] == 'danduoc' || it['type'] == 'linhthach';
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final t = Theme.of(ctx).textTheme;
      final grade = it['grade'] as int;
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PixelIcon(it['pixel'] as String, grade: grade, size: 64),
          const SizedBox(height: 8),
          Text(it['name'] as String,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
              '${cultTypeNames[it['type']]} · phẩm ${gradeNames[grade - 1]}'
              '${(qty ?? 0) > 1 ? ' · còn $qty' : ''}',
              style: t.labelMedium?.copyWith(color: gradeColor(grade))),
          const SizedBox(height: 6),
          Text(cultEffectText(it),
              style: t.bodyMedium
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(it['descr'] as String? ?? '',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (qty != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  try {
                    isDan
                        ? await cultUseItem(it['id'] as int)
                        : await cultEquip(it['id'] as int);
                    ref.invalidate(cultStateProvider);
                    ref.invalidate(cultInventoryProvider);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: Text(isDan
                    ? 'Dùng'
                    : it['type'] == 'congphap'
                        ? 'Tu học'
                        : 'Trang bị'),
              ),
            ),
          ],
        ]),
      );
    },
  );
}
