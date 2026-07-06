import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import 'explore/home.dart';
import 'library/library.dart';
import 'library/queue.dart';
import 'account/settings.dart';

/// Khung 4 tab: Tủ truyện · Khám phá · Hàng đợi · Cài đặt.
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
  static const _pages = [LibraryScreen(), HomeScreen(), QueueScreen(), SettingsScreen()];

  static const _tabs = [
    (icon: Icons.bookmarks_outlined, active: Icons.bookmarks_rounded, label: 'Tủ truyện'),
    (icon: Icons.explore_outlined, active: Icons.explore_rounded, label: 'Khám phá'),
    (icon: Icons.hourglass_empty_rounded, active: Icons.hourglass_bottom_rounded, label: 'Hàng đợi'),
    (icon: Icons.settings_outlined, active: Icons.settings_rounded, label: 'Cài đặt'),
  ];

  @override
  void initState() {
    super.initState();
    _i = sb.auth.currentUser != null ? 0 : 1; // Tủ truyện nếu đã đăng nhập, ngược lại Khám phá
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
      if (i == 2) ref.invalidate(translateQueueProvider);
      HapticFeedback.lightImpact();
      setState(() => _i = i);
    }

    void go(int i) {
      if (i < 0 || i > 3 || i == _i) return;
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
    const n = 4;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: DecoratedBox(
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
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(26),
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
        )),
      ),
    );
  }
}
