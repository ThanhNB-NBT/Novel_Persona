import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      if (!mounted) return;
      maybePromptUpdate(context, ref);
      _maybeOfferGuide();
    });
  }

  /// Người mới: mời xem Hướng dẫn đúng MỘT lần (SnackBar có nút, không chặn màn).
  void _maybeOfferGuide() {
    if (prefs.getBool('guide_offered') == true) return;
    prefs.setBool('guide_offered', true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text('Lần đầu dùng app? Xem hướng dẫn từng bước nhé.'),
      action: SnackBarAction(
          label: 'Xem', onPressed: () => context.push('/guide')),
    ));
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

    // Các tab đã bỏ AppBar → tự khai style status bar (trong suốt, icon theo theme);
    // không khai thì Android giữ style của màn trước đó, nhìn lem nhem.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          // TẦNG KHÍ QUYỂN sau mọi tab: 2 quầng sáng lớn rất loãng (xanh nhấn +
          // vàng thành tựu) — app có chiều sâu thay vì mặt phẳng một màu.
          // Các tab Scaffold trong suốt để lộ tầng này.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AtmospherePainter(
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                  dark,
                ),
              ),
            ),
          ),
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
      ),
    );
  }
}

/// Khí quyển nền: 2 quầng radial rất loãng — trên-trái màu nhấn, dưới-phải vàng.
/// Vẽ 1 lần (shouldRepaint false trừ đổi theme), nằm sau mọi tab.
class _AtmospherePainter extends CustomPainter {
  final Color primary, gold;
  final bool dark;
  _AtmospherePainter(this.primary, this.gold, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.12, size.height * 0.05), size.width * 1.0,
        primary, dark ? 0.14 : 0.08);
    glow(Offset(size.width * 0.95, size.height * 0.85), size.width * 0.85,
        gold, dark ? 0.08 : 0.05);
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) =>
      old.primary != primary || old.gold != gold || old.dark != dark;
}

/// "Sao băng linh khí" trong dock: pill phát sáng ở tab hiện hành; khi đổi tab nó
/// BAY sang vị trí mới, kéo vệt đuôi gradient thon dần + rắc vài tia lửa dọc đường.
/// x = vị trí thật (số lẻ khi đang bay), target = tab đích, fade = tan gần đĩa giữa.
class _CometPillPainter extends CustomPainter {
  final double x, fade;
  final int target, n;
  final Color color;
  final Animation<double> ambient; // nhịp sống 0..1 (lava trôi trong pill)
  _CometPillPainter({
    required this.x,
    required this.target,
    required this.n,
    required this.color,
    required this.fade,
    required this.ambient,
  }) : super(repaint: ambient); // đậu yên vẫn tự vẽ lại theo nhịp lava

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0.01) return;
    final w = size.width / n;
    final cx = (x + 0.5) * w;
    final cy = size.height / 2;
    // đang bay bao xa (0 = đậu, 1 = còn nguyên 1 tab) → quyết định độ dài đuôi
    final drift = (x - target).abs().clamp(0.0, 1.0);
    final dir = (x - target).sign; // đuôi ngả về phía VỪA RỜI ĐI

    // pill "giọt nước": bay thì giãn ngang bẹt dọc, gần đích co về tròn.
    // Cao gần kín dock (52/56) + bo đúng nửa chiều cao = viên nang tròn trịa,
    // ăn khớp khung bo 32 của dock (bản cũ 44/bo24 nhìn lửng lơ, lạc khung).
    final sx = 1 + drift * 0.5;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: (w - 6) * sx, height: 50 / sx);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));

    // vệt đuôi: gradient thon dần về phía sau, chỉ hiện khi đang bay
    if (drift > 0.02) {
      final tailLen = drift * w * 1.5;
      final tail = Rect.fromLTRB(
        dir > 0 ? cx : cx - tailLen * 0 - 0, // đầu đuôi bám mép pill
        cy - 14 * (1 - drift * 0.4),
        dir > 0 ? cx + tailLen : cx,
        cy + 14 * (1 - drift * 0.4),
      ).translate(dir > 0 ? rect.width * 0.2 : -rect.width * 0.2, 0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tail, const Radius.circular(14)),
        Paint()
          ..shader = LinearGradient(
            begin: dir > 0 ? Alignment.centerLeft : Alignment.centerRight,
            end: dir > 0 ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              color.withValues(alpha: 0.22 * fade),
              color.withValues(alpha: 0),
            ],
          ).createShader(tail),
      );
      // tia lửa rơi lại phía sau: vị trí tất định theo x (không random — vẽ lại
      // frame nào cũng khớp frame đó, không nhấp nháy)
      for (var k = 1; k <= 3; k++) {
        final d = drift * k / 3;
        final px = cx + dir * (rect.width * 0.3 + d * tailLen * 0.9);
        final py = cy + (k.isEven ? -1 : 1) * (3.0 + 4 * d);
        canvas.drawCircle(
          Offset(px, py),
          2.2 * (1 - d) * fade,
          Paint()..color = color.withValues(alpha: (0.5 - 0.4 * d) * fade),
        );
      }
    }

    // quầng sáng ngoài (vẽ TRƯỚC pill cho mềm) + pill kính
    canvas.drawRRect(
      rr.inflate(3),
      Paint()
        ..color = color.withValues(alpha: (0.10 + 0.15 * drift) * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
        rr, Paint()..color = color.withValues(alpha: 0.13 * fade));

    // "lava" trong pill: 2 đốm sáng mờ trôi chéo nhau theo nhịp ambient — pill
    // đậu yên vẫn sống, như linh khí cuộn trong bình kính. Clip theo pill.
    final tt = ambient.value * 2 * math.pi;
    canvas.save();
    canvas.clipRRect(rr);
    final blob = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
      ..color = color.withValues(alpha: 0.20 * fade);
    canvas.drawCircle(
        Offset(cx + math.sin(tt) * rect.width * 0.24,
            cy + math.cos(tt * 2) * 7),
        11,
        blob);
    canvas.drawCircle(
        Offset(cx - math.sin(tt + 1.3) * rect.width * 0.28,
            cy - math.cos(tt * 2 + 0.7) * 6),
        8,
        blob..color = color.withValues(alpha: 0.14 * fade));
    canvas.restore();

    // viền sáng mảnh — chất "kính" bắt sáng
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.25 * fade),
    );
  }

  @override
  bool shouldRepaint(_CometPillPainter old) =>
      old.x != x || old.fade != fade || old.color != color;
}

