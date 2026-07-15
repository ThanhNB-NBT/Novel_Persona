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
import 'pixel.dart';

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
      'Linh căn (${rootName(elements.length, variant)})',
      '×${linhCanMult(elements, variant).toStringAsFixed(1)}',
      variant != null,
    ),
    if (refine > 0)
      ('Luyện căn (Tẩy Tủy Đan Lv.$refine)',
          '×${(1 + 0.1 * refine).toStringAsFixed(1)}', true),
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
                  return _AnimatedCultivator(
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
                    rootName(elements.length, variant),
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
                                                    : 'Đạo Tổ · tiên đạo viên mãn')
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
                                          : 'Đạo Tổ · Tiên đạo viên mãn')
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
  static const _resultStart = 0.86;

  late final _ctrl = AnimationController(
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
              painter: _BurstPainter(
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
                    child: _AnimatedCultivator(
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
                          ? _AnimatedCultivator(
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
            return active ? const TribulationPreview() : const SizedBox.shrink();
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
                painter: _BurstPainter(v, color, win, false),
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

/// Chớp sáng + 2 vòng xung kích + 12 tia lan ra (thành công); quầng đỏ tắt dần (bại).
/// loi = lôi kiếp: thiên lôi vàng giáng từ trên xuống trong nửa đầu hoạt ảnh.
class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final bool ok;
  final bool loi;
  final bool
  major; // true = đại cảnh giới → bản điện ảnh; false = lên tầng snappy
  final ui.FragmentShader? shader; // nấc 2: godray+bloom additive (chỉ major)
  _BurstPainter(
    this.t,
    this.color,
    this.ok,
    this.loi, {
    this.major = false,
    this.shader,
  });

  Offset _spoke(Offset c, int i, int count, double radius, double ang0) {
    final ang = ang0 + i * (math.pi * 2 / count);
    return c + Offset(math.cos(ang), math.sin(ang)) * radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Tâm nổ đặt quanh nhân vật (nội dung căn giữa màn). s = co giãn theo cỡ màn
    // để hiệu ứng KHÔNG bé tí / KHÔNG chạm cứng mép khi vẽ toàn màn hình.
    final c = Offset(size.width / 2, size.height * 0.40);
    final s = size.shortestSide;

    // Mây kiếp là các khối mây đen tụ từ hai mép vào thiên tâm, không dùng vòng cung giả.
    if (loi) {
      final gather = Curves.easeInOut.transform((t / 0.24).clamp(0.0, 1.0));
      final sky = Rect.fromLTWH(0, 0, size.width, size.height * 0.34);
      canvas.drawRect(
        sky,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF05080F).withValues(alpha: 0.82 * gather),
              const Color(0xFF111827).withValues(alpha: 0.54 * gather),
              Colors.transparent,
            ],
          ).createShader(sky),
      );
      final cloudShadow = Paint()
        ..color = const Color(0xFF070A10).withValues(alpha: 0.92 * gather)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      final cloudBody = Paint()
        ..color = const Color(0xFF1A2230).withValues(alpha: 0.88 * gather)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      for (var i = 0; i < 13; i++) {
        final targetX = (i + 0.5) * size.width / 13;
        final edgeX = i.isEven ? -s * 0.28 : size.width + s * 0.28;
        final x = edgeX + (targetX - edgeX) * gather;
        final y = s * 0.02 + (i % 4) * s * 0.07 + gather * s * 0.05;
        final w = s * (0.32 + (i % 3) * 0.07);
        final h = w * 0.60;
        final blob = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
        canvas.drawOval(blob.inflate(s * 0.035), cloudShadow);
        canvas.drawOval(blob, cloudBody);
      }
    }

    // ---- THẤT BẠI: quầng đỏ + tàn tro rơi ----
    if (!ok) {
      if (major && t < _AdvanceFxDialogState._resultStart) return;
      final resultT = major
          ? ((t - _AdvanceFxDialogState._resultStart) /
                    (1 - _AdvanceFxDialogState._resultStart))
                .clamp(0.0, 1.0)
          : t;
      final a = (1 - resultT) * 0.35;
      final failHaze = Rect.fromLTWH(0, c.dy - s * 0.18, size.width, s * 0.42);
      canvas.drawRect(
        failHaze,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              color.withValues(alpha: a),
              Colors.transparent,
            ],
          ).createShader(failHaze),
      );
      final ash = Paint()..color = color.withValues(alpha: (1 - resultT) * 0.6);
      for (var i = 0; i < 10; i++) {
        final p = _spoke(c, i, 10, s * 0.08 + resultT * s * 0.12, i.toDouble());
        canvas.drawCircle(
          Offset(p.dx, p.dy + resultT * s * 0.18),
          (1 - resultT) * 2.4,
          ash,
        );
      }
      return;
    }

    if (major && t < _AdvanceFxDialogState._resultStart) return;

    // ================= THÀNH CÔNG =================
    // bt = thời gian vụ nổ ánh sáng: minor chạy cả hoạt ảnh, major tái chuẩn
    // hoá 0..1 từ lúc lộ kết quả (sét đã dứt) để chớp/vòng/tia nổ đúng nhịp.
    final bt = major
        ? ((t - _AdvanceFxDialogState._resultStart) /
                  (1 - _AdvanceFxDialogState._resultStart))
              .clamp(0.0, 1.0)
        : t;
    // 1) HỘI TỤ linh khí: hạt xoáy vào tâm, sáng dần trước va chạm (cả lên tầng)
    final gatherEnd = major ? 0.10 : 0.28;
    if (t < gatherEnd) {
      final g = t / gatherEnd;
      final n = major ? 16 : 12;
      final gp = Paint();
      for (var i = 0; i < n; i++) {
        final p = _spoke(
          c,
          i,
          n,
          (1 - g) * s * (major ? 0.42 : 0.30) + 8,
          g * 3 + i.toDouble(),
        );
        gp.color = color.withValues(alpha: g * 0.9);
        canvas.drawCircle(p, 1.5 + g * 1.6, gp);
      }
      if (!major) {
        canvas.drawCircle(
          c,
          s * 0.32 * (1 - g),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: g * 0.4),
        );
      }
    }

    // Tiểu cảnh giới: linh văn xoay khép trận và sóng tu vi dâng lên, không dùng kiếp lôi.
    if (!major) {
      final spin = t * math.pi * 2.4;
      final runePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: (1 - t) * 0.8);
      for (final (radius, reverse) in [(s * 0.16, false), (s * 0.23, true)]) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          reverse ? -spin : spin,
          math.pi * 1.35,
          false,
          runePaint,
        );
      }
      for (var i = 0; i < 8; i++) {
        final p = _spoke(c, i, 8, s * (0.20 + 0.05 * t), spin);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(spin + i);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 5, height: 5),
          runePaint,
        );
        canvas.restore();
      }
      final waveY = c.dy + s * 0.18 - t * s * 0.48;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx, waveY), width: s * 0.34, height: 18),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t) + 0.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..color = color.withValues(alpha: (1 - t) * 0.7),
      );
    }

    // 2) CHỚP va chạm — major nổ trắng to, lên tầng lóe MÀU dịu (không chói)
    const flashLen = 0.16;
    if (bt < flashLen) {
      final ft = bt / flashLen;
      final r = s * (major ? 0.5 : 0.34);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(
                color,
                Colors.white,
                major ? 0.75 : 0.55,
              )!.withValues(alpha: (1 - ft) * (major ? 0.85 : 0.7)),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Pháp trận sau va chạm: mảnh, lệch pha, để cảm giác "khai khiếu" thay vì HUD tròn đều.
    final wheel = ((bt - 0.04) / 0.68).clamp(0.0, 1.0);
    if (wheel > 0) {
      final ease = Curves.easeOut.transform(wheel);
      final spin = bt * math.pi * (major ? 0.9 : 1.4);
      final radius = s * (0.10 + ease * (major ? 0.38 : 0.28));
      final rune = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = major ? 1.4 : 1.1
        ..color = color.withValues(alpha: (1 - wheel) * (major ? 0.72 : 0.58));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(spin);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        -math.pi * 0.82,
        math.pi * 1.48,
        false,
        rune,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.78),
        math.pi * 0.18,
        math.pi * 1.35,
        false,
        rune,
      );
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi * 2 / 12;
        final inner = radius * (0.92 + (i.isEven ? 0.02 : 0.0));
        final outer = inner + (i.isEven ? s * 0.045 : s * 0.022);
        canvas.drawLine(
          Offset(math.cos(a) * inner, math.sin(a) * inner),
          Offset(math.cos(a) * outer, math.sin(a) * outer),
          rune,
        );
      }
      canvas.restore();
    }

    // Dải khí nâng người lên sau khi phá cảnh, chạy lệch nhịp để không thành vòng loading.
    final qi = ((bt - 0.12) / 0.72).clamp(0.0, 1.0);
    if (qi > 0) {
      final qiPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = major ? 2.0 : 1.3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      for (var i = 0; i < (major ? 5 : 3); i++) {
        final phase = bt * math.pi * 2.4 + i * 1.7;
        final y = c.dy + s * 0.28 - qi * s * (0.54 + i * 0.035);
        final w = s * (0.12 + qi * 0.18);
        qiPaint.color = color.withValues(
          alpha: (1 - qi) * (major ? 0.32 : 0.24),
        );
        final path = Path()
          ..moveTo(c.dx - w, y)
          ..cubicTo(
            c.dx - w * 0.35,
            y - 9 + math.sin(phase) * 8,
            c.dx + w * 0.35,
            y + 9 + math.cos(phase) * 8,
            c.dx + w,
            y,
          );
        canvas.drawPath(path, qiPaint);
      }
    }

    // 4) TRỤ SÁNG dựng lên — major cao vút, lên tầng cột ngắn nhẹ
    {
      final pt = (bt / (major ? 0.4 : 0.6)).clamp(0.0, 1.0);
      final h =
          (major ? size.height * 0.85 : s * 0.55) *
          Curves.easeOut.transform(pt);
      final w =
          ((major ? 32.0 : 16.0) + (major ? 18 : 9) * math.sin(bt * 30).abs()) *
          (1 - pt * 0.3);
      final rect = Rect.fromLTWH(c.dx - w / 2, c.dy - h, w, h + 20);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: (1 - bt) * (major ? 0.85 : 0.6)),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, major ? 8 : 5),
      );
    }

    // 5) VÒNG XUNG KÍCH (glow, scale theo màn — major lan rộng hơn)
    for (final delay in const [0.0, 0.22]) {
      final v = ((bt - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (v <= 0) continue;
      canvas.drawCircle(
        c,
        s * 0.05 + v * s * (major ? 0.52 : 0.36),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - v) * 5 + 0.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
          ..color = color.withValues(alpha: (1 - v) * 0.8),
      );
    }

    // 6) TIA SÁNG phóng ra
    {
      final ray = Paint()
        ..strokeWidth = major ? 2.2 : 1.8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: (1 - bt) * 0.85);
      for (var i = 0; i < 14; i++) {
        final ang = i * math.pi * 2 / 14 + 0.26;
        final dir = Offset(math.cos(ang), math.sin(ang));
        canvas.drawLine(
          c + dir * (s * 0.08 + bt * s * (major ? 0.36 : 0.28)),
          c + dir * (s * 0.12 + bt * s * (major ? 0.44 : 0.34)),
          ray,
        );
      }
    }

    // 7) ĐỐM LINH KHÍ bay lên
    final emberN = major ? 20 : 12;
    final ember = Paint();
    for (var i = 0; i < emberN; i++) {
      final seed = (i * 53) % 100 / 100.0;
      final x = c.dx + ((i * 37 % 200) - 100) / 100.0 * s * 0.4 * (0.4 + seed);
      final y = c.dy + s * 0.1 - bt * s * (major ? 0.7 : 0.5) * (0.6 + seed);
      final a = (1 - bt) * 0.9 * (bt > 0.15 ? 1.0 : bt / 0.15);
      ember.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), (1 - bt) * 2.4 + 0.6, ember);
    }

    // 8) NẤC 2: shader godray + bloom phủ additive lên trên (chỉ major, sau hội tụ)
    if (shader != null && major && t > _AdvanceFxDialogState._resultStart) {
      shader!
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, (t - 0.22) / 0.78) // tái chuẩn hoá 0..1 từ lúc va chạm
        ..setFloat(3, color.r)
        ..setFloat(4, color.g)
        ..setFloat(5, color.b)
        ..setFloat(6, c.dx)
        ..setFloat(7, c.dy);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Kiểu hiệu ứng quanh người theo CÔNG PHÁP đang tu (mỗi công pháp một "hệ").
