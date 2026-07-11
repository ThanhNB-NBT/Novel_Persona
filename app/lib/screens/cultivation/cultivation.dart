import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../cultivation.dart';
import '../../data.dart';
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
          result: r,
          major: major,
          race: st['race'] as String?,
          gender: st['gender'] as String?,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Lỗi: $e', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(cultStateProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
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
                                onAdvance: () => _advance(st),
                              ),
                              const SizedBox(height: 14),
                              const _SectionLabel(
                                'Trang bị',
                                Icons.shield_moon_outlined,
                              ),
                              const SizedBox(height: 8),
                              _EquipRow(st: st),
                              const SizedBox(height: 12),
                              const _SectionLabel(
                                'Túi càn khôn',
                                Icons.backpack_rounded,
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
}) {
  final cs = Theme.of(context).colorScheme;
  final c = on ? cs.primary : cs.onSurfaceVariant;
  return Container(
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
      ],
    ),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = st['realm'] as int;
    final rc = gradeColor((realm + 1) ~/ 2);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

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
                    halo: eq['phapbao']?['effect']?['halo'] as String?,
                    weaponSprite: eq['vukhi']?['pixel'] as String?,
                    phapbaoSprite: eq['phapbao']?['pixel'] as String?,
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
                        realmNames[realm - 1],
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
                    const SizedBox(width: 10),
                    // nhấc pill lên chút cho khớp chân chữ (line-box cao hơn baseline)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: _tangPill(context, st['stage'] as int, rc),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '「${daoTitles[realm - 1]}」',
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
        ],
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
  final bool busy;
  const _RealmCard({
    required this.st,
    required this.exp,
    required this.onAdvance,
    required this.busy,
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
    // tỷ lệ đột phá hiển thị = công thức server (đan hộ thân + pháp chú + tộc đã cộng)
    final chance = cultBreakthroughChance(st);
    final now = DateTime.now();
    final buffUntil = DateTime.tryParse(st['buff_until'] as String? ?? '');
    final stoneUntil = DateTime.tryParse(st['stone_until'] as String? ?? '');
    final cpElem = (st['equipped'] as Rec?)?['congphap']?['effect']?['element'];
    final match =
        cpElem != null && (cpElem == st['element'] || cpElem == 'all');
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
                    linhCanTier((st['linh_can'] as num).toInt()),
                  ),
                  if (st['element'] != null)
                    _infoChip(
                      context,
                      Icons.auto_awesome_rounded,
                      'hệ ${elementNames[st['element']]}${match ? ' ×1.3' : ''}',
                      on: match,
                    ),
                  _infoChip(
                    context,
                    Icons.speed_rounded,
                    '${rate.toStringAsFixed(1)}/giây',
                    on: true,
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
                                        ? 'Viên mãn — chờ phi thăng'
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
                        onPressed: full && !peak && !busy ? onAdvance : null,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                major
                                    ? Icons.bolt_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 18,
                              ),
                        label: Text(
                          major
                              ? 'Đột phá ${realmNames[realm]} ($chance%)'
                              : peak
                              ? 'Đỉnh Độ Kiếp'
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
  final String? race;
  final String? gender;
  const _AdvanceFxDialog({
    required this.result,
    required this.major,
    this.race,
    this.gender,
  });
  @override
  State<_AdvanceFxDialog> createState() => _AdvanceFxDialogState();
}

class _AdvanceFxDialogState extends State<_AdvanceFxDialog>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

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
                      : const PixelIcon('talisman', grade: 1, size: 80),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.major
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
                    child: Text(
                      'Tỷ lệ lúc roll: ${r['chance']}%',
                      style: t.labelMedium?.copyWith(color: Colors.white38),
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
                  child: Text(ok ? 'Tiếp tục tu luyện' : 'Tĩnh tâm'),
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
        _bolt(
          canvas,
          Offset(c.dx + dx * 1.6, 0),
          c + Offset(dx * 0.2, -6),
          i + 3,
          bolt,
        );
      }
      // lóe sáng nơi sét chạm
      canvas.drawCircle(
        c,
        10 + t * 8,
        Paint()..color = const Color(0xFFFFE066).withValues(alpha: a * 0.4),
      );
    }
    if (!ok) {
      // quầng đỏ phụt lên rồi tắt
      final a = (1 - t) * 0.35;
      canvas.drawCircle(
        c,
        70 + t * 30,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: a),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: 100 + t * 30)),
      );
      return;
    }
    // chớp sáng trắng 15% đầu
    if (t < 0.15) {
      canvas.drawCircle(
        c,
        140,
        Paint()..color = Colors.white.withValues(alpha: (1 - t / 0.15) * 0.75),
      );
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
          ..color = color.withValues(alpha: (1 - v) * 0.8),
      );
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
  );
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
  });
  @override
  State<_AnimatedCultivator> createState() => _AnimatedCultivatorState();
}

class _AnimatedCultivatorState extends State<_AnimatedCultivator>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  ui.Image? _weaponImg; // icon webp của vũ khí đang đeo, decode 1 lần
  ui.Image? _phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  ui.Image? _swordWheelImg; // kiếm luân minh họa, xoay sau đầu
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
        old.phapbaoSprite != widget.phapbaoSprite) {
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
    ]);
    if (!mounted) return;
    setState(() {
      _weaponImg = imgs[0];
      _phapbaoImg = imgs[1];
      _swordWheelImg = imgs[2];
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
  final Color moon; // màu cảnh giới
  final Color aura; // màu hệ công pháp (quầng thở)
  final int realm; // 1..9 — kiếm luân nhích to, sao từ Hóa Thần
  final String?
  halo; // kiểu vòng từ pháp bảo: nguyet/tinh/loi/kim — null = vòng trơn
  final ui.Image? weaponImg; // vũ khí đang đeo — nửa vòng SAU vẽ ở lớp nền này
  final ui.Image? phapbaoImg; // pháp bảo đang đeo — như trên, lệch pha nửa vòng
  final ui.Image? swordWheelImg; // kiếm luân minh họa sau đầu
  _SkyPainter(
    this.t,
    this.moon,
    this.aura,
    this.realm, {
    this.halo,
    this.weaponImg,
    this.phapbaoImg,
    this.swordWheelImg,
  });

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

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.t != t ||
      old.moon != moon ||
      old.aura != aura ||
      old.realm != realm ||
      old.halo != halo ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg ||
      old.swordWheelImg != swordWheelImg;
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
        _rings(canvas, c);
        _dots(canvas, c);
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

  /// vòng kim quang lan từ người ra
  void _rings(Canvas canvas, Offset c) {
    for (final off in [0.0, 0.5]) {
      final v = (t + off) % 1;
      canvas.drawOval(
        Rect.fromCenter(
          center: c + const Offset(0, 26),
          width: 40 + v * 70,
          height: (40 + v * 70) * 0.38,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - v) * 2.5 + 0.5
          ..color = color.withValues(alpha: (1 - v) * 0.55),
      );
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
  const _SectionLabel(this.title, this.icon);
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
      ],
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
    ],
  );

  if (action != 'use') return;
  if (_cultItemBusy) return; // đang xử lý món trước → bỏ qua tap lặp
  _cultItemBusy = true;
  try {
    isDan
        ? await cultUseItem(it['id'] as int)
        : await cultEquip(it['id'] as int);
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
