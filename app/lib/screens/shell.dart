import 'dart:math' as math;
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

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

/// Dock nổi: bên trong đọng một vũng LINH DỊCH có mặt nước gợn sóng. Mặt nước
/// dâng thành gò dưới tab đang chọn (không còn "ô chạy"), giọt Tu Tiên ở giữa
/// dính vào vũng qua smooth-min, và nội dung sau dock bị bẻ cong qua khối lỏng.
///
/// Toàn bộ do `shaders/liquid_dock.frag` vẽ — gooey là metaball thật trong SDF,
/// không phải mẹo blur + ngưỡng alpha ở tầng widget (cách đó gần như vô hình).
/// Cần Impeller; không có thì rơi về nền kính mờ thường.
class _Dock extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _Dock({required this.index, required this.onTap});
  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> with SingleTickerProviderStateMixin {
  // nhịp sống của chất lỏng. 2π/vòng: mọi hệ số thời gian trong shader là số
  // nguyên nên sóng khớp liền mạch qua mỗi vòng lặp, không giật.
  late final _amb =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  // shader dùng chung cho cả app, nạp đúng 1 lần
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
      // Hỏng lặng lẽ ở đây thì dock trông y hệt "quên làm hiệu ứng" → kêu lên.
      // Vẫn còn vũng vẽ tay ở _LiquidPainter nên không mất hẳn chất lỏng.
      debugPrint('liquid_dock.frag không nạp được: $e');
    }
  }

  @override
  void dispose() {
    _amb.dispose();
    super.dispose();
  }

  static const _h = 56.0, _pad = 6.0; // cao vùng tab, đệm quanh
  static const _n = 5;
  static const _splashMs = 750;

  // lần chạm gần nhất → sóng lan + giọt bắn. Painter tự tính độ tắt dần theo
  // đồng hồ nên không cần controller riêng.
  DateTime? _tapAt;
  double _tapX = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: LayoutBuilder(builder: (_, c) {
        final cell = (c.maxWidth - _pad * 2) / _n;
        // x chạy mượt giữa các tab: cấp cho shader cả vị trí gò lẫn mức "đang
        // chảy" (|x - đích| → sóng mạnh hơn, gò cao hơn giữa đường).
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.index.toDouble()),
          duration: const Duration(milliseconds: 560),
          curve: Curves.easeOutCubic,
          builder: (_, x, _) => _body(cs, t, dark, cell, c.maxWidth, x),
        );
      }),
    );
  }

  Widget _body(ColorScheme cs, TextTheme t, bool dark, double cell, double w,
      double x) {
    final liquid = cs.primary;

    return DecoratedBox(
      // bóng ở NGOÀI ClipRRect — trong clip là bị cắt mất, dock "bẹt"
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
              blurRadius: 26,
              offset: const Offset(0, 10)),
          BoxShadow(
              color: liquid.withValues(alpha: dark ? 0.14 : 0.09),
              blurRadius: 34),
        ],
      ),
      // RepaintBoundary: chất lỏng chạy 60fps, đừng kéo cả cây widget vẽ lại
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(children: [
            // nền kính mờ (không dính dáng gì tới shader → luôn có)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: dark ? 0.55 : 0.68),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
              ),
            ),
            // vũng linh dịch, vẽ THẲNG lên canvas — không qua ImageFilter nên
            // không phụ thuộc Impeller
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LiquidPainter(
                    amb: _amb,
                    shader: _liquid,
                    color: liquid,
                    alpha: dark ? 0.52 : 0.46,
                    selX: _pad + (x + 0.5) * cell,
                    cent: (1 - (x - 2).abs()).clamp(0.0, 1.0),
                    flow: (x - widget.index).abs().clamp(0.0, 1.0),
                    tapAt: _tapAt,
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
                          _tapAt = DateTime.now();
                          _tapX = _pad + (i + 0.5) * cell;
                          widget.onTap(i); // haptic do go() lo
                        },
                        behavior: HitTestBehavior.opaque,
                        child: i == 2
                            ? _Emblem(selected: widget.index == 2)
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

  /// Icon + chữ của 4 tab thường. Càng gần khối lỏng càng phồng lên, như bị
  /// mặt nước dâng đội lên.
  Widget _label(ColorScheme cs, TextTheme t, int i, double x) {
    final near = (1 - (i - x).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(cs.onSurfaceVariant, cs.primary, near)!;
    final tab = _RootShellState._tabs[i];
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Transform.translate(
        offset: Offset(0, -2.5 * near),
        child: Transform.scale(
          scale: 1 + 0.1 * near,
          child: Icon(i == widget.index ? tab.active : tab.icon,
              size: 20, color: color),
        ),
      ),
      const SizedBox(height: 2),
      // độ đậm CỐ ĐỊNH — đổi weight giữa hoạt ảnh làm chữ đổi bề rộng, nhìn giật
      Text(tab.label,
          style: t.labelSmall?.copyWith(
              letterSpacing: 0,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color)),
    ]);
  }
}

