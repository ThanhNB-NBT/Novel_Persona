import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../widgets.dart';
import 'dialog_advance.dart';
import 'hero_stage.dart';
import 'inventory.dart';
import 'pixel.dart';
import 'realm_card.dart';
import 'sheets_tu_tien.dart';
import 'silk.dart';

// Painters + cảnh nhân vật động đã tách sang painters_aura/painters_fx/preview;
// export lại cho render test import thẳng cultivation.dart như cũ.
export 'preview.dart';

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
  // Đã cuộn qua hero → hiện dải nền sau status bar. Status bar trong suốt để hero trải
  // lên tận đỉnh, nhưng cuộn xuống túi đồ thì icon ô vật phẩm chạy chồng lên giờ/pin.
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _timer?.cancel();
    _exp.dispose();
    _scrolled.dispose();
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
        pageBuilder: (ctx, _, _) => AdvanceFxDialog(
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
        pageBuilder: (ctx, _, _) => AdvanceFxDialog(
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
          content: Text(
            win
                ? 'Vượt Tâm Ma ($chance%), độ thiên kiếp thành công — đăng bậc ${tienTierNames[tier]}!'
                : 'Tâm ma quấy nhiễu ($chance%), độ kiếp thất bại — hao 20% tiên nguyên. Thử lại.',
          ),
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
                error: (e, _) => AppError(
                  e,
                  onRetry: () => ref.invalidate(cultStateProvider),
                ),
                data: (st) {
                  if (st == null) {
                    // Nút mặc định là `primary` (xanh băng) — đặt giữa tranh thuỷ mặc
                    // xanh đêm + vàng kim thì chỏi hẳn tông. Dùng `secondary` (vàng
                    // thành tựu) cho hợp cảnh, vẫn là token chứ không hardcode.
                    final cs = Theme.of(context).colorScheme;
                    return Center(
                      child: FilledButton(
                        onPressed: () => context.push('/login'),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.secondary,
                          foregroundColor: cs.onSecondary,
                        ),
                        child: const Text('Đăng nhập để bắt đầu tu luyện'),
                      ),
                    );
                  }
                  _sync(st);
                  final topPad = MediaQuery.paddingOf(context).top;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
                        _scrolled.value = n.metrics.pixels > 160;
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () async => ref.invalidate(cultStateProvider),
                      child: ListView(
                        // hero tràn viền → bỏ padding ngang ở ListView, pad từng phần dưới
                        padding: const EdgeInsets.only(bottom: 120), // né dock
                        children: [
                          // chưa chọn chủng tộc → mời chọn (một lần duy nhất, server chặn đổi)
                          if (st['race'] == null)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                topPad + 8,
                                16,
                                4,
                              ),
                              child: _RacePickerCard(),
                            ),
                          // có card chọn tộc phía trên thì hero khỏi ôm status bar
                          HeroStage(
                            st: st,
                            topPad: st['race'] == null ? 0 : topPad,
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                RealmCard(
                                  st: st,
                                  exp: _exp,
                                  busy: _advancing,
                                  ascended: st['ascended_at'] != null,
                                  onAdvance: () => _advance(st),
                                  onAscend: () => _ascend(st),
                                  onAscendTier: () => _ascendTier(),
                                ),
                                const SizedBox(height: 12),
                                // ô khổ cố định (3 thẻ, dãy trang bị): 200% cắt chữ → chặn 1.3
                                MediaQuery.withClampedTextScaling(
                                  maxScaleFactor: 1.3,
                                  child: _TuTienActionBar(st: st),
                                ),
                                const SizedBox(height: 14),
                                const CultSectionLabel(
                                  'Trang bị',
                                  Icons.shield_moon_outlined,
                                ),
                                const SizedBox(height: 8),
                                MediaQuery.withClampedTextScaling(
                                  maxScaleFactor: 1.3,
                                  child: EquipRow(st: st),
                                ),
                                const SizedBox(height: 12),
                                CultSectionLabel(
                                  'Túi càn khôn',
                                  Icons.backpack_rounded,
                                  trailing: TextButton.icon(
                                    onPressed: () => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      showDragHandle: true,
                                      builder: (_) => const CollectionSheet(),
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
                                const InventoryGrid(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _scrolled,
                  builder: (_, on, _) => AnimatedOpacity(
                    opacity: on ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    // tối hẳn để icon status bar (đang để sáng) luôn đọc được
                    child: ColoredBox(
                      color: Color.lerp(bgTint, Colors.black, 0.7)!,
                    ),
                  ),
                ),
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

/// Tiêu đề mục kiểu game: thanh nhấn dọc + icon + nhãn viết hoa nhỏ.
class CultSectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  const CultSectionLabel(this.title, this.icon, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        const Seal(size: 11),
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

/// Thanh lối tắt tính năng Tu Tiên: Động Phủ, Bí Cảnh, Thành Tựu
class _TuTienActionBar extends StatelessWidget {
  final Rec st;
  const _TuTienActionBar({required this.st});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final silk = Silk.of(context);
    Widget actionCard({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: SilkCard(
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SealIcon(icon),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: silk.ink),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(fontSize: 10, color: silk.inkSoft),
              ),
            ],
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
            builder: (_) => DongPhuSheet(st: st),
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
            builder: (_) => BiCanhSheet(st: st),
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
            builder: (_) => ThanhTuuSheet(st: st),
          ),
        ),
      ],
    );
  }
}
