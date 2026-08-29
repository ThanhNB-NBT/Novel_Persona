import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../widgets.dart';
import '../../theme.dart' show monoStyle;
import 'painters_fx.dart';
import 'pixel.dart';
import 'preview.dart';

// Painters + cảnh nhân vật động đã tách sang painters_aura/painters_fx/preview;
// export lại cho render test import thẳng cultivation.dart như cũ.
export 'preview.dart';

// ponytail: cờ toàn cục chống double-tap dùng/trang bị đồ — app 1 user, 1 màn Tu Tiên
// mở cùng lúc; nếu sau này có nhiều màn song song thì chuyển sang state cục bộ.
bool _cultItemBusy = false;

String cultivationBackgroundAsset(Brightness brightness) =>
    brightness == Brightness.dark
    ? 'assets/bg/cultivation_bg_night.webp'
    : 'assets/bg/cultivation_bg.webp';

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
  bool _advancing = false; // khóa nút đột phá/lên tầng khi RPC đang chạy

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
    if (_advancing) return; // chống double-tap: 1 lần đột phá mỗi lần bấm
    setState(() => _advancing = true);
    final major = (st['stage'] as int) >= 9; // đột phá đại cảnh giới
    try {
      final r = await cultAdvance();
      if (!mounted) return;
      // dialog trong suốt tự vẽ hiệu ứng — thành công nổ vòng xung kích vàng,
      // thất bại rung đỏ; nền mờ đậm cho cảm giác "trời long đất lở"
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'đột phá',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => _AdvanceFxDialog(
          result: r,
          major: major,
          race: st['race'] as String?,
          gender: st['gender'] as String?,
        ),
      );
      // Giữ màn Tu Tiên ở snapshot cũ trong suốt animation; chỉ hiện state server
      // mới sau khi user đóng kết quả, tránh thấy cảnh giới/exp đổi dưới lớp kiếp lôi.
      if (mounted) ref.invalidate(cultStateProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  /// Phi Thăng ở đỉnh Độ Kiếp: một trận Tâm Ma cuối, thắng thì đắc đạo thành tiên.
  Future<void> _ascend(Rec st) async {
    if (_advancing) return;
    setState(() => _advancing = true);
    try {
      final r = await cultAscend();
      if (!mounted) return;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'phi thăng',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => _AdvanceFxDialog(
          result: {
            'success': r['ascended'] == true,
            'realm': 9,
            'stage': 9,
            'chance': (r['tamma'] as Rec?)?['chance'],
            'tamma': r['tamma'],
          },
          major: true,
          ascend: true,
          race: st['race'] as String?,
          gender: st['gender'] as String?,
        ),
      );
      if (mounted) ref.invalidate(cultStateProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  /// Độ Thiên Kiếp hậu Phi Thăng: thăng một bậc tiên (không Tâm Ma, không phạt).
  Future<void> _ascendTier() async {
    if (_advancing) return;
    setState(() => _advancing = true);
    try {
      final r = await cultAscendTier();
      if (!mounted) return;
      ref.invalidate(cultStateProvider);
      final win = r['win'] == true;
      final tier = (r['tier'] as num?)?.toInt() ?? 0;
      final chance = (r['chance'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(win
              ? 'Vượt Tâm Ma ($chance%), độ thiên kiếp thành công — đăng bậc ${tienTierNames[tier]}!'
              : 'Tâm ma quấy nhiễu ($chance%), độ kiếp thất bại — hao 20% tiên nguyên. Thử lại.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cultStateProvider);
    final cs = Theme.of(context).colorScheme;
    // nền nhuốm MÀU CẢNH GIỚI (khớp quầng trời của hero stage) — chưa có
    // state thì tạm màu nhấn app, có data là cả màn liền một tông
    final realm0 = state.value?['realm'] as int?;
    final bgTint = realm0 == null ? cs.primary : gradeColor((realm0 + 1) ~/ 2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: _CultivationBackdrop(
                primary: bgTint,
                gold: cs.secondary,
                surface: cs.surface,
              ),
            ),
            // top: false — cảnh hero tự trải dưới status bar (topPad) để màu
            // liền một dải, không lộ vệt nền khác màu trên đầu nhân vật.
            SafeArea(
              top: false,
              bottom: false,
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    AppError(e, onRetry: () => ref.invalidate(cultStateProvider)),
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
                  final topPad = MediaQuery.paddingOf(context).top;
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(cultStateProvider),
                    child: ListView(
                      // hero tràn viền → bỏ padding ngang ở ListView, pad từng phần dưới
                      padding: const EdgeInsets.only(bottom: 120), // né dock
                      children: [
                        // chưa chọn chủng tộc → mời chọn (một lần duy nhất, server chặn đổi)
                        if (st['race'] == null)
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 4),
                            child: _RacePickerCard(),
                          ),
                        // có card chọn tộc phía trên thì hero khỏi ôm status bar
                        _HeroStage(
                          st: st,
                          topPad: st['race'] == null ? 0 : topPad,
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _RealmCard(
                                st: st,
                                exp: _exp,
                                busy: _advancing,
                                ascended: st['ascended_at'] != null,
                                onAdvance: () => _advance(st),
                                onAscend: () => _ascend(st),
                                onAscendTier: () => _ascendTier(),
                              ),
                              const SizedBox(height: 12),
                              _TuTienActionBar(st: st),
                              const SizedBox(height: 14),
                              const _SectionLabel(
                                'Trang bị',
                                Icons.shield_moon_outlined,
                              ),
                              const SizedBox(height: 8),
                              _EquipRow(st: st),
                              const SizedBox(height: 12),
                              _SectionLabel(
                                'Túi càn khôn',
                                Icons.backpack_rounded,
                                trailing: TextButton.icon(
                                  onPressed: () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    showDragHandle: true,
                                    builder: (_) => const _CollectionSheet(),
                                  ),
                                  icon: const Icon(
                                    Icons.grid_view_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Sưu tập'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const _InventoryGrid(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CultivationBackdrop extends StatelessWidget {
  final Color primary;
  final Color gold;
  final Color surface;
  const _CultivationBackdrop({
    required this.primary,
    required this.gold,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    final asset = cultivationBackgroundAsset(Theme.of(context).brightness);
    // gradient nhuộm màu cảnh giới — fallback khi asset nền lỗi tải.
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(primary.withValues(alpha: 0.82), surface),
            Color.alphaBlend(primary.withValues(alpha: 0.38), surface),
            Color.alphaBlend(gold.withValues(alpha: 0.09), surface),
          ],
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Nền tranh thủy mặc, lỗi tải thì tự về gradient để không vỡ màn.
        Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ],
    );
  }
}

// ---- đọc chỉ số từ state (mirror công thức server, chỉ để hiển thị) ----
num? _cpMult(Rec st) {
  final g = (st['equipped'] as Rec?)?['congphap']?['grade'] as int?;
  return const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[g];
}

/// Pill "tầng N" nhỏ cạnh tên cảnh giới. Nền kính surface đậm (không tô rc)
/// vì trời phía sau giờ CÙNG màu cảnh giới — rc trên rc là chìm nghỉm.
Widget _tangPill(BuildContext context, int stage, Color rc) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: cs.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: rc.withValues(alpha: 0.65)),
      boxShadow: [BoxShadow(color: rc.withValues(alpha: 0.30), blurRadius: 10)],
    ),
    child: Text(
      'Tầng $stage',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: rc,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
  );
}

/// Chip thông tin nhỏ (icon + chữ) trong bảng nhân vật; [on] để nhấn màu nhấn.
Widget _infoChip(
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

  showDialog(
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
                Text('${rate.toStringAsFixed(1)}/giây',
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

/// Sân khấu nhân vật tràn viền (hero stage): trời loang màu cảnh giới, cảnh
/// tu luyện phóng to ~2x bản card cũ, tên cảnh giới chữ lớn phát quang neo
/// đáy — không khung, không viền, hoà thẳng vào nền màn hình.
class _HeroStage extends ConsumerWidget {
  final Rec st;
  final double topPad; // chiều cao status bar — trời loang phủ luôn dải này
  const _HeroStage({required this.st, this.topPad = 0});

  /// Sheet admin: đổi tộc/giới tính tự do (server chỉ cho profiles.is_admin).
  void _avatarSheet(BuildContext context, WidgetRef ref) {
    var gender = (st['gender'] as String?) ?? 'nam';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Đổi dung mạo (admin)',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                for (final g in genderNames.keys)
                  ButtonSegment(value: g, label: Text(genderNames[g]!)),
              ],
              selected: {gender},
              onSelectionChanged: (s) => setSheet(() => gender = s.first),
            ),
            const SizedBox(height: 6),
            for (final r in raceNames.keys)
              ListTile(
                dense: true,
                title: Text(raceNames[r]!),
                selected: r == st['race'],
                trailing: r == st['race']
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  final nav = Navigator.of(ctx);
                  try {
                    await cultSetAvatar(r, gender);
                    ref.invalidate(cultStateProvider);
                    nav.pop();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            // Công cụ test bậc — CHỈ trong debug build (flutter run), để soi hiệu ứng
            if (kDebugMode) ...[
              const Divider(height: 24),
              Text(
                'DEV · test hiệu ứng bậc',
                style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                  color: Theme.of(ctx).colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _devChip(ctx, ref, 'Về Luyện Khí 1', 1, 1),
                  _devChip(
                    ctx,
                    ref,
                    'Đầy tu vi bậc này',
                    st['realm'] as int,
                    st['stage'] as int,
                  ),
                  _devChip(
                    ctx,
                    ref,
                    'Sẵn sàng đại cảnh giới',
                    st['realm'] as int,
                    9,
                  ),
                  _devChip(ctx, ref, 'Độ Kiếp 9 (Phi Thăng)', 9, 9),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 1 nút DEV: set realm/stage + đầy tu vi rồi refetch state (không đóng sheet
  /// để bấm liên tiếp). Chỉ dựng khi kDebugMode.
  Widget _devChip(
    BuildContext ctx,
    WidgetRef ref,
    String label,
    int realm,
    int stage,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(ctx);
        try {
          await cultDebugSet(realm, stage);
          ref.invalidate(cultStateProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Đã đặt: cảnh giới $realm · tầng $stage')),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('$e')));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = st['realm'] as int;
    final rc = gradeColor((realm + 1) ~/ 2);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;
    // hậu Phi Thăng: hiện cấp bậc tiên thay cảnh giới + đạo hiệu cõi tiên + hào quang vàng
    final ascended = st['ascended_at'] != null;
    final tienTier = (st['tien_tier'] as num?)?.toInt() ?? 0;

    return SizedBox(
      height: 372 + topPad,
      width: double.infinity,
      child: Stack(
        children: [
          // cảnh nhân vật (halo + bóng chân + sương + người) phóng to theo khung;
          // truyền đồ ĐANG ĐEO có hiển thị: vòng sáng (pháp bảo halo) + vũ khí
          Positioned.fill(
            top: topPad,
            bottom: 62,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Builder(
                builder: (_) {
                  final eq = (st['equipped'] as Rec?) ?? const {};
                  return AnimatedCultivator(
                    realm: realm,
                    race: st['race'] as String?,
                    gender: st['gender'] as String?,
                    cpCode: eq['congphap']?['code'] as String?,
                    cpElem: eq['congphap']?['effect']?['element'] as String?,
                    element: st['element'] as String?,
                    elements: (st['elements'] as List?)?.cast<String>() ?? const [],
                    halo: eq['phapbao']?['effect']?['halo'] as String?,
                    weaponSprite: eq['vukhi']?['pixel'] as String?,
                    phapbaoSprite: eq['phapbao']?['pixel'] as String?,
                    tienTier: ascended ? tienTier : -1,
                    haloWorn: st['halo_worn'] as String?,
                  );
                },
              ),
            ),
          ),
          // tên cảnh giới + tầng + đạo hiệu — neo đáy, căn giữa
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  // căn đáy → pill nằm ngang chân chữ thay vì giữa dòng
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        ascended ? tienTierNames[tienTier] : realmNames[realm - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Agbalumo: display bo tròn đậm, có dấu tiếng Việt (Đ)
                        style: GoogleFonts.agbalumo(
                          textStyle: t.headlineMedium,
                          fontSize: 32,
                          letterSpacing: 0.5,
                          color: cs.onSurface,
                          // viền sáng surface ôm chữ cho TƯƠNG PHẢN, vòng ngoài
                          // là quầng phát quang màu cảnh giới
                          shadows: [
                            Shadow(color: cs.surface, blurRadius: 8),
                            Shadow(color: cs.surface, blurRadius: 8),
                            Shadow(
                              color: rc.withValues(alpha: 0.5),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // hậu phi thăng vượt khỏi "tầng" → ẩn pill, tên bậc tiên đã đủ
                    if (!ascended) ...[
                      const SizedBox(width: 10),
                      // nhấc pill lên chút cho khớp chân chữ (line-box cao hơn baseline)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _tangPill(context, st['stage'] as int, rc),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '「${ascended ? tienDaoTitles[tienTier] : daoTitles[realm - 1]}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // serif nghiêng + viền kính surface (2 lớp bóng chồng) để nổi
                  // trên nền tranh, hết cảnh chữ trùng màu nền.
                  style: GoogleFonts.lora(
                    textStyle: t.labelMedium,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: cs.onSurface,
                    shadows: [
                      Shadow(color: cs.surface, blurRadius: 6),
                      Shadow(color: cs.surface, blurRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // admin: đổi tộc/giới tính tự do — nút mờ góc phải trên
          if (isAdmin)
            Positioned(
              top: topPad + 4,
              right: 8,
              child: IconButton(
                icon: Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: 'Đổi dung mạo (admin)',
                onPressed: () => _avatarSheet(context, ref),
              ),
            ),
          // trận pháp hào quang — góc trái trên; Tiên Nhân (hoặc admin ở bản dev) mới hiện
          if (ascended || (isAdmin && kDebugMode))
            Positioned(
              top: topPad + 4,
              left: 8,
              child: IconButton(
                icon: Icon(
                  Icons.blur_circular_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: 'Trận pháp hào quang',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true, // lưới trận cao → cho cuộn, khỏi tràn
                  builder: (_) => _HaloSheet(isAdmin: isAdmin),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chọn trận pháp hào quang (hậu Phi Thăng). User thường chỉ thấy/đội trận ĐÃ sở hữu;
/// admin (bản dev) thấy trọn bộ + nút nhận hết. Cởi = ô "Không đội".
class _HaloSheet extends ConsumerWidget {
  final bool isAdmin;
  const _HaloSheet({required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final st = ref.watch(cultStateProvider).value ?? const {};
    final owned = ((st['halos'] as List?)?.cast<String>() ?? const <String>[]).toSet();
    final worn = st['halo_worn'] as String?;
    // admin dev thấy cả bộ để test; user thường chỉ trận đã sở hữu
    final codes = (isAdmin ? tienHalos.keys : tienHalos.keys.where(owned.contains))
        .toList();

    Future<void> wear(String? code) async {
      try {
        await cultWearHalo(code);
        ref.invalidate(cultStateProvider);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Trận pháp hào quang',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isAdmin)
                  TextButton.icon(
                    icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                    label: const Text('Nhận hết'),
                    onPressed: () async {
                      try {
                        await cultAdminGrantHalos();
                        ref.invalidate(cultStateProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (codes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Chưa có trận pháp nào. Tiếp tục đọc truyện để nhận cơ duyên.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [
                // ô "Không đội"
                _haloTile(context, null, worn == null, 'Không đội', cs.onSurface,
                    () => wear(null)),
                for (final code in codes)
                  _haloTile(
                    context,
                    code,
                    worn == code,
                    haloName(code),
                    Color(tienHalos[code]!.$2),
                    () => wear(code),
                  ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _haloTile(BuildContext context, String? code, bool active, String name,
      Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color : cs.outlineVariant,
            width: active ? 2 : 1,
          ),
          color: active ? color.withValues(alpha: 0.10) : null,
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: code == null
                  ? Icon(Icons.block_rounded, color: cs.onSurfaceVariant, size: 34)
                  : Image.asset('assets/cult_halo/$code.webp', fit: BoxFit.contain),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? color : cs.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w700 : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
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
    final cs = Theme.of(context).colorScheme;
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
                // viền foil: sweep cảnh giới → vàng → xanh nhấn, xoay theo hướng nghiêng
                gradient: SweepGradient(
                  transform: GradientRotation(math.atan2(o.dy, o.dx + 0.01)),
                  colors: [
                    rc.withValues(alpha: 0.55),
                    cs.secondary.withValues(alpha: 0.40 + 0.35 * mag),
                    cs.primary.withValues(alpha: 0.40),
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
/// (Nhân vật + tên cảnh giới đã dời lên _HeroStage.)
class _RealmCard extends StatelessWidget {
  final Rec st;
  final ValueNotifier<double> exp;
  final VoidCallback onAdvance;
  final VoidCallback onAscend;
  final VoidCallback onAscendTier;
  final bool busy;
  final bool ascended;
  const _RealmCard({
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
              Color.alphaBlend(rc.withValues(alpha: 0.16), cs.surface),
              cs.surface,
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
                  _infoChip(
                    context,
                    Icons.spa_rounded,
                    rootName(elements.length, variant,
                        (st['linh_can'] as num?)?.toInt() ?? 1),
                    on: variant != null, // dị/thiên căn nổi bật
                  ),
                  if (elements.isNotEmpty)
                    _infoChip(
                      context,
                      Icons.auto_awesome_rounded,
                      'hệ ${elements.map((e) => elementNames[e]).join('·')}${match ? ' ×1.3' : ''}',
                      on: match,
                    ),
                  if (ascended && tienTier > 0)
                    _infoChip(
                      context,
                      Icons.auto_awesome_mosaic_rounded,
                      'tiên uy +${tienTier * 20}% tốc',
                      on: true,
                    ),
                  // bấm để xem chi tiết các yếu tố ảnh hưởng tốc độ tu luyện
                  _infoChip(
                    context,
                    Icons.speed_rounded,
                    '${rate.toStringAsFixed(1)}/giây',
                    on: true,
                    onTap: () => _showSpeedBreakdown(context, st),
                  ),
                  if (_cpMult(st) != null)
                    _infoChip(
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
                        color: rc.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Stack(
                        children: [
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
                                        ? (ascended
                                              ? (canTier
                                                    ? 'Viên mãn — có thể độ thiên kiếp'
                                                    : 'Hư Vô Đại Đạo Tổ · cực hạn chư thiên')
                                              : 'Viên mãn — có thể phi thăng')
                                        : 'Bình cảnh · ${major ? 'sẵn sàng đột phá' : 'sẵn sàng lên tầng'}')
                                  : '${e.floor()} / ${req.floor()}',
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

/// Dialog kết quả lên tầng/đột phá, tự vẽ hiệu ứng chạy 1 lần (~1.1s):
/// thành công = chớp sáng + vòng xung kích + 12 tia lan ra + nhân vật hiện dần;
/// thất bại = rung ngang + quầng đỏ tắt dần.
class _AdvanceFxDialog extends StatefulWidget {
  final Rec result;
  final bool major;
  final bool ascend; // phi thăng: đổi chữ + tông vàng tiên
  final String? race;
  final String? gender;
  const _AdvanceFxDialog({
    required this.result,
    required this.major,
    this.ascend = false,
    this.race,
    this.gender,
  });
  @override
  State<_AdvanceFxDialog> createState() => _AdvanceFxDialogState();
}

class _AdvanceFxDialogState extends State<_AdvanceFxDialog>
    with SingleTickerProviderStateMixin {
  static const _cloudEnd = 0.18;
  // mốc lộ kết quả — hằng dùng chung với BurstPainter (painters_fx.dart)
  static const _resultStart = advanceResultStart;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Đại cảnh giới cần đủ nhịp tụ mây → ba đạo lôi → dư chấn; tiểu cảnh giới gọn hơn.
    duration: Duration(milliseconds: widget.major ? 8000 : 1250),
  )..forward();
  bool _tammaPhase = false; // pha Tâm Ma trước khi lộ kết quả đột phá
  Timer? _tammaTimer;
  ui.FragmentShader? _shader; // nấc 2 (major); null = fallback về nấc 1

  Future<void> _loadShader() async {
    try {
      final prog = await ui.FragmentProgram.fromAsset(
        'shaders/breakthrough.frag',
      );
      if (mounted) setState(() => _shader = prog.fragmentShader());
    } catch (_) {
      // shader lỗi/thiết bị không hỗ trợ → giữ nguyên hiệu ứng nấc 1
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _impactHaptic();
    });
    if (widget.major) _loadShader(); // chỉ cảnh lớn mới cần shader
    // đại cảnh giới có Tâm Ma → diễn ~1.9s rồi mới sang kết quả đột phá
    if (widget.result['tamma'] != null) {
      _tammaPhase = true;
      HapticFeedback.mediumImpact(); // vào khảo nghiệm
      _tammaTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) {
          setState(() => _tammaPhase = false);
          _ctrl
            ..reset()
            ..forward();
        }
      });
    }
  }

  void _impactHaptic() {
    final ok = widget.result['success'] == true;
    if (!ok) {
      HapticFeedback.mediumImpact();
    } else if (widget.major) {
      HapticFeedback.heavyImpact(); // đại cảnh giới thành công = cú va chạm mạnh
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _tammaTimer?.cancel();
    _shader?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.result;
    if (_tammaPhase) return _tammaView(t, r['tamma'] as Rec);
    final ok = r['success'] == true;
    final realm = r['realm'] as int;
    final grade = (realm + 1) ~/ 2;
    final color = ok
        ? (widget.ascend
              ? gradeColor(5)
              : gradeColor(grade)) // vàng tiên khi phi thăng
        : const Color(0xFFE03131);
    // đột phá VÀO Kim Đan trở lên → thiên lôi giáng xuống (lore: kết đan dẫn kiếp)
    final loi = widget.major;

    return Stack(
      fit: StackFit.expand,
      children: [
        // FX phủ TOÀN MÀN HÌNH → vụ nổ tan vào bóng tối, không chạm mép hộp thoại
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: BurstPainter(
                _ctrl.value,
                color,
                ok,
                loi,
                major: widget.major,
                shader: _shader,
              ),
            ),
          ),
        ),
        // Asset kiếp lôi động phủ lên thiên tượng Canvas, kết thúc đúng điểm nhân vật.
        ..._tribulationOverlays(loi),
        ..._residualOverlays(ok),
        if (widget.major)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => Offstage(
              offstage: _ctrl.value >= _resultStart,
              // rung màn theo từng đạo lôi chạm đất — áp vào nhân vật đang chịu kiếp
              child: Transform.translate(
                offset: _strikeShake(_ctrl.value),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedCultivator(
                      realm: realm,
                      race: widget.race,
                      gender: widget.gender,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Nội dung (nhân vật + chữ + nút) căn giữa; chỉ phần này rung máy
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Offstage(
            offstage: widget.major && _ctrl.value < _resultStart,
            child: child,
          ),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, child) {
                final v = _ctrl.value;
                var dx = ok ? 0.0 : math.sin(v * math.pi * 10) * 8 * (1 - v);
                var dy = 0.0;
                // major thành công: cú "slam" rung mạnh tắt dần ngay khi lộ kết quả
                if (widget.major && ok) {
                  final d = v - _resultStart;
                  if (d >= 0 && d < 0.08) {
                    final sh = (1 - d / 0.08) * 9;
                    dx += math.sin(d * math.pi * 90) * sh;
                    dy += math.cos(d * math.pi * 76) * sh;
                  }
                }
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: child,
                  );
                },
                child: Padding(
                padding: const EdgeInsets.all(
                  48,
                ), // chừa chỗ cho vòng xung kích
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // nhân vật/phù hiện dần sau chớp sáng
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _ctrl,
                        curve: const Interval(0.15, 0.6, curve: Curves.easeOut),
                      ),
                      child: ok
                          ? AnimatedCultivator(
                              realm: realm,
                              race: widget.race,
                              gender: widget.gender,
                            )
                          : Image.asset(
                              'assets/cult_fx/heart_demon.webp',
                              width: 126,
                              height: 126,
                              fit: BoxFit.contain,
                            ),
                    ),
                    const SizedBox(height: 10),
                    // major thành công: tên "slam" vào (phóng to → co về, nảy) sau va chạm
                    FadeTransition(
                      opacity: widget.major && ok
                          ? CurvedAnimation(
                              parent: _ctrl,
                              curve: const Interval(0.90, 0.96),
                            )
                          : const AlwaysStoppedAnimation(1.0),
                      child: ScaleTransition(
                        scale: widget.major && ok
                            ? Tween(begin: 1.5, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: _ctrl,
                                  curve: const Interval(
                                    0.90,
                                    1.0,
                                    curve: Curves.elasticOut,
                                  ),
                                ),
                              )
                            : const AlwaysStoppedAnimation(1.0),
                        child: Text(
                          widget.ascend
                              ? (ok
                                    ? 'PHI THĂNG THÀNH CÔNG'
                                    : 'PHI THĂNG THẤT BẠI')
                              : widget.major
                              ? (ok
                                    ? (loi
                                          ? 'VƯỢT LÔI KIẾP THÀNH CÔNG'
                                          : 'ĐỘT PHÁ THÀNH CÔNG')
                                    : 'ĐỘT PHÁ THẤT BẠI')
                              : 'LÊN TẦNG',
                          style: t.titleLarge?.copyWith(
                            color: ok ? Colors.white : color,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.ascend
                          ? (ok
                                ? 'Vượt Tâm Ma cuối, độ kiếp phi thăng —\nđắc đạo thành Tiên Nhân!'
                                : 'Tâm ma còn vương, phi thăng bất thành.\nTĩnh tâm rồi thử lại.')
                          : ok
                          ? '${realmNames[realm - 1]} · tầng ${r['stage']}'
                          : loi
                          ? 'Lôi kiếp đánh rớt, tâm ma quấy nhiễu — mất 30% tu vi tầng này.\nTĩnh tâm dưỡng thương rồi thử lại!'
                          : 'Tẩu hỏa nhập ma nhẹ, mất 30% tu vi tầng này.\nTĩnh tâm tu luyện tiếp!',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    if (widget.major && !widget.ascend)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tỷ lệ lúc roll: ${r['chance']}%',
                          style: t.labelMedium?.copyWith(color: Colors.white38),
                        ),
                      ),
                    if (!widget.ascend && (r['tamma'] as Rec?)?['win'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⚔ Áp chế Tâm Ma · +15% đột phá',
                          style: t.labelMedium?.copyWith(
                            color: const Color(0xFF9775FA),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: ok && grade >= 4
                            ? Colors.black87
                            : Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        ok
                            ? (widget.ascend
                                  ? 'Đắc đạo thành tiên'
                                  : 'Tiếp tục tu luyện')
                            : 'Tĩnh tâm',
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// WebP động chứa trọn ba đạo kiếp lôi, tự giữ đúng nhịp và điểm chạm nhân vật.
  List<Widget> _tribulationOverlays(bool loi) {
    if (!loi) return const [];
    return [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final active = _ctrl.value >= _cloudEnd && _ctrl.value < _resultStart;
            if (!active) return const SizedBox.shrink();
            final stormT =
                ((_ctrl.value - _cloudEnd) / (_resultStart - _cloudEnd))
                    .clamp(0.0, 1.0)
                    .toDouble();
            return CustomPaint(
              painter: TribulationAtmospherePainter(stormT),
              child: const TribulationPreview(),
            );
          },
        ),
      ),
    ];
  }

  /// Rung màn theo từng đạo lôi chạm đất, đạo sau mạnh hơn đạo trước.
  Offset _strikeShake(double v) {
    var dx = 0.0, dy = 0.0;
    for (final (i, hit) in [0.38, 0.56, 0.74].indexed) {
      final d = v - hit;
      if (d >= 0 && d < 0.09) {
        final sh = (1 - d / 0.09) * (4 + i * 2.5);
        dx += math.sin(d * math.pi * 90) * sh;
        dy += math.cos(d * math.pi * 76) * sh;
      }
    }
    return Offset(dx, dy);
  }

  /// Hào quang + sét tàn dư chỉ xuất hiện SAU khi thành công.
  /// major: mount lúc lộ kết quả (mount muộn để Lottie tự chạy đúng lúc);
  /// minor: mount ngay từ đầu.
  List<Widget> _residualOverlays(bool ok) {
    if (!ok) return const [];
    final phase = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(_resultStart, 1, curve: Curves.easeOut),
    );
    return [
      // aura linh khí xoáy quanh nhân vật — mọi lần thành công, xoay lặp
      // liên tục tới khi đóng dialog
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) =>
              !widget.major || _ctrl.value >= _resultStart
              ? child!
              : const SizedBox.shrink(),
          child: Align(
            alignment: const Alignment(0, -0.18),
            child: FractionallySizedBox(
              widthFactor: widget.major ? 0.9 : 0.6,
              child: AspectRatio(
                aspectRatio: 1,
                child: Lottie.asset(
                  'assets/cult_fx/fx_aura.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
      if (widget.major)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Offstage(
              offstage: _ctrl.value < _resultStart,
              child: child,
            ),
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: FractionallySizedBox(
                widthFactor: 0.95,
                child: Lottie.asset(
                  'assets/cult_fx/fx_lightning.json',
                  controller: phase,
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Pha Tâm Ma (~1.9s, tự chuyển sang kết quả): linh thể co giãn và trôi nhẹ,
  /// tím đạo nếu áp chế được, đỏ ma + rung nếu bị quấy nhiễu.
  Widget _tammaView(TextTheme t, Rec tm) {
    final win = tm['win'] == true;
    final color = win ? const Color(0xFF7048E8) : const Color(0xFFC92A2A);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final v = _ctrl.value;
            final dx = win ? 0.0 : math.sin(v * math.pi * 12) * 6 * (1 - v);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: CustomPaint(
                painter: TammaPainter(v, win),
                foregroundPainter: BurstPainter(v, color, win, false),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final pulse = 1 + math.sin(_ctrl.value * math.pi * 5) * 0.06;
                    return Transform.translate(
                      offset: Offset(0, math.sin(_ctrl.value * math.pi * 3) * 7),
                      child: Transform.scale(scale: pulse, child: child),
                    );
                  },
                  child: Image.asset(
                    'assets/cult_fx/heart_demon.webp',
                    width: 126,
                    height: 126,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'TÂM MA KHẢO NGHIỆM',
                  style: t.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  win
                      ? 'Đạo tâm bất động — áp chế tâm ma!'
                      : 'Tâm thần chấn động, tâm ma trỗi dậy...',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Đạo tâm ${tm['chance']}%',
                    style: t.labelMedium?.copyWith(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
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

/// Tiêu đề mục kiểu game: thanh nhấn dọc + icon + nhãn viết hoa nhỏ.
class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  const _SectionLabel(this.title, this.icon, {this.trailing});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: t.labelSmall?.copyWith(color: cs.onSurface, letterSpacing: 1),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// Bộ sưu tập: đối chiếu catalog với lịch sử từng sở hữu. Dùng/luyện hóa hết đồ
/// không làm mất tiến độ sưu tập.
class _CollectionSheet extends ConsumerWidget {
  const _CollectionSheet();

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
                  child: _SectionLabel(
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

/// Mời chọn xuất thân (hiện khi race null): giới tính + chủng tộc — chọn MỘT
/// lần, server chặn đổi (admin đổi lại được qua nút trên hero).
class _RacePickerCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RacePickerCard> createState() => _RacePickerCardState();
}

class _RacePickerCardState extends ConsumerState<_RacePickerCard> {
  String _gender = 'nam';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn xuất thân',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onPrimaryContainer,
              ),
            ),
            Text(
              'Chủng tộc định thiên hướng cả đời tu — chọn rồi không đổi được.',
              style: t.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                for (final g in genderNames.keys)
                  ButtonSegment(value: g, label: Text(genderNames[g]!)),
              ],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
            ),
            const SizedBox(height: 10),
            for (final r in raceNames.keys)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(
                    raceNames[r]!,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(raceDescs[r]!, style: t.labelMedium),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await cultSetAvatar(r, _gender);
                      ref.invalidate(cultStateProvider);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã nhập ${raceNames[r]} — bắt đầu tu hành!',
                          ),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 5 chỉ số cơ bản (server tính, cult_stats) — pill gọn đồng bộ _infoChip,
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

/// 6 slot trang bị GỌN trên 1 hàng: chỉ icon + bonus (đang đeo) hoặc tên loại
/// (trống) — tên món, mô tả đầy đủ nằm ở popup khi tap. Trước là 2 hàng ô to
/// (icon + tên + bonus) chiếm gấp đôi chỗ.
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
    final grade = (it?['grade'] as int?) ?? 1;
    final gc = gradeColor(grade);
    return Builder(
      builder: (slotCtx) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: it == null ? null : () => _showItemPopup(slotCtx, ref, it, null),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: it != null
                  ? gc.withValues(alpha: 0.65)
                  : cs.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              it != null
                  ? PixelIcon(
                      it['pixel'] as String,
                      grade: it['grade'] as int,
                      size: 28,
                    )
                  : Icon(Icons.add_rounded, size: 22, color: cs.outlineVariant),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  it != null ? _bonus(it) : cultTypeNames[type]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.labelSmall?.copyWith(
                    fontSize: 8,
                    fontWeight: it != null ? FontWeight.w700 : FontWeight.w500,
                    color: it != null
                        ? gc
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const types = ['congphap', 'vukhi', 'phapbao', 'phapchu', 'yphuc', 'giay'];
    return Row(
      children: [
        for (final type in types) ...[
          Expanded(child: _slot(context, ref, type)),
          if (type != types.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Lưới kho đồ: ô nhỏ chỉ icon + số lượng (màu viền = phẩm), đồ ĐANG TRANG BỊ
/// được ẩn (đã hiện ở mục Trang bị); tap → popup nhỏ ngay cạnh ô.
class _InventoryGrid extends ConsumerWidget {
  const _InventoryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final inv = ref.watch(cultInventoryProvider).value ?? const <Rec>[];
    // ẩn món đang đeo — nhìn túi là biết còn gì CHƯA dùng
    final st = ref.watch(cultStateProvider).value;
    final wearing = {
      for (final e in ((st?['equipped'] as Rec?) ?? const {}).values)
        if (e != null) (e as Map)['id'] as int,
    };
    final items = [
      for (final r in inv)
        if (!wearing.contains((r['cult_items'] as Rec)['id'])) r,
    ];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            inv.isEmpty
                ? 'Kho trống — đọc truyện để gặp cơ duyên nhận bảo vật.'
                : 'Bao nhiêu bảo vật đều đã trang bị cả.',
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // khớp 6 cột hàng Trang bị → ô cùng bề rộng
        mainAxisExtent:
            58, // ponytail: khớp chiều cao ô Trang bị (_slot height 58)
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i]['cult_items'] as Rec;
        final qty = items[i]['qty'] as int;
        final grade = it['grade'] as int;
        final gc = gradeColor(grade);
        // Builder: cần context CỦA Ô để popup neo đúng cạnh ô được bấm
        return Builder(
          builder: (tileCtx) {
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showItemPopup(tileCtx, ref, it, qty),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: gc.withValues(alpha: 0.55),
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: PixelIcon(
                        it['pixel'] as String,
                        grade: grade,
                        size: 32,
                      ),
                    ),
                    if (qty > 1)
                      Positioned(
                        right: 3,
                        bottom: 2,
                        child: Text(
                          '×$qty',
                          style: t.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: gc,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Popup chi tiết vật phẩm neo NGAY CẠNH ô vừa bấm (thay bottom sheet cũ chiếm
/// cả đáy màn): tên + phẩm + hiệu ứng + mô tả, kèm dòng hành động khi mở từ túi.
/// qty null = mở từ slot đang đeo → chỉ xem.
Future<void> _showItemPopup(
  BuildContext tileCtx,
  WidgetRef ref,
  Rec it,
  int? qty,
) async {
  final cs = Theme.of(tileCtx).colorScheme;
  final t = Theme.of(tileCtx).textTheme;
  final grade = it['grade'] as int;
  // đồ tiêu hao (uống/kích hoạt): đan dược + linh thạch
  final isDan = it['type'] == 'danduoc' || it['type'] == 'linhthach';

  // vị trí ô trên màn → popup mọc từ cạnh ô
  final box = tileCtx.findRenderObject() as RenderBox;
  final overlay = Overlay.of(tileCtx).context.findRenderObject() as RenderBox;
  final rect = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: tileCtx,
    position: rect,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      PopupMenuItem(
        enabled: false,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 216),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PixelIcon(it['pixel'] as String, grade: grade, size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it['name'] as String,
                          style: t.labelLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${cultTypeNames[it['type']]} · ${gradeNames[grade - 1]}'
                          '${(qty ?? 0) > 1 ? ' · ×$qty' : ''}',
                          style: t.labelSmall?.copyWith(
                            color: gradeColor(grade),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                cultEffectText(it),
                style: t.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((it['descr'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  it['descr'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      if (qty != null)
        PopupMenuItem(
          value: 'use',
          height: 40,
          child: Row(
            children: [
              Icon(
                isDan
                    ? Icons.local_drink_rounded
                    : it['type'] == 'congphap'
                    ? Icons.menu_book_rounded
                    : Icons.shield_moon_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isDan
                    ? 'Dùng'
                    : it['type'] == 'congphap'
                    ? 'Tu học'
                    : 'Trang bị',
                style: t.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      // Bản dư (qty > 1) → luyện hóa thành tu vi; luôn chừa 1 bản
      if ((qty ?? 0) > 1)
        PopupMenuItem(
          value: 'recycle',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Text(
                'Luyện hóa ${qty! - 1} bản (+${cultRecycleGain(grade) * (qty - 1)} tu vi)',
                style: t.labelLarge?.copyWith(
                  color: cs.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  if (action == null) return;
  if (_cultItemBusy) return; // đang xử lý món trước → bỏ qua tap lặp
  _cultItemBusy = true;
  try {
    if (action == 'recycle') {
      final r = await cultRecycle(it['id'] as int);
      if (tileCtx.mounted) {
        ScaffoldMessenger.of(tileCtx).showSnackBar(
          SnackBar(
            content: Text(
              'Luyện hóa ${r['recycled']} bản → +${r['linh_khi']} tu vi',
            ),
          ),
        );
      }
    } else {
      isDan
          ? await cultUseItem(it['id'] as int)
          : await cultEquip(it['id'] as int);
    }
    ref.invalidate(cultStateProvider);
    ref.invalidate(cultInventoryProvider);
  } catch (e) {
    if (tileCtx.mounted) {
      ScaffoldMessenger.of(tileCtx).showSnackBar(SnackBar(content: Text('$e')));
    }
  } finally {
    _cultItemBusy = false;
  }
}

/// Thanh lối tắt tính năng Tu Tiên: Động Phủ, Bí Cảnh, Thành Tựu
class _TuTienActionBar extends StatelessWidget {
  final Rec st;
  const _TuTienActionBar({required this.st});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget actionCard({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: cs.primary),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        actionCard(
          icon: Icons.temple_buddhist_rounded,
          title: 'Động Phủ',
          subtitle: 'Tụ linh khí',
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _DongPhuSheet(st: st),
          ),
        ),
        const SizedBox(width: 8),
        actionCard(
          icon: Icons.explore_rounded,
          title: 'Bí Cảnh',
          subtitle: 'Thám hiểm',
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _BiCanhSheet(st: st),
          ),
        ),
        const SizedBox(width: 8),
        actionCard(
          icon: Icons.military_tech_rounded,
          title: 'Thành Tựu',
          subtitle: 'Thiên đạo',
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _ThanhTuuSheet(st: st),
          ),
        ),
      ],
    );
  }
}

/// Sheet Động Phủ: Thu nạp linh khí & Thiền định
class _DongPhuSheet extends ConsumerStatefulWidget {
  final Rec st;
  const _DongPhuSheet({required this.st});

  @override
  ConsumerState<_DongPhuSheet> createState() => _DongPhuSheetState();
}

class _DongPhuSheetState extends ConsumerState<_DongPhuSheet> {
  bool _busy = false;

  Future<void> _harvestQi(double rate) async {
    if (_busy) return;
    setState(() => _busy = true);
    final gain = (rate * 30).clamp(50, 10000).toDouble();
    try {
      HapticFeedback.mediumImpact();
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

    return SafeArea(
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
class _BiCanhSheet extends ConsumerStatefulWidget {
  final Rec st;
  const _BiCanhSheet({required this.st});

  @override
  ConsumerState<_BiCanhSheet> createState() => _BiCanhSheetState();
}

class _BiCanhSheetState extends ConsumerState<_BiCanhSheet> {
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
class _ThanhTuuSheet extends StatefulWidget {
  final Rec st;
  const _ThanhTuuSheet({required this.st});

  @override
  State<_ThanhTuuSheet> createState() => _ThanhTuuSheetState();
}

class _ThanhTuuSheetState extends State<_ThanhTuuSheet> {
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