enum _Aura { qi, ice, wind, earth, sword, gold, star, fire, leaf }

/// hệ ngũ hành → (kiểu hiệu ứng, màu hệ) — nguồn màu CHÍNH của trận pháp/aura.
const _elemAura = <String, (_Aura, Color)>{
  'hoa': (_Aura.fire, Color(0xFFFF7043)),
  'thuy': (_Aura.ice, Color(0xFF74C0FC)),
  'moc': (_Aura.leaf, Color(0xFF69DB7C)),
  'kim': (_Aura.gold, Color(0xFFFFC94D)),
  'tho': (_Aura.earth, Color(0xFFB08968)),
  'all': (_Aura.star, Color(0xFFB197FC)),
};

/// Cơ chế màu trận pháp/aura, ưu tiên từ trên xuống:
/// 1. code công pháp có kiểu RIÊNG (kiếm quang, tinh tú...) → dùng override;
/// 2. hệ trong effect của công pháp (server) → tra [_elemAura];
/// 3. hệ LINH CĂN người chơi ([element]) → tra [_elemAura] — công pháp nhập
///    môn không gắn hệ (dan_khi/tho_nap) vẫn ăn màu theo người tu;
/// 4. còn lại (qi, null) → dùng màu cảnh giới.
(_Aura, Color?) _auraFor(String? code, String? cpElem, String? element) {
  final override = switch (code) {
    'cp_huyen_bang' => (_Aura.ice, const Color(0xFF74C0FC)),
    'cp_ngu_phong' => (_Aura.wind, const Color(0xFF63E6BE)),
    'cp_huyen_thien' => (_Aura.qi, const Color(0xFF748FFC)),
    'cp_dia_sat' => (_Aura.earth, const Color(0xFFB08968)),
    'cp_luyen_the' => (_Aura.gold, const Color(0xFFFFA94D)),
    'cp_cuu_chuyen' => (_Aura.gold, const Color(0xFFFFC94D)),
    'cp_thien_cang' => (_Aura.sword, const Color(0xFFCED4DA)),
    'cp_liet_hoa' => (_Aura.fire, const Color(0xFFFF7043)),
    'cp_xich_diem' => (_Aura.fire, const Color(0xFFFF5722)),
    'cp_thanh_moc' => (_Aura.leaf, const Color(0xFF69DB7C)),
    'cp_dai_dien' => (_Aura.star, const Color(0xFFB197FC)),
    'cp_hon_don' => (_Aura.star, const Color(0xFF9775FA)),
    'cp_thai_co' => (_Aura.star, const Color(0xFFFFE066)),
    _ => null,
  };
  if (override != null) return override;
  final byElem = _elemAura[cpElem] ?? _elemAura[element];
  return byElem ?? (_Aura.qi, null);
}