/// Viền AURORA quanh mép dock: một cung sáng màu nhấn chạy vòng quanh viền kính
/// (sweep gradient xoay theo nhịp), như linh khí tuần hoàn quanh pháp khí.
class _AuroraBorderPainter extends CustomPainter {
  final Animation<double> ambient;
  final Color color, base;
  _AuroraBorderPainter(this.ambient, this.color, this.base)
      : super(repaint: ambient);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(32));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = SweepGradient(
        transform: GradientRotation(ambient.value * 2 * math.pi),
        colors: [
          base.withValues(alpha: 0.0),
          color.withValues(alpha: 0.85),
          base.withValues(alpha: 0.0),
          base.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.08, 0.22, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rr.deflate(0.65), paint);
  }

  @override
  bool shouldRepaint(_AuroraBorderPainter old) =>
      old.color != color || old.base != base;
}

/// Đĩa Tu Tiên "dập nổi" giữa dock: biểu tượng đứng yên trang trọng, quanh mép
/// là vòng bát quái mảnh xoay chậm + đốm linh khí chạy quỹ đạo kéo vệt đuôi.
/// Được chọn: bừng sáng + vòng quay NHANH lên (như dồn linh khí).
/// Thêm 2026-07-16: đĩa LƠ LỬNG (nhấp nhô sin theo controller) + quầng sáng
/// thở theo cùng nhịp — nhìn như pháp bảo đang treo giữa không trung.
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
        // AnimatedBuilder bọc NGOÀI: đĩa lơ lửng nhấp nhô + quầng thở cùng nhịp
        // _spin (chọn tab → nhịp nhanh lên như dồn linh khí).
        child: AnimatedBuilder(
          animation: _spin,
          builder: (_, _) {
            final breath =
                0.5 + 0.5 * math.sin(_spin.value * 2 * math.pi * 2);
            return Transform.translate(
              offset: Offset(0, -2.5 * breath),
              child: Container(
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
                        color: cs.primary.withValues(
                            alpha: (sel ? 0.6 : 0.32) + 0.18 * breath),
                        blurRadius: (sel ? 20 : 11) + 5 * breath,
                        offset: const Offset(0, 4)),
                    // bóng đổ xuống dock giãn/co ngược nhịp bay — bán chất "lơ lửng"
                    BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.18 * (1 - breath * 0.5)),
                        blurRadius: 8,
                        offset: Offset(0, 6 + 2 * breath)),
                  ],
                ),
                child: Stack(alignment: Alignment.center, children: [
                  // vòng bát quái + đốm linh khí quay quanh mép đĩa
                  CustomPaint(
                    size: const Size.square(48),
                    painter: _SpiritRingPainter(_spin.value, sel),
                  ),
                  // biểu tượng ĐỨNG YÊN (xoay cả icon nhìn chóng mặt, kém "ấn tín")
                  PixelIcon(emblem, grade: 5, size: 26),
                ]),
              ),
            );
          },
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

