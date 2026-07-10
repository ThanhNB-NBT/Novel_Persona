import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cultivation.dart';
import '../data.dart';
import '../update.dart';
import 'cultivation/cultivation.dart';
import 'cultivation/pixel.dart';
import 'explore/home.dart';
import 'library/library.dart';
import 'library/queue.dart';
import 'account/settings.dart';

/// Khung 5 tab: Tủ truyện · Khám phá · TU TIÊN (giữa, nổi) · Hàng đợi · Cài đặt.
/// Mặc định mở Tủ truyện (chưa đăng nhập → Khám phá). Vuốt ngang đổi tab bằng PageView.
/// Dock NỔI đè lên nội dung như NEO (Stack, không dùng slot bottomNavigationBar —
/// slot đó chừa nguyên một dải nền phía sau).
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  late int _i;
  late final _pc = PageController(initialPage: _i);
  static const _pages = [
    LibraryScreen(), HomeScreen(), CultivationScreen(), QueueScreen(), SettingsScreen(),
  ];

  static const _tabs = [
    (icon: Icons.bookmarks_outlined, active: Icons.bookmarks_rounded, label: 'Tủ truyện'),
    (icon: Icons.explore_outlined, active: Icons.explore_rounded, label: 'Khám phá'),
    (icon: Icons.self_improvement_rounded, active: Icons.self_improvement_rounded, label: 'Tu Tiên'),
    (icon: Icons.hourglass_empty_rounded, active: Icons.hourglass_bottom_rounded, label: 'Hàng đợi'),
    (icon: Icons.settings_outlined, active: Icons.settings_rounded, label: 'Cài đặt'),
  ];

  @override
  void initState() {
    super.initState();
    _i = sb.auth.currentUser != null ? 0 : 1; // Tủ truyện nếu đã đăng nhập, ngược lại Khám phá
    // có bản mới trên GitHub Releases → hỏi 1 lần mỗi version (sau frame đầu, cần context)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptUpdate(context, ref);
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cả vuốt lẫn bấm dock đều đi qua onPageChanged → side effect một chỗ
    void changed(int i) {
      if (i == _i) return;
      if (i == 0) ref.invalidate(readingProvider);
      if (i == 2) ref.invalidate(cultStateProvider); // tick exp mỗi lần mở Tu Tiên
      if (i == 3) ref.invalidate(translateQueueProvider);
      HapticFeedback.lightImpact();
      setState(() => _i = i);
    }

    void go(int i) {
      if (i < 0 || i > 4 || i == _i) return;
      _pc.animateToPage(i,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }

    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        // PageView: trang bám ngón tay, trượt như thẻ (giống TabBarView bên Quản trị).
        // Vùng có list cuộn ngang (carousel, rail) thì gesture của list thắng.
        PageView(
          controller: _pc,
          onPageChanged: changed,
          children: [for (final p in _pages) _KeepAlive(child: p)],
        ),
        // Tab dùng IndexedStack (giữ sống) nên không tự fetch lại — go() làm mới
        // dữ liệu khi mở tab để thấy thay đổi vừa gây ở màn khác.
        Align(alignment: Alignment.bottomCenter, child: _Dock(index: _i, onTap: go)),
      ]),
    );
  }
}

/// Đĩa Tu Tiên "dập nổi" giữa dock: biểu tượng đứng yên trang trọng, quanh mép
/// là vòng bát quái mảnh xoay chậm + đốm linh khí chạy quỹ đạo kéo vệt đuôi.
/// Được chọn: bừng sáng + vòng quay NHANH lên (như dồn linh khí).
class _TaijiDisc extends ConsumerStatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  const _TaijiDisc({required this.selected, required this.onTap});
  @override
  ConsumerState<_TaijiDisc> createState() => _TaijiDiscState();
}

class _TaijiDiscState extends ConsumerState<_TaijiDisc>
    with SingleTickerProviderStateMixin {
  late final _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = widget.selected;
    // chọn tab → linh khí quay nhanh gấp ~3 (đổi duration giữa chừng vẫn mượt
    // vì repeat() chạy tiếp từ value hiện tại)
    final want = sel ? 4 : 12;
    if (_spin.duration!.inSeconds != want) {
      _spin.duration = Duration(seconds: want);
      _spin.repeat();
    }
    final emblem = ref.watch(tabEmblemProvider); // biểu tượng do user chọn
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: sel ? 1.12 : 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]),
            border: Border.all(
                color: cs.surface.withValues(alpha: 0.9), width: 3),
            boxShadow: [
              BoxShadow(
                  color: cs.primary.withValues(alpha: sel ? 0.75 : 0.4),
                  blurRadius: sel ? 22 : 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Stack(alignment: Alignment.center, children: [
            // vòng bát quái + đốm linh khí quay quanh mép đĩa
            AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => CustomPaint(
                size: const Size.square(48),
                painter: _SpiritRingPainter(_spin.value, sel),
              ),
            ),
            // biểu tượng ĐỨNG YÊN (xoay cả icon nhìn chóng mặt, kém "ấn tín")
            PixelIcon(emblem, grade: 5, size: 26),
          ]),
        ),
      ),
    );
  }
}