/// Vũng linh dịch trong dock. Có shader thì vẽ bằng `liquid_dock.frag` (metaball
/// + đổ bóng theo pháp tuyến); không có thì vẫn vẽ tay mặt sóng + giọt Tu Tiên —
/// nhạt hơn nhưng KHÔNG bao giờ để dock trơ ra như quên làm hiệu ứng.
class _LiquidPainter extends CustomPainter {
  final Animation<double> amb;
  final FragmentShader? shader;
  final Color color;
  final double alpha, selX, cent, flow, tapX;
  final DateTime? tapAt;
  _LiquidPainter({
    required this.amb,
    required this.shader,
    required this.color,
    required this.alpha,
    required this.selX,
    required this.cent,
    required this.flow,
    required this.tapAt,
    required this.tapX,
  }) : super(repaint: amb);

  /// 1 ngay lúc chạm → 0 sau _splashMs
  double get _splash {
    final at = tapAt;
    if (at == null) return 0;
    final age = DateTime.now().difference(at).inMilliseconds;
    return (1 - age / _DockState._splashMs).clamp(0.0, 1.0);
  }

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
        ..setFloat(10, _splash)
        ..setFloat(11, tapX);
      canvas.drawRect(Offset.zero & size, Paint()..shader = sh);
      return;
    }

    // ponytail: bản vẽ tay bỏ metaball (không có smooth-min trên Path) — mặt
    // sóng và giọt chỉ chồng lên nhau, không dính mềm. Đủ dùng cho máy không
    // chạy được shader; muốn dính mềm thì phải có shader.
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final base = size.height * 0.82;
    final path = Path()..moveTo(0, size.height);
    for (var px = 0.0; px <= size.width; px += 4) {
      final k = (px - selX) / 30;
      final y = base -
          20 * math.exp(-k * k) +
          1.4 * math.sin(px * 0.055 + t * 2) +
          0.9 * math.sin(px * 0.090 - t * 3);
      path.lineTo(px, y);
    }
    canvas.drawPath(
        path
          ..lineTo(size.width, size.height)
          ..close(),
        paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2),
        14 + 3 * cent, paint);
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.selX != selX ||
      old.cent != cent ||
      old.flow != flow ||
      old.color != color;
}

/// Ô giữa: chỉ còn biểu tượng, không chữ. Thân giọt Tu Tiên (méo + vệ tinh quay)
/// do _LiquidPainter vẽ phía sau, nên ở đây không vẽ gì thêm ngoài cái ấn tín.
class _Emblem extends ConsumerWidget {
  final bool selected;
  const _Emblem({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emblem = ref.watch(tabEmblemProvider); // biểu tượng do user chọn
    return Center(
      child: AnimatedScale(
        scale: selected ? 1.2 : 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        child: PixelIcon(emblem, grade: 5, size: 22),
      ),
    );
  }
}