/// Bản public của nhân vật động — cho test render soi hình + có thể tái dùng nơi khác.
class CultivatorPreview extends StatelessWidget {
  final int realm;
  final String? cpCode;
  final String? cpElem; // hệ của công pháp (effect.element từ server)
  final String? element; // hệ LINH CĂN người chơi — fallback màu trận pháp
  final String? race;
  final String? gender;
  final String? halo; // kiểu vòng sáng (pháp bảo vòng đang đeo)
  final String? weaponSprite; // key icon vũ khí đang đeo (assets/cult_items)
  final String? phapbaoSprite; // key icon pháp bảo đang đeo — bay đối xứng
  final int tienTier; // bậc tiên hậu phi thăng (0..6); -1 = chưa phi thăng
  final List<String> elements; // bộ hệ linh căn → sương ngũ sắc
  final String? haloWorn; // mã trận pháp đang đội
  const CultivatorPreview({
    super.key,
    required this.realm,
    this.cpCode,
    this.cpElem,
    this.element,
    this.race,
    this.gender,
    this.halo,
    this.weaponSprite,
    this.phapbaoSprite,
    this.tienTier = -1,
    this.elements = const [],
    this.haloWorn,
  });
  @override
  Widget build(BuildContext context) => _AnimatedCultivator(
    realm: realm,
    cpCode: cpCode,
    cpElem: cpElem,
    element: element,
    race: race,
    gender: gender,
    halo: halo,
    weaponSprite: weaponSprite,
    phapbaoSprite: phapbaoSprite,
    tienTier: tienTier,
    elements: elements,
    haloWorn: haloWorn,
  );
}

/// Preview TĨNH 1 frame hiệu ứng đột phá tại thời điểm [t] (0..1) — cho render
/// test soi filmstrip khi sửa _BurstPainter (docs/tu-tien.md §3, bước soi PNG).
class BurstPreview extends StatelessWidget {
  final double t;
  final Color color;
  final bool ok;
  final bool loi;
  final bool major;
  const BurstPreview({
    super.key,
    required this.t,
    required this.color,
    this.ok = true,
    this.loi = false,
    this.major = false,
  });
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BurstPainter(t, color, ok, loi, major: major),
    child: const SizedBox.expand(),
  );
}

