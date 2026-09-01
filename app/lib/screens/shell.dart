import 'dart:math' as math;
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../cultivation.dart';
import '../data.dart';
import '../update.dart';
import '../widgets.dart';
import 'cultivation/cultivation.dart';
import 'cultivation/pixel.dart';
import 'explore/home.dart';
import 'library/library.dart';
import 'library/queue.dart';
import 'account/settings.dart';

/// Cờ tĩnh ghi nhận splash đã chiếu trong phiên chạy (không lặp lại khi đổi tab)
bool _splashShown = false;

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
  late bool _showSplash = !_splashShown;
  static const _pages = [
    LibraryScreen(), HomeScreen(), CultivationScreen(), QueueScreen(), SettingsScreen(),
  ];

  static const _tabs = [
    (icon: Icons.bookmarks_outlined, active: Icons.bookmarks_rounded, label: 'Tủ truyện'),
    (icon: Icons.explore_outlined, active: Icons.explore_rounded, label: 'Khám phá'),
    // ô giữa (Tu Tiên) không dùng icon/label ở đây — vẽ bằng _SpiritDrop
    (icon: Icons.self_improvement_rounded, active: Icons.self_improvement_rounded, label: ''),
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
          Align(
            alignment: Alignment.bottomCenter,
            child: _Dock(index: _i, pageController: _pc, onTap: go),
          ),
          // Hoạt ảnh khởi động: Chữ "Gác Truyện" bay vào giữa màn hình rồi chuyển hóa sang Logo
          if (_showSplash)
            _AppSplashIntro(
              onComplete: () {
                if (mounted) {
                  setState(() {
                    _splashShown = true;
                    _showSplash = false;
                  });
                }
              },
            ),
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

/// Dock nổi 120fps Ultra-Smooth: vũng LINH DỊCH metaball bám sát ngón tay theo
/// thời gian thực qua PageController.
class _Dock extends StatefulWidget {
  final int index;
  final PageController pageController;
  final ValueChanged<int> onTap;
  const _Dock({
    required this.index,
    required this.pageController,
    required this.onTap,
  });
  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> with TickerProviderStateMixin {
  // Nhịp thở chất lỏng tuần hoàn (2π/vòng)
  late final _amb =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  // Animation controller chuyên dụng cho sóng chạm và giọt bắn 120fps
  late final _splashCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  static FragmentShader? _liquid;
  static bool _tried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_tried) return;
    _tried = true;
    try {
      final p = await FragmentProgram.fromAsset('shaders/liquid_dock.frag');
      if (mounted) setState(() => _liquid = p.fragmentShader());
    } catch (e) {
      debugPrint('liquid_dock.frag không nạp được: $e');
    }
  }

  @override
  void dispose() {
    _amb.dispose();
    _splashCtrl.dispose();
    super.dispose();
  }

  static const _h = 56.0, _pad = 6.0;
  static const _n = 5;

  double _tapX = 0;

  double _calcX() {
    final pc = widget.pageController;
    if (pc.hasClients && pc.position.haveDimensions) {
      final p = pc.page;
      if (p != null) return p;
    }
    return widget.index.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: LayoutBuilder(builder: (_, c) {
        final cell = (c.maxWidth - _pad * 2) / _n;
        // AnimatedBuilder hợp nhất Vsync ticker: lắng nghe cử chỉ vuốt PageController
        // + nhịp sóng amb + hiệu ứng chạm splashCtrl
        return AnimatedBuilder(
          animation: Listenable.merge([widget.pageController, _amb, _splashCtrl]),
          builder: (_, _) {
            final x = _calcX();
            return _body(cs, t, dark, cell, c.maxWidth, x);
          },
        );
      }),
    );
  }

  Widget _body(ColorScheme cs, TextTheme t, bool dark, double cell, double w,
      double x) {
    final liquid = cs.primary;
    // Độ dãn dính khi chuyển giữa các tab (0 = đứng yên tại tab, 1 = giữa 2 tab)
    final flow = ((x - x.round()).abs() * 2.0).clamp(0.0, 1.0);
    final cent = (1.0 - (x - 2.0).abs()).clamp(0.0, 1.0);
    final splashVal = _splashCtrl.isAnimating
        ? (1.0 - _splashCtrl.value).clamp(0.0, 1.0)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: liquid.withValues(alpha: dark ? 0.14 : 0.09),
            blurRadius: 34,
          ),
        ],
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(children: [
            // Nền kính mờ (BackdropFilter)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: dark ? 0.55 : 0.68),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
              ),
            ),
            // Vệt sáng mép trên — ColorOS 17 gọi là contour lighting: một sợi sáng
            // ôm rìa trên làm thanh nổi khỏi nền thay vì viền xám phẳng.
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              height: 1.5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: dark ? 0.55 : 0.95),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
            // Vũng linh dịch chạy 120fps trên canvas
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LiquidPainter(
                    amb: _amb,
                    shader: _liquid,
                    color: liquid,
                    // hạ xuống vì nút tròn phát sáng đã gánh phần "đang ở tab nào";
                    // để nguyên 0.52/0.46 thì hai lớp chồng nhau thành bệt.
                    alpha: dark ? 0.30 : 0.26,
                    selX: _pad + (x + 0.5) * cell,
                    cent: cent,
                    flow: flow,
                    splash: splashVal,
                    tapX: _tapX,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(_pad),
              child: SizedBox(
                height: _h,
                child: Row(children: [
                  for (var i = 0; i < _n; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          _tapX = _pad + (i + 0.5) * cell;
                          _splashCtrl.forward(from: 0);
                          widget.onTap(i);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: i == 2
                            ? _Emblem(proximity: cent)
                            : _label(cs, t, i, x),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Icon + chữ cross-fade mượt mà theo khoảng cách x thực tế
  Widget _label(ColorScheme cs, TextTheme t, int i, double x) {
    final near = (1.0 - (i - x).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(cs.onSurfaceVariant, cs.primary, near)!;
    final tab = _RootShellState._tabs[i];

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Transform.translate(
        offset: Offset(0, -3.0 * near),
        child: Transform.scale(
          scale: 1.0 + 0.12 * near,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Quầng sáng tròn sau icon đang chọn — "contour glow" kiểu ColorOS 17:
              // nút sáng từ trong ra thay vì nằm trên nền phẳng. Mờ dần theo `near`
              // nên lúc vuốt giữa 2 tab nó chuyển mượt chứ không bật/tắt.
              if (near > 0.01)
                IgnorePointer(
                  child: Container(
                    width: 30 + 8 * near,
                    height: 30 + 8 * near,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // ruột sáng nhẹ + viền sáng rõ: nút TRÒN nổi hẳn khỏi mặt kính,
                      // đúng kiểu Control Center ColorOS 17 (bỏ nền phẳng)
                      color: cs.primary.withValues(alpha: 0.16 * near),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.55 * near),
                        width: 1.2,
                      ),
                      boxShadow: [
                        // hào quang toả ra ngoài — "contour glow"
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.38 * near),
                          blurRadius: 16 * near,
                          spreadRadius: 1.0 * near,
                        ),
                        // lõi sáng bên trong cho cảm giác đèn thật
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.22 * near),
                          blurRadius: 6 * near,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
              // Icon viền nét mờ
              Opacity(
                opacity: (1.0 - near).clamp(0.0, 1.0),
                child: Icon(tab.icon, size: 20, color: cs.onSurfaceVariant),
              ),
              // Icon đặc phát sáng khi active
              Opacity(
                opacity: near,
                child: Icon(tab.active, size: 20, color: cs.primary),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        tab.label,
        style: t.labelSmall?.copyWith(
          letterSpacing: 0,
          fontSize: 9.5,
          fontWeight: near > 0.5 ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      ),
    ]);
  }
}

/// Vũng linh dịch vẽ tay + shader
class _LiquidPainter extends CustomPainter {
  final Animation<double> amb;
  final FragmentShader? shader;
  final Color color;
  final double alpha, selX, cent, flow, splash, tapX;

  _LiquidPainter({
    required this.amb,
    required this.shader,
    required this.color,
    required this.alpha,
    required this.selX,
    required this.cent,
    required this.flow,
    required this.splash,
    required this.tapX,
  }) : super(repaint: amb);

  @override
  void paint(Canvas canvas, Size size) {
    final t = amb.value * 2 * math.pi;
    final sh = shader;
    if (sh != null) {
      sh
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, t)
        ..setFloat(3, selX)
        ..setFloat(4, cent)
        ..setFloat(5, flow)
        ..setFloat(6, color.r)
        ..setFloat(7, color.g)
        ..setFloat(8, color.b)
        ..setFloat(9, alpha)
        ..setFloat(10, splash)
        ..setFloat(11, tapX);
      canvas.drawRect(Offset.zero & size, Paint()..shader = sh);
      return;
    }

    final paint = Paint()..color = color.withValues(alpha: alpha);
    final base = size.height * 0.82;
    final path = Path()..moveTo(0, size.height);
    for (var px = 0.0; px <= size.width; px += 3) {
      final k = (px - selX) / (28 + 10 * flow);
      final y = base -
          (24 + 8 * flow) * math.exp(-k * k) +
          1.2 * math.sin(px * 0.055 + t * 2) +
          0.8 * math.sin(px * 0.090 - t * 3);
      path.lineTo(px, y);
    }
    canvas.drawPath(
      path
        ..lineTo(size.width, size.height)
        ..close(),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      14 + 3.5 * cent,
      paint,
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.selX != selX ||
      old.cent != cent ||
      old.flow != flow ||
      old.splash != splash ||
      old.color != color;
}

/// Ô giữa: Biểu tượng Tu Tiên đồng bộ thuần túy với các tab còn lại
class _Emblem extends ConsumerWidget {
  final double proximity; // 0..1
  const _Emblem({required this.proximity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final emblem = ref.watch(tabEmblemProvider);
    final near = proximity.clamp(0.0, 1.0);
    final scale = 1.0 + 0.10 * near;
    final color = Color.lerp(cs.onSurfaceVariant, cs.primary, near)!;

    return Center(
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelIcon(emblem, grade: near > 0.5 ? 5 : 1, size: 24),
            const SizedBox(height: 2),
            Text(
              'Tu Tiên',
              maxLines: 1,
              style: t.labelSmall?.copyWith(
                fontSize: 9.5,
                letterSpacing: 0,
                fontWeight: near > 0.5 ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoạt ảnh mở màn: Chữ "Gác Truyện" bay vào giữa màn hình, chuyển hóa sang logo sắc nét
class _AppSplashIntro extends StatefulWidget {
  final VoidCallback onComplete;
  const _AppSplashIntro({required this.onComplete});

  @override
  State<_AppSplashIntro> createState() => _AppSplashIntroState();
}

class _AppSplashIntroState extends State<_AppSplashIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _ctrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final val = _ctrl.value;

        // Giai đoạn 1 (0.0 -> 0.38): Chữ bay từ dưới vào giữa màn hình
        final textIn = (val / 0.38).clamp(0.0, 1.0);
        final textSlide = Curves.easeOutCubic.transform(textIn);

        // Giai đoạn 2 (0.38 -> 0.68): Chữ tan biến, Logo nở ra giữa tâm
        final morph = ((val - 0.38) / 0.30).clamp(0.0, 1.0);
        final textOut = (1.0 - morph).clamp(0.0, 1.0);
        final logoIn = Curves.easeOutBack.transform(morph);

        // Giai đoạn 3 (0.70 -> 1.0): Mờ dần toàn bộ splash, vào giao diện chính
        final fadeOut = ((val - 0.70) / 0.30).clamp(0.0, 1.0);
        final overallOpacity = (1.0 - fadeOut).clamp(0.0, 1.0);

        return IgnorePointer(
          ignoring: val > 0.75,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _ctrl.stop();
              widget.onComplete();
            },
            child: Opacity(
              opacity: overallOpacity,
              child: Container(
                color: bg,
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Chữ bay vào tâm
                    if (textOut > 0.01)
                      Opacity(
                        opacity: (textIn * textOut).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 42 * (1.0 - textSlide) - 16 * morph),
                          child: Transform.scale(
                            scale: 0.90 + 0.14 * textSlide,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Gác Truyện',
                                  style: t.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 28,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Logo nở ra từ tâm
                    if (morph > 0.01)
                      Opacity(
                        opacity: morph.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.55 + 0.45 * logoIn,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: cs.primary.withValues(alpha: 0.08 * logoIn.clamp(0.0, 1.0)),
                                ),
                                child: const BrandLogo(height: 64),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'GÁC TRUYỆN',
                                style: t.labelSmall?.copyWith(
                                  color: cs.primary,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