/// Vòng linh khí quanh đĩa Tu Tiên: 8 vạch bát quái mảnh xoay đều + 1 đốm sáng
/// chạy quỹ đạo kéo vệt đuôi mờ dần. Trắng trên nền primary — hợp cả 2 theme.
class _SpiritRingPainter extends CustomPainter {
  final double t; // 0..1 vòng quay
  final bool sel;
  _SpiritRingPainter(this.t, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 20.0; // bán kính quỹ đạo (đĩa 54 - viền 3 - chừa mép)
    final ang = t * 2 * math.pi;

    // 8 vạch bát quái xoay theo t (vạch dài/ngắn xen kẽ — gợi hào âm dương)
    final tick = Paint()
      ..isAntiAlias = true
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: sel ? 0.75 : 0.45);
    for (var i = 0; i < 8; i++) {
      final a = ang + i * math.pi / 4;
      final len = i.isEven ? 3.5 : 2.0;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r - len),
        c + Offset(math.cos(a), math.sin(a)) * r,
        tick,
      );
    }

    // đốm linh khí chạy NGƯỢC chiều vạch (nhìn "sống" hơn cùng chiều) + vệt đuôi
    final head = -ang * 2;
    for (var k = 0; k < 6; k++) {
      final a = head + k * 0.14; // đuôi rải phía sau
      final alpha = (sel ? 0.95 : 0.7) * (1 - k / 6);
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * r,
        k == 0 ? 2.1 : 1.5 - k * 0.15,
        Paint()
          ..isAntiAlias = true
          ..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_SpiritRingPainter old) => old.t != t || old.sel != sel;
}

/// Giữ trạng thái từng tab trong PageView (thay vai trò IndexedStack cũ).
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Dock nổi kiểu NEO: pill kính mờ tách khỏi mép màn, PILL CHỌN TRƯỢT giữa các tab,
/// bóng đổ + quầng màu nhấn (đặt NGOÀI clip để không bị cắt).
class _Dock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _Dock({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const n = 5;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      // Stack clip none: đĩa Tu Tiên "dập nổi" nhô lên khỏi dock (nằm NGOÀI
      // ClipRRect của dock, không thì bị cắt cụt đầu).
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        _dockBody(context, cs, t, dark, n),
        Positioned(
          top: -16,
          child: _TaijiDisc(selected: index == 2, onTap: () => onTap(2)),
        ),
      ]),
    );
  }

  Widget _dockBody(
      BuildContext context, ColorScheme cs, TextTheme t, bool dark, int n) {
    return DecoratedBox(
        // bóng ở NGOÀI ClipRRect — trong clip là bị cắt mất, dock "bẹt"
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
                blurRadius: 26, offset: const Offset(0, 10)),
            BoxShadow(
                color: cs.primary.withValues(alpha: dark ? 0.12 : 0.08),
                blurRadius: 34),
          ],
        ),
        // RepaintBoundary: hoạt ảnh pill/icon chỉ vẽ lại dock, không kéo cả cây
        child: RepaintBoundary(
            child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            // sigma 16 đủ mờ — 24 tốn GPU, gây khựng khi pill trượt
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: dark ? 0.6 : 0.72),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
              ),
              child: SizedBox(
                height: 56,
                child: Stack(children: [
                  // Pill chọn trượt giữa các tab. AnimatedSlide = CHỈ transform khi vẽ
                  // (GPU), không tính layout lại mỗi frame như AnimatedAlign → mượt.
                  Positioned.fill(
                    child: LayoutBuilder(builder: (_, cons) {
                      final w = cons.maxWidth / n;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: w,
                          height: cons.maxHeight,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: index.toDouble()),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            builder: (_, x, child) {
                              // "giọt nước": đang trôi thì giãn ngang + bẹt dọc
                              // (bảo toàn thể tích), càng gần đích càng co về tròn
                              final s = 1 + (x - index).abs().clamp(0.0, 1.0) * 0.45;
                              return FractionalTranslation(
                                translation: Offset(x, 0), // x = bội số bề rộng pill
                                child: Transform.scale(scaleX: s, scaleY: 1 / s, child: child),
                              );
                            },
                            // tab giữa: pill ẨN (đĩa Tu Tiên tự sáng lên thay) —
                            // pill trượt dưới đĩa nhìn chồng chéo rất xấu
                            child: AnimatedOpacity(
                              opacity: index == 2 ? 0 : 1,
                              duration: const Duration(milliseconds: 250),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  Row(children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => onTap(i), // haptic do go() trong shell lo
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ô giữa: đĩa Tu Tiên nổi đè lên trên → chỉ chừa chỗ + nhãn
                                if (i == 2)
                                  const SizedBox(height: 24)
                                else
                                // icon "pop" nhẹ khi được chọn
                                AnimatedScale(
                                  scale: i == index ? 1.12 : 1,
                                  duration: const Duration(milliseconds: 300),
                                  // easeOutBack vọt lố → rung nhẹ; cubic êm hơn
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                      i == index
                                          ? _RootShellState._tabs[i].active
                                          : _RootShellState._tabs[i].icon,
                                      size: 22,
                                      color: i == index
                                          ? cs.primary
                                          : cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 2),
                                // độ đậm CỐ ĐỊNH — đổi w500↔w700 làm chữ đổi bề rộng
                                // giữa chừng hoạt ảnh → nhìn "giật"; chỉ đổi màu
                                Text(_RootShellState._tabs[i].label,
                                    style: t.labelSmall?.copyWith(
                                        letterSpacing: 0,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: i == index
                                            ? cs.primary
                                            : cs.onSurfaceVariant)),
                              ]),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
        )));
  }
}