/// Asset kiếp lôi động dùng chung giữa dialog thật và render test trên khung điện thoại.
class TribulationPreview extends StatefulWidget {
  const TribulationPreview({super.key});

  @override
  State<TribulationPreview> createState() => _TribulationPreviewState();
}

class _TribulationPreviewState extends State<TribulationPreview> {
  MemoryImage? _img;

  @override
  void initState() {
    super.initState();
    rootBundle.load('assets/cult_fx/tribulation_sequence.webp').then((data) {
      if (!mounted) return;
      // Copy byte để MemoryImage có identity mới: mỗi lần đột phá luôn phát lại từ frame 0.
      setState(
        () => _img = MemoryImage(Uint8List.fromList(data.buffer.asUint8List())),
      );
    });
  }

  @override
  void dispose() {
    // identity mới mỗi lần mở → phải tự nhả, không thì mỗi lần đột phá
    // đọng thêm một codec webp ~1.2MB trong imageCache
    _img?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _img == null
      ? const SizedBox.expand()
      : Image(image: _img!, fit: BoxFit.cover, gaplessPlayback: true);
}

/// Bóng tiên nhân động: lơ lửng lên xuống, quầng thở, hiệu ứng bay theo công pháp.
/// Cảnh TIẾN HÓA theo cảnh giới: trăng to dần, đá → đài sen → kiếm bay,
/// sao trời hiện từ Hóa Thần, nhị nguyệt luân từ Đại Thừa. Lặp 4 giây.
class _AnimatedCultivator extends StatefulWidget {
  final int realm; // 1..9
  final String? cpCode; // code công pháp đang tu → kiểu hiệu ứng
  final String? cpElem; // hệ công pháp — nguồn màu chính
  final String? element; // hệ linh căn — fallback màu khi công pháp vô hệ
  final String? race; // dáng nhân vật theo chủng tộc
  final String? gender; // nam/nu — dáng + kiểu tóc
  final String? halo; // kiểu vòng sáng sau đầu (từ pháp bảo vòng)
  final String? weaponSprite; // vũ khí đang đeo bay quanh (null = không)
  final String? phapbaoSprite; // pháp bảo đang đeo bay quanh, lệch pha nửa vòng
  final int tienTier; // bậc tiên hậu phi thăng (0..6); -1 = chưa phi thăng, không hào quang
  final List<String> elements; // bộ hệ linh căn cố định → sương linh khí ngũ sắc quanh người
  final String? haloWorn; // mã trận pháp đang đội (hậu phi thăng) → vòng lớn xoay sau lưng
  const _AnimatedCultivator({
    required this.realm,
    this.cpCode,
    this.cpElem,
    this.element,
    this.race,
    this.gender,
    this.halo,
    this.weaponSprite,
    this.phapbaoSprite,
    this.tienTier = -1,
    this.elements = const [],
    this.haloWorn,
  });
  @override
  State<_AnimatedCultivator> createState() => _AnimatedCultivatorState();
}

class _AnimatedCultivatorState extends State<_AnimatedCultivator>
    with SingleTickerProviderStateMixin {
  int _elementTurn = 0;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Linh khí dùng thời gian tích luỹ để các tần số vô tỉ không bị reset sau 4s.
        _elementTurn++;
        _ctrl.forward(from: 0);
      }
    })
    ..forward();
  ui.Image? _weaponImg; // icon webp của vũ khí đang đeo, decode 1 lần
  ui.Image? _phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  ui.Image? _swordWheelImg; // kiếm luân minh họa, xoay sau đầu
  ui.Image? _haloImg; // trận pháp đang đội — vòng lớn xoay sau lưng
  // Frame idle phụ (tóc/áo lay, chớp mắt) nếu có trong bundle: đặt cạnh ảnh
  // gốc với hậu tố _f2.._f4 (vd human_male_f2.webp) là TỰ NHẬN, không cần
  // sửa code. Chưa có frame phụ → danh sách 1 phần tử, hành vi như ảnh tĩnh.
  List<String> _frames = const [];

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _loadFrames();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCultivator old) {
    super.didUpdateWidget(old);
    if (old.weaponSprite != widget.weaponSprite ||
        old.phapbaoSprite != widget.phapbaoSprite ||
        old.haloWorn != widget.haloWorn) {
      _loadIcons();
    }
    if (old.race != widget.race || old.gender != widget.gender) _loadFrames();
  }

  Future<void> _loadFrames() async {
    final base = _cultivatorAsset(widget.race, widget.gender);
    final found = [base];
    for (var i = 2; i <= 4; i++) {
      final p = base.replaceFirst('.webp', '_f$i.webp');
      try {
        await rootBundle.load(p); // chỉ dò tồn tại — decode để Image.asset lo
        found.add(p);
      } catch (_) {
        break; // frame phải liền số: thiếu _f2 thì khỏi dò _f3
      }
    }
    if (mounted) setState(() => _frames = found);
  }

  /// Painter không tự decode asset được → decode ở đây rồi truyền ui.Image vào.
  Future<void> _loadIcons() async {
    // decode SONG SONG — tuần tự sẽ dồn trễ, khung hình đầu thiếu đồ bay
    final imgs = await Future.wait([
      _decodeItem(widget.weaponSprite),
      _decodeItem(widget.phapbaoSprite),
      _decodeAsset('assets/cult_fx/sword_wheel.webp'),
      widget.haloWorn == null
          ? Future.value(null)
          : _decodeAsset('assets/cult_halo/${widget.haloWorn}.webp'),
    ]);
    if (!mounted) return;
    setState(() {
      _weaponImg = imgs[0];
      _phapbaoImg = imgs[1];
      _swordWheelImg = imgs[2];
      _haloImg = imgs[3];
    });
  }

  Future<ui.Image?> _decodeItem(String? key) async {
    if (key == null) return null;
    try {
      final data = await rootBundle.load(
        'assets/cult_items/${key == 'gourd_big' ? 'gourd' : key}.webp',
      );
      return await decodeImageFromList(data.buffer.asUint8List());
    } catch (_) {
      return null; // thiếu asset thì thôi, không vẽ món đó
    }
  }

  Future<ui.Image?> _decodeAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return decodeImageFromList(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (style, elem) = _auraFor(
      widget.cpCode,
      widget.cpElem,
      widget.element,
    );
    final grade = (widget.realm + 1) ~/ 2;
    // Nền màn hình cũng nhuộm gradeColor → vòng/trận cùng màu gốc sẽ chìm.
    // Tách tông theo chế độ nền: tối → đẩy vòng SÁNG lên (pha trắng), sáng →
    // dìm vòng ĐẬM xuống (pha đen) — vẫn giữ "họ màu" cảnh giới, chỉ lệch bậc.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final moon = Color.lerp(
      gradeColor(grade),
      dark ? Colors.white : Colors.black,
      dark ? 0.45 : 0.25,
    )!;
    final color = elem ?? moon;
    return SizedBox(
      width: 150,
      height: 145,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          // nền: halo sau đầu + trận pháp dưới chân + sương + quầng thở
          // nền nhận cả đồ bay quanh: nửa vòng SAU vẽ ở đây → bị người che thật
          painter: _SkyPainter(
            _ctrl.value,
            moon,
            color,
            widget.realm,
            halo: widget.halo,
            weaponImg: _weaponImg,
            phapbaoImg: _phapbaoImg,
            swordWheelImg: _swordWheelImg,
            tienTier: widget.tienTier,
            elements: widget.elements,
            haloImg: _haloImg,
            elementTime: _elementTurn + _ctrl.value,
          ),
          // trước: hiệu ứng công pháp + nửa vòng TRƯỚC của vũ khí/pháp bảo
          foregroundPainter: _AuraPainter(
            _ctrl.value,
            color,
            style,
            weaponImg: _weaponImg,
            phapbaoImg: _phapbaoImg,
          ),
          child: Center(
            // Ảnh chibi 1 tấm không có layer riêng → giả chuyển động bằng
            // 4 tín hiệu chồng nhau (mọi tần số là bội NGUYÊN của loop 4s):
            // trôi Lissajous, xoay quanh trục Y có phối cảnh (2.5D), nghiêng
            // Z nhẹ, và THỞ neo ở chân (giãn dọc, bụng phập phồng) thay vì
            // phóng đều cả ảnh. Bóng dưới chân bên _SkyPainter co giãn ngược
            // pha [bob] để bán cảm giác lơ lửng.
            child: Builder(
              builder: (_) {
                final ph = _ctrl.value * 2 * math.pi;
                final bob = math.sin(ph); // -1..1, cùng pha bóng dưới chân
                final breath = math.sin(ph * 2); // thở 2 nhịp mỗi vòng
                // có frame phụ → chạy ping-pong 1..n..1 (8 bước/vòng ≈ 2fps),
                // gaplessPlayback giữ frame cũ khi decode nên không nháy trắng
                final n = _frames.length;
                final asset = n <= 1
                    ? _cultivatorAsset(widget.race, widget.gender)
                    : () {
                        final step = (_ctrl.value * 8).floor() % (2 * n - 2);
                        return _frames[step < n ? step : 2 * n - 2 - step];
                      }();
                return Transform.translate(
                  offset: Offset(
                    bob * 1.5 + math.sin(ph * 2 + 0.9) * 0.7, // trôi lệch nhịp
                    10 + bob * 4,
                  ),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(
                        3,
                        2,
                        0.0015,
                      ) // phối cảnh cho rotateY có chiều sâu
                      ..rotateY(math.sin(ph + 1.1) * 0.07) // khẽ xoay người
                      ..rotateZ(bob * 0.012)
                      ..scaleByDouble(
                        1.0 - breath * 0.006,
                        1.0 + breath * 0.011,
                        1.0,
                        1.0,
                      ),
                    child: Image.asset(
                      asset,
                      width: 104,
                      height: 128,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _cultivatorAsset(String? race, String? gender) {
  final raceKey = switch (race) {
    'yeu' => 'fox',
    'ma' => 'demon',
    'linh' => 'spirit',
    _ => 'human',
  };
  final genderKey = gender == 'nu' ? 'female' : 'male';
  // CHỈ webp được bundle trong pubspec (png là file gốc, không ship)
  return 'assets/cultivators/${raceKey}_$genderKey.webp';
}

/// Nền cảnh tu luyện — vẽ TRƯỚC bóng người (background painter):
/// sao (realm 5+) → KIẾM LUÂN NGŨ SẮC sau đầu → bóng chân → quầng thở →
/// sương trôi → đom đóm linh khí.
/// Hình học khớp docs/tu-tien.md §3: canvas 150×145, đầu nhân vật ≈ (75, 37).
class _SkyPainter extends CustomPainter {
  final double t; // 0..1
  final double elementTime; // thời gian tích luỹ, không reset theo vòng idle 4s
  final Color moon; // màu cảnh giới
  final Color aura; // màu hệ công pháp (quầng thở)
  final int realm; // 1..9 — kiếm luân nhích to, sao từ Hóa Thần
  final String?
  halo; // kiểu vòng từ pháp bảo: nguyet/tinh/loi/kim — null = vòng trơn
  final ui.Image? weaponImg; // vũ khí đang đeo — nửa vòng SAU vẽ ở lớp nền này
  final ui.Image? phapbaoImg; // pháp bảo đang đeo — như trên, lệch pha nửa vòng
  final ui.Image? swordWheelImg; // kiếm luân minh họa sau đầu
  final int tienTier; // bậc tiên (0..6) → hào quang vàng sau đầu; -1 = không vẽ
  final List<String> elements; // bộ hệ linh căn → sương linh khí ngũ sắc bay quanh
  final ui.Image? haloImg; // trận pháp đang đội — vòng lớn xoay sau lưng (nền)
  _SkyPainter(
    this.t,
    this.moon,
    this.aura,
    this.realm, {
    this.halo,
    this.weaponImg,
    this.phapbaoImg,
    this.swordWheelImg,
    this.tienTier = -1,
    this.elements = const [],
    this.haloImg,
    this.elementTime = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // trận pháp hào quang đội sau lưng — lớp SÂU nhất, vòng to gần kín khung, xoay chậm
    // + thở nhẹ; nằm sau cả nhân vật nên chỉ ló vành quanh người.
    if (haloImg != null) {
      final side = size.width * (0.98 + 0.03 * math.sin(t * 2 * math.pi));
      final hc = Offset(c.dx, c.dy + 2);
      canvas.save();
      canvas.translate(hc.dx, hc.dy);
      canvas.rotate(t * 2 * math.pi * 0.08); // xoay rất chậm
      canvas.drawImageRect(
        haloImg!,
        Rect.fromLTWH(0, 0, haloImg!.width.toDouble(), haloImg!.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(
              alpha: 0.85 + 0.15 * math.sin(t * 2 * math.pi)),
      );
      canvas.restore();
    }
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

    // ---- kiếm luân ngũ sắc: quay + BÁM nhịp lơ lửng của nhân vật cho dính lưng ----
    // dùng CÙNG công thức trôi của thân người (child) để vòng dập dềnh đồng bộ,
    // bỏ hằng số +10 để giữ nguyên vị trí neo gốc, chỉ theo phần chuyển động.
    final ph = t * 2 * math.pi;
    final chBob = math.sin(ph);
    final hc = Offset(
      c.dx + chBob * 1.5 + math.sin(ph * 2 + 0.9) * 0.7,
      c.dy - 29 + chBob * 4,
    );
    _drawSwordWheel(canvas, hc, 30.0 + realm * 0.65);
    // hào quang cõi tiên hậu Phi Thăng — nằm ở lớp nền nên SAU nhân vật
    if (tienTier >= 0) _drawTienCorona(canvas, hc, tienTier);
    // sương linh khí NGŨ SẮC theo bộ hệ linh căn — mỗi hệ một đốm màu bay quanh người
    _drawElementWisps(canvas, Offset(c.dx, c.dy + 6));

    // Bỏ trận pháp: chỉ còn bóng chân để nhân vật neo vào nền tranh.
    final fc = Offset(c.dx, size.height - 13);
    final bob = math.sin(t * 2 * math.pi);
    // bóng hứng dưới chân, NGƯỢC pha với độ nhấp nhô của người (bob>0 = người
    // hạ thấp → bóng to + đậm; bay lên → nhỏ + nhạt) — bán cảm giác lơ lửng
    canvas.drawOval(
      Rect.fromCenter(center: fc, width: 30 + bob * 5, height: 7 + bob * 1.4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22 + bob * 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // quầng linh khí thở (theo màu công pháp) — nằm SAU bóng người
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    for (final (r0, a) in [(38.0, 0.20), (54.0, 0.09)]) {
      final r = r0 + breathe * 6;
      canvas.drawCircle(
        Offset(c.dx, c.dy + 14),
        r,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  aura.withValues(alpha: a),
                  aura.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(center: Offset(c.dx, c.dy + 14), radius: r),
              ),
      );
    }

    // 3 dải sương trôi ngang, mỗi dải tốc độ/độ cao khác nhau, lượn theo sin
    final mist = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (final (i, (y, w, speed)) in [
      (0, (0.62, 66.0, 1.0)),
      (1, (0.76, 88.0, 0.6)),
      (2, (0.50, 52.0, 1.4)),
    ]) {
      // x chạy vòng: -w → size.width+w rồi lặp
      final x = (((t * speed + i / 3) % 1) * (size.width + 2 * w)) - w;
      mist.color = Colors.white.withValues(alpha: 0.05 + 0.02 * i);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            x,
            size.height * y + math.sin(t * 2 * math.pi + i) * 3,
          ),
          width: w,
          height: 10,
        ),
        mist,
      );
    }

    // đom đóm linh khí bay lên — lệch pha nhau, mờ dần khi lên cao (loop khớp t)
    final mote = Paint();
    for (var i = 0; i < 10; i++) {
      final ph = (t + i / 10) % 1;
      final x =
          (i * 41 + 13) % 140 + 5 + math.sin((t * 2 + i) * 2 * math.pi) * 3;
      final tw =
          0.5 + 0.5 * math.sin((t * 3 + i / 3) * 2 * math.pi); // nhấp nháy
      mote.color = aura.withValues(alpha: (0.20 + 0.25 * tw) * (1 - ph));
      canvas.drawCircle(
        Offset(x, size.height - 8 - ph * (size.height - 30)),
        1.0 + (i % 3) * 0.35,
        mote,
      );
    }

    // đồ bay quanh đang ở nửa vòng SAU — vẽ ở lớp nền để thân người che thật
    if (weaponImg != null) {
      _drawOrbiter(canvas, t, c, aura, weaponImg!, frontLayer: false);
    }
    if (phapbaoImg != null) {
      _drawOrbiter(
        canvas,
        t,
        c,
        moon,
        phapbaoImg!,
        frontLayer: false,
        scale: 0.82,
        orbit: _orbitPhapbao,
      );
    }
  }

  void _drawSwordWheel(Canvas canvas, Offset c, double radius) {
    final img = swordWheelImg;
    if (img == null) return;
    final side = radius * 2.35;
    final speed = halo == 'loi' ? 1.5 : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi * speed);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: side, height: side),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  /// Hạt linh khí trôi quanh đan điền theo các tần số vô tỉ. Thời gian tích luỹ không
  /// reset theo vòng idle nên dòng hạt không lặp lại thành một quỹ đạo đóng hay bị giật.
  void _drawElementWisps(Canvas canvas, Offset c) {
    if (elements.isEmpty) return;
    final n = elements.length;
    final golden = (1 + math.sqrt(5)) / 2;
    for (var i = 0; i < n; i++) {
      final element = elements[i];
      final col = _elemAura[element]?.$2 ?? aura;
      final lane = i / n;
      final phase = lane * math.pi * 2;
      final direction = i.isOdd ? -1.0 : 1.0;

      Offset orbitAt(double time) {
        final wave = time * math.pi * 2;
        final a = wave * direction / golden + phase;
        final rx = 29 + 5 * math.sin(wave * golden + phase);
        final ry = 16 + 4 * math.cos(wave * math.sqrt(2) - phase);
        final side = 5 * math.sin(wave * math.sqrt(3) + phase * 0.7);
        final lift = 4 * math.cos(wave / golden - phase * 1.3);
        return Offset(
          c.dx + math.cos(a) * rx + side,
          c.dy - 4 + math.sin(a) * ry + lift,
        );
      }

      // Mỗi hệ là một dòng 6 hạt, đuôi thưa và mờ dần như linh khí tản ra.
      for (var particle = 5; particle >= 0; particle--) {
        final age = particle / 6;
        final p = orbitAt(elementTime - particle * 0.115);
        final pulse = 0.5 + 0.5 * math.sin(elementTime * 7 + particle + phase);
        final radius = 0.75 + (1 - age) * (1.35 + pulse * 0.45);
        final alpha = (1 - age) * (0.22 + pulse * 0.22);
        canvas.drawCircle(
          p,
          radius * 2.6,
          Paint()
            ..color = col.withValues(alpha: alpha * 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
        );
        canvas.drawCircle(
          p,
          radius,
          Paint()..color = col.withValues(alpha: alpha),
        );
        if (particle == 0) {
          canvas.drawCircle(
            p,
            radius * 0.42,
            Paint()..color = Colors.white.withValues(alpha: 0.72),
          );
        }
      }
    }
  }

  /// Hào quang cõi tiên: đĩa vàng ấm + tia sáng xoay quanh đầu, càng lên bậc (tier)
  /// càng nhiều tia + rực hơn. Vẽ ở lớp nền → nằm SAU nhân vật.
  void _drawTienCorona(Canvas canvas, Offset hc, int tier) {
    const gold = Color(0xFFFFD25A);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final r = 22.0 + tier * 1.5;
    canvas.drawCircle(
      hc,
      r,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                gold.withValues(alpha: 0.22 + 0.05 * tier),
                gold.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: hc, radius: r)),
    );
    final rays = 8 + tier * 2;
    final len = 20.0 + tier * 3 + pulse * 4;
    final ray = Paint()
      ..color = gold.withValues(alpha: 0.30 + 0.04 * tier)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(hc.dx, hc.dy);
    canvas.rotate(t * 2 * math.pi * 0.15); // xoay chậm
    for (var i = 0; i < rays; i++) {
      final a = i / rays * 2 * math.pi;
      final r0 = r + 2;
      final r1 = r + len * (0.7 + 0.3 * math.sin(a * 3 + t * 6));
      canvas.drawLine(
        Offset(math.cos(a) * r0, math.sin(a) * r0),
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        ray,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.t != t ||
      old.elementTime != elementTime ||
      old.moon != moon ||
      old.aura != aura ||
      old.realm != realm ||
      old.halo != halo ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg ||
      old.swordWheelImg != swordWheelImg ||
      old.tienTier != tienTier ||
      old.haloImg != haloImg ||
      old.elements.join() != elements.join();
}

/// Quỹ đạo VŨ KHÍ: vòng ngang quanh eo, góc quét đều nhưng bán kính + cao độ
/// dao động theo sin TẦN SỐ LỆCH NHAU (đường Lissajous) → quỹ tích bất quy
/// tắc như "ý niệm điều khiển", không phải vòng tròn máy móc.
/// Trả về (vị trí, đang ở nửa TRƯỚC người hay không).
(Offset, bool) _orbit(double t, Offset c) {
  final a = t * 2 * math.pi;
  final r = 44 + 10 * math.sin(a * 3 + 1.3);
  return (
    Offset(
      c.dx + math.cos(a) * r,
      c.dy - 6 + math.sin(a) * r * 0.40 + math.sin(a * 2 + 0.7) * 6,
    ),
    math.sin(a) > 0, // nửa vòng dưới coi như bay TRƯỚC người
  );
}

/// Quỹ đạo PHÁP BẢO: TRỤC KHÁC HẲN vũ khí — ellipse dựng đứng hơn, NGHIÊNG
/// chéo ~29°, tâm nâng lên ngang ngực, quay NGƯỢC chiều, bán kính thở theo
/// tần số khác → hai món không bao giờ trùng nhịp hay trùng đường.
(Offset, bool) _orbitPhapbao(double t, Offset c) {
  final a = -t * 2 * math.pi + 2.6; // ngược chiều, mọc lệch góc so với vũ khí
  final r = 34 + 8 * math.sin(a * 2 + 0.5);
  final raw = Offset(math.cos(a) * r * 0.55, math.sin(a) * r * 0.72);
  const ct = 0.8776, st = 0.4794; // cos/sin 0.5 rad — góc nghiêng trục
  return (
    c + Offset(raw.dx * ct - raw.dy * st, -10 + raw.dx * st + raw.dy * ct),
    raw.dy > 0, // nửa thấp của vòng chéo coi như TRƯỚC người
  );
}

/// Vẽ 1 món bay quanh + vệt đuôi theo quỹ đạo [orbit], TÁCH LỚP: nửa vòng sau
/// gọi từ _SkyPainter (dưới ảnh nhân vật → thân che thật), nửa trước từ
/// _AuraPainter.
void _drawOrbiter(
  Canvas canvas,
  double t,
  Offset c,
  Color color,
  ui.Image img, {
  required bool frontLayer,
  double scale = 1,
  (Offset, bool) Function(double, Offset) orbit = _orbit,
}) {
  final (p, front) = orbit(t, c);
  if (front != frontLayer) return;
  // đuôi kiếm quang: lấy lại vị trí các pha ngay trước → chuỗi đốm nhỏ mờ dần
  final tail = Paint();
  for (var k = 6; k >= 1; k--) {
    final (q, _) = orbit(t - k * 0.013, c);
    tail.color = color.withValues(alpha: 0.30 * (1 - k / 7));
    canvas.drawCircle(q, (2.4 - k * 0.28) * scale, tail);
  }
  // ra sau nhỏ lại một chút cho có chiều sâu
  final side = (front ? 26.0 : 21.0) * scale;
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromCenter(center: p, width: side, height: side),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: front ? 1 : 0.88),
  );
}

/// Hiệu ứng bay quanh theo HỆ công pháp (vẽ ĐÈ lên bóng người — quầng thở
/// nằm bên _SkyPainter phía sau):
/// qi đốm sáng · ice mảnh băng · wind cung gió xoáy · earth đá vụn ·
/// sword kiếm quang · gold vòng kim quang lan · star tinh tú nhấp nháy ·
/// fire lưỡi lửa bốc lên · leaf lá cuốn theo gió.
/// Kèm VŨ KHÍ ĐANG ĐEO bay quanh người (quỹ đạo Lissajous — không tròn đều).
class _AuraPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final _Aura style;
  final ui.Image? weaponImg; // icon vũ khí đang đeo — null = không vẽ
  final ui.Image? phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  _AuraPainter(
    this.t,
    this.color,
    this.style, {
    this.weaponImg,
    this.phapbaoImg,
  });

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
        _dots(canvas, c); // bỏ _rings (vòng ellip lan từng đợt) theo yêu cầu
      case _Aura.star:
        _stars(canvas, c);
      case _Aura.fire:
        _flames(canvas, c);
      case _Aura.leaf:
        _leaves(canvas, c);
    }
    if (weaponImg != null) {
      _drawOrbiter(canvas, t, c, color, weaponImg!, frontLayer: true);
    }
    if (phapbaoImg != null) {
      _drawOrbiter(
        canvas,
        t,
        c,
        color,
        phapbaoImg!,
        frontLayer: true,
        scale: 0.82,
        orbit: _orbitPhapbao,
      );
    }
  }

  /// lưỡi lửa bốc từ quanh thân lên, lắc ngang + nhỏ dần khi lên cao
  void _flames(Canvas canvas, Offset c) {
    for (var i = 0; i < 6; i++) {
      final ph = (t * 2 + i / 6) % 1; // 2 đợt/loop
      final x =
          c.dx + ((i * 29) % 76 - 38) + math.sin((t + i) * 2 * math.pi) * 4;
      final y = c.dy + 34 - ph * 66;
      final s = (1 - ph) * 4.2 + 0.8;
      final flame = Path()
        ..moveTo(x, y - s * 1.7)
        ..quadraticBezierTo(x + s, y - s * 0.3, x, y + s)
        ..quadraticBezierTo(x - s, y - s * 0.3, x, y - s * 1.7);
      canvas.drawPath(flame, _glow(0.75 * (1 - ph) + 0.1));
    }
  }

  /// lá cuốn: bay quanh theo elip đồng thời tự xoay, rơi nhẹ rồi cuốn lên
  void _leaves(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final ang = (t + i / 5) * 2 * math.pi;
      final p =
          c +
          Offset(
            math.cos(ang) * 56,
            math.sin(ang) * 24 + math.sin(ang * 2 + i) * 5,
          );
      final front = math.sin(ang) > 0;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang * 2 + i); // lá tự xoay khi bay
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 7, height: 3),
        _glow(front ? 0.85 : 0.35),
      );
      canvas.restore();
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
      canvas.drawArc(
        Rect.fromCenter(center: c, width: 112, height: 52),
        start,
        1.1,
        false,
        paint,
      );
    }
  }

  /// đá vụn lơ lửng vòng quanh chân (quỹ đạo thấp, chậm)
  void _rocks(Canvas canvas, Offset c) {
    for (var i = 0; i < 4; i++) {
      final ang = (t * 0.5 + i / 4) * 2 * math.pi;
      final p =
          c +
          Offset(math.cos(ang) * 54, 22 + math.sin(ang) * 10); // lửng quanh đùi
      final s = math.sin(ang) > 0 ? 3.4 : 2.4;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 1.6),
        _glow(0.75),
      );
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

  /// tinh tú nhấp nháy quanh người (chữ thập 4 cánh)
  void _stars(Canvas canvas, Offset c) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final ang = i * math.pi / 3 + 0.4;
      final r = 46.0 + 14 * ((i * 37) % 3);
      final p = c + Offset(math.cos(ang) * r, math.sin(ang) * r * 0.5);
      final tw =
          (0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 6))));
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
      old.t != t ||
      old.color != color ||
      old.style != style ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg;
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
        color: cs.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 12, color: cs.secondary),
          const SizedBox(width: 4),
          Text(
            '${widget.label} +${widget.pct}% · ${h > 0 ? '${h}g ' : ''}$m′${s.toString().padLeft(2, '0')}″',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.secondary,
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
    final icon = PixelIcon(it['pixel'] as String, grade: grade, size: 40);
    return Tooltip(
      message: owned ? it['name'] as String : '??? (chưa thu thập)',
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            cs.onSurface.withValues(alpha: 0.05),
            cs.surface,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: owned
                ? gradeColor(grade).withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
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
                  ? gradeColor(it['grade'] as int).withValues(alpha: 0.7)
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
                    fontWeight: it != null ? FontWeight.w800 : FontWeight.w500,
                    color: it != null
                        ? gradeColor(it['grade'] as int)
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
                    color: gradeColor(grade).withValues(alpha: 0.55),
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
                        bottom: 1,
                        child: Text(
                          '×$qty',
                          style: t.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: gradeColor(grade),
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
                'Luyện hóa ${qty! - 1} bản dư',
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