/// Dock nổi kiểu NEO: pill kính mờ tách khỏi mép màn, bóng đổ + quầng màu nhấn
/// (đặt NGOÀI clip để không bị cắt). Có nhịp sống riêng (_amb, 8s/vòng) nuôi:
/// viền AURORA chạy quanh mép dock + đốm "lava" trôi trong pill chọn.
class _Dock extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _Dock({required this.index, required this.onTap});
  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> with SingleTickerProviderStateMixin {
  late final _amb =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  @override
  void dispose() {
    _amb.dispose();
    super.dispose();
  }

  int get index => widget.index;
  ValueChanged<int> get onTap => widget.onTap;

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
            child: Stack(children: [
          ClipRRect(
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
                // MỘT tween x (vị trí pill, số lẻ khi đang bay) cấp cho CẢ painter
                // sao băng lẫn icon: mọi thứ cùng nhịp, không lệch pha.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: index.toDouble()),
                  duration: const Duration(milliseconds: 460),
                  curve: Curves.easeOutCubic,
                  builder: (_, x, _) => Stack(children: [
                    // "Sao băng linh khí": pill phát sáng bay giữa các tab, kéo vệt
                    // đuôi gradient + rắc tia lửa dọc đường; đậu lại thì bên trong
                    // có đốm lava trôi theo nhịp _amb (repaint qua Listenable).
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CometPillPainter(
                          x: x,
                          target: index,
                          n: n,
                          color: cs.primary,
                          ambient: _amb,
                          // gần đĩa Tu Tiên thì pill tự tan (đĩa sáng thay vai)
                          fade: index == 2 ? (x - 2).abs().clamp(0.0, 1.0) : 1.0,
                        ),
                      ),
                    ),
                    Row(children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => onTap(i), // haptic do go() trong shell lo
                            behavior: HitTestBehavior.opaque,
                            child: Builder(builder: (_) {
                              // "thấu kính linh khí": icon phồng/nhô theo KHOẢNG CÁCH
                              // tới pill đang bay (liên tục, không nhảy bậc) — dock
                              // như bị nam châm của sao băng hút qua từng tab.
                              final near =
                                  (1 - (i - x).abs()).clamp(0.0, 1.0);
                              final iconColor = Color.lerp(
                                  cs.onSurfaceVariant, cs.primary, near)!;
                              return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // ô giữa: đĩa Tu Tiên nổi đè lên trên → chừa chỗ
                                    if (i == 2)
                                      const SizedBox(height: 24)
                                    else
                                      Transform.translate(
                                        // nhô/phồng NHẸ thôi — quá tay là chữ dưới
                                        // chạm mép pill (feedback 2026-07-16)
                                        offset: Offset(0, -1.5 * near),
                                        child: Transform.scale(
                                          scale: 1 + 0.09 * near,
                                          child: Icon(
                                              i == index
                                                  ? _RootShellState._tabs[i].active
                                                  : _RootShellState._tabs[i].icon,
                                              size: 20,
                                              color: iconColor),
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    // độ đậm CỐ ĐỊNH — đổi weight giữa hoạt ảnh làm
                                    // chữ đổi bề rộng nhìn "giật"; chỉ đổi màu
                                    Text(_RootShellState._tabs[i].label,
                                        style: t.labelSmall?.copyWith(
                                            letterSpacing: 0,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: iconColor)),
                                  ]);
                            }),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
          // viền aurora chạy quanh mép dock — vẽ ĐÈ lên trên cùng, không bắt chạm
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AuroraBorderPainter(_amb, cs.primary, cs.outlineVariant),
              ),
            ),
          ),
        ])));
  }
}
