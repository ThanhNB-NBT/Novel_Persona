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
import '../theme.dart';
import '../tts.dart';

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
            // Đàn hồi kiểu Fluid Fusion (ColorOS 17): vuốt tới tab đầu/cuối thì
            // trang căng ra rồi bật lại theo ngón tay, thay vì khựng cứng.
            physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
            onPageChanged: changed,
            children: [for (final p in _pages) _KeepAlive(child: p)],
          ),
          // Tab dùng IndexedStack (giữ sống) nên không tự fetch lại — go() làm mới
          // dữ liệu khi mở tab để thấy thay đổi vừa gây ở màn khác.
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _GlobalTtsBar(),
                _Dock(index: _i, pageController: _pc, onTap: go),
              ],
            ),
          ),
          // Hoạt ảnh khởi động: Chữ "Gác Truyện" bay vào giữa màn hình rồi chuyển hóa sang Logo
          if (_showSplash)
            AppSplashIntro(
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

/// Thanh điều khiển máy đọc TTS toàn cục: hiển thị khi có audio đang phát/tạm dừng.
class _GlobalTtsBar extends StatelessWidget {
  const _GlobalTtsBar();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsState>(
      valueListenable: TtsPlayer.i.state,
      builder: (context, st, _) {
        if (!st.active) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final dark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (st.novelId != null) {
                  context.push('/novel/${st.novelId}/read/${st.chapterIndex}');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: dark
                      ? Pal.dSurface.withValues(alpha: 0.92)
                      : Pal.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      st.playing
                          ? Icons.graphic_eq_rounded
                          : Icons.headphones_rounded,
                      size: 20,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Đang phát chương ${st.chapterIndex}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        st.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                        color: cs.primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () {
                        if (st.playing) {
                          TtsPlayer.i.pause();
                        } else {
                          TtsPlayer.i.resume();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => TtsPlayer.i.stop(),
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
  static const _h = 56.0, _pad = 6.0;
  static const _n = 5;

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
        // Chỉ còn bám cử chỉ vuốt PageController — dock đã bỏ hoạt ảnh chất lỏng.
        return AnimatedBuilder(
          animation: widget.pageController,
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
    // Khoảng cách tới tab giữa — emblem Tu Tiên vẫn dùng để nảy nhẹ khi tới gần.
    final cent = (1.0 - (x - 2.0).abs()).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, 10),
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
                    // trong hơn hẳn: bản thật nhìn xuyên thấy nội dung phía sau
                    color: cs.surface.withValues(alpha: dark ? 0.42 : 0.55),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(32),
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
                        onTap: () => widget.onTap(i),
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
    // ColorOS 17 KHÔNG tô màu nhấn cho tab đang chọn: chỉ icon đặc + chữ đậm,
    // toàn thanh một tông mực. Thêm màu vào là thành thanh menu khác hẳn.
    final color = Color.lerp(cs.onSurfaceVariant, cs.onSurface, near)!;
    final tab = _RootShellState._tabs[i];

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Transform.translate(
        offset: Offset(0, -3.0 * near),
        child: Transform.scale(
          scale: 1.0 + 0.12 * near,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Icon viền nét mờ
              Opacity(
                opacity: (1.0 - near).clamp(0.0, 1.0),
                child: Icon(tab.icon, size: 20, color: cs.onSurfaceVariant),
              ),
              // Icon đặc phát sáng khi active
              Opacity(
                opacity: near,
                child: Icon(tab.active, size: 20, color: cs.onSurface),
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

/// Hoạt ảnh mở màn: Dải lụa ánh sáng bay lượn mềm mại uốn lượn vào giữa tâm,
/// sau đó ngưng kết thành đốm sáng và bừng nở ra logo Gác Truyện.
class AppSplashIntro extends StatefulWidget {
  final VoidCallback onComplete;
  const AppSplashIntro({super.key, required this.onComplete});

  @override
  State<AppSplashIntro> createState() => _AppSplashIntroState();
}

class _AppSplashIntroState extends State<AppSplashIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final val = _ctrl.value;

        // Giai đoạn 1 (0.0 -> 0.65): Nét cọ vẽ logo thư pháp GT từ trên trái xuống
        final brushProgress = Curves.easeInOutCubic.transform((val / 0.65).clamp(0.0, 1.0));

        // Giai đoạn 2 (0.35 -> 0.75): Chữ GÁC TRUYỆN và slogan hiện lên trang nhã
        final textProgress = ((val - 0.35) / 0.40).clamp(0.0, 1.0);
        final textAlpha = Curves.easeOutCubic.transform(textProgress);
        final textScale = 0.95 + 0.05 * Curves.easeOutBack.transform(textProgress);

        // Giai đoạn 3 (0.88 -> 1.0): Mờ dần chuyển vào màn hình chính
        final fadeOut = ((val - 0.88) / 0.12).clamp(0.0, 1.0);
        final overallOpacity = (1.0 - fadeOut).clamp(0.0, 1.0);

        final inkColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E242B);
        final logoAsset = isDark ? 'assets/icon/gt_white.png' : 'assets/icon/gt_ink.png';

        return Opacity(
          opacity: overallOpacity,
          child: Container(
            color: bg,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Tầng nền: Vệt mực loang mờ nhạt và các giọt mực bắn tự nhiên
                CustomPaint(
                  size: const Size(360, 360),
                  painter: _InkSplatterPainter(
                    progress: brushProgress,
                    color: inkColor,
                  ),
                ),

                // Tầng chính: Bức hoạ cọ vẽ GT reveal theo chuyển động ngọn bút
                Center(
                  child: SizedBox(
                    width: 260,
                    height: 188,
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        // Quét dải gradient từ góc trên trái xuống dưới phải theo chiều viết cọ
                        final sweep = brushProgress * 1.5;
                        return LinearGradient(
                          begin: const Alignment(-1.0, -1.0),
                          end: const Alignment(1.0, 1.0),
                          stops: [
                            (sweep - 0.28).clamp(0.0, 1.0),
                            sweep.clamp(0.0, 1.0),
                          ],
                          colors: const [
                            Colors.black,
                            Colors.transparent,
                          ],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: Image.asset(
                        logoAsset,
                        width: 260,
                        height: 188,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),

                // Tầng chữ: Thương hiệu GÁC TRUYỆN hiện lên phía dưới
                if (textAlpha > 0.01)
                  Positioned(
                    bottom: MediaQuery.of(context).size.height * 0.26,
                    child: Opacity(
                      opacity: textAlpha,
                      child: Transform.scale(
                        scale: textScale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'GÁC TRUYỆN',
                              style: t.titleMedium?.copyWith(
                                letterSpacing: 6.0 - 2.0 * textAlpha,
                                fontWeight: FontWeight.w700,
                                color: inkColor,
                                fontFamily: 'serif',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Vạn Cuốn Thư Sinh • Nhất Niệm Thông Thiên',
                              style: t.labelSmall?.copyWith(
                                letterSpacing: 1.8,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.80),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Vẽ quầng mực loang và các hạt mực bắn tự nhiên khi hạ bút
class _InkSplatterPainter extends CustomPainter {
  final double progress;
  final Color color;

  _InkSplatterPainter({
    required this.progress,
    required this.color,
  });

  // Tọa độ tương đối của 18 hạt mực bắn (x, y, radius, triggerProgress, alpha)
  static final List<List<double>> _splatters = [
    [-95, -70, 2.2, 0.10, 0.70],
    [-80, -90, 1.8, 0.15, 0.60],
    [-110, -40, 3.0, 0.18, 0.75],
    [-65, -55, 1.4, 0.22, 0.50],
    [-20, -75, 2.5, 0.28, 0.65],
    [30, -60, 3.2, 0.35, 0.80],
    [70, -70, 1.6, 0.40, 0.55],
    [95, -45, 2.8, 0.45, 0.70],
    [105, -20, 2.0, 0.50, 0.60],
    [85, 20, 3.5, 0.55, 0.75],
    [60, 50, 2.4, 0.60, 0.65],
    [25, 75, 1.9, 0.65, 0.55],
    [-10, 85, 3.2, 0.70, 0.80],
    [-45, 65, 2.1, 0.75, 0.60],
    [-80, 45, 2.6, 0.80, 0.70],
    [115, 35, 1.5, 0.82, 0.45],
    [-30, -30, 2.0, 0.85, 0.50],
    [40, 10, 1.8, 0.90, 0.55],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;

    final center = Offset(size.width / 2, size.height / 2);

    // 1. Quầng mực khuếch tán ở tâm (radial ink wash)
    final washRadius = 40.0 + 85.0 * Curves.easeOutCubic.transform(progress);
    final washAlpha = (0.07 * (1.0 - progress * 0.3)).clamp(0.0, 0.10);
    final washPaint = Paint()
      ..color = color.withValues(alpha: washAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, washRadius, washPaint);

    // 2. Hạt mực bắn (Ink Droplets)
    final dropPaint = Paint()..style = PaintingStyle.fill;
    for (final s in _splatters) {
      final trigger = s[3];
      if (progress >= trigger) {
        final dropP = ((progress - trigger) / 0.20).clamp(0.0, 1.0);
        final dropScale = Curves.easeOutBack.transform(dropP);
        final ox = center.dx + s[0];
        final oy = center.dy + s[1];
        final r = s[2] * dropScale;
        final a = (s[4] * dropP).clamp(0.0, 1.0);

        dropPaint.color = color.withValues(alpha: a);
        canvas.drawCircle(Offset(ox, oy), r, dropPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InkSplatterPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
