import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Chuyển màn dùng chung: fade ngắn, không che nội dung và không vẽ lại cả màn.
CustomTransitionPage<T> inkPage<T>({required Widget child, LocalKey? key}) =>
    CustomTransitionPage<T>(
      key: key,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
      // trang mở riêng nằm NGOÀI shell: màn nền trong suốt (Hàng đợi, Thông báo — viết
      // để lộ khí quyển shell khi là tab) sẽ lộ ra nền đen → tô nền theme bên dưới
      child: BackToFallback(
        child: Builder(
            builder: (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor, child: child)),
      ),
    );

/// Trang mở thẳng bằng link là trang ĐẦU của ngăn xếp: Back hệ thống sẽ thoát app
/// (hoặc về app vừa mở link). Chặn lại, đưa về [fallback] như người dùng chờ đợi.
class BackToFallback extends StatelessWidget {
  final String fallback;
  final Widget child;
  const BackToFallback({super.key, this.fallback = '/', required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(fallback);
      },
      child: child,
    );
  }
}
