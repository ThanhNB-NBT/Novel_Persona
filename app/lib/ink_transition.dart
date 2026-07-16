import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Chuyển màn "MỰC TÀU LOANG" — chữ ký chuyển động của app (chốt 2026-07-16).
/// Màn mới không slide/fade mà HIỆN QUA VẾT MỰC loang từ giữa trang: mép nhòe
/// gợn sóng bất định như mực thấm giấy dó, vài giọt mực văng trước mép rồi bị
/// vệt chính nuốt khi loang rộng; pop thì mực RÚT về (chạy ngược). Mọi route
/// push (trừ màn đọc — có transition riêng theo chế độ lật/cuộn) đi qua đây.
CustomTransitionPage<T> inkPage<T>({required Widget child, LocalKey? key}) =>
    CustomTransitionPage<T>(
      key: key,
      transitionDuration: const Duration(milliseconds: 470),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (context, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return AnimatedBuilder(
          animation: t,
          builder: (_, _) => _InkReveal(progress: t.value, child: child),
        );
      },
      child: child,
    );

class _InkReveal extends StatelessWidget {
  final double progress;
  final Widget child;
  const _InkReveal({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    if (progress >= 1) return child;
    if (progress <= 0.001) return const SizedBox.shrink();
    // viền mực sẫm bám mép vết loang (đậm lúc mới loang, tan khi phủ kín) —
    // chính nó bán cái chất "mực" thay vì chỉ là mặt nạ tròn vô hồn
    final ink = Color.lerp(
        Colors.black, Theme.of(context).colorScheme.primary, 0.25)!;
    return Stack(fit: StackFit.expand, children: [
      ClipPath(clipper: _InkClipper(progress), child: child),
      IgnorePointer(
        child: CustomPaint(painter: _InkRimPainter(progress, ink)),
      ),
    ]);
  }
}

class _InkClipper extends CustomClipper<Path> {
  final double t;
  _InkClipper(this.t);
  @override
  Path getClip(Size size) => inkBlobPath(size, t);
  @override
  bool shouldReclip(_InkClipper old) => old.t != t;
}

class _InkRimPainter extends CustomPainter {
  final double t;
  final Color ink;
  _InkRimPainter(this.t, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 0.98) return;
    canvas.drawPath(
      inkBlobPath(size, t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * (1 - t) + 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = ink.withValues(alpha: 0.4 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_InkRimPainter old) => old.t != t || old.ink != ink;
}

/// Vết mực tại tiến độ t (0..1): blob 64 đỉnh quanh tâm, bán kính gợn 3 tầng
/// sóng sin LỆCH PHA THEO t (mép "sống" như đang thấm), phủ kín màn khi t→1.
/// Kèm 6 giọt mực văng trước mép (vị trí tất định — không nhấp nháy giữa frame).
Path inkBlobPath(Size size, double t) {
  final c = Offset(size.width * 0.5, size.height * 0.42);
  // 0.62 > 1/2 đường chéo tính từ tâm lệch — kín cả 4 góc khi t=1, wob=0
  final maxR =
      math.sqrt(size.width * size.width + size.height * size.height) * 0.62;
  final r = maxR * math.pow(t, 0.85);
  final wob = (1 - t) * 0.22; // gợn mạnh lúc đầu, phẳng dần khi phủ kín
  final path = Path();
  const n = 64;
  for (var i = 0; i <= n; i++) {
    final a = i / n * 2 * math.pi;
    final w = 1 +
        wob *
            (0.55 * math.sin(3 * a + t * 9) +
                0.30 * math.sin(7 * a - t * 6) +
                0.15 * math.sin(11 * a + t * 4));
    final p = c + Offset(math.cos(a), math.sin(a)) * (r * w);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
  if (t < 0.85) {
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3 + 0.4;
      final d = r * (1.12 + 0.10 * math.sin(k * 2.1 + t * 5));
      final rad = maxR * 0.02 * (1 - t) * (1 + k % 3);
      path.addOval(Rect.fromCircle(
          center: c + Offset(math.cos(a), math.sin(a)) * d, radius: rad));
    }
  }
  return path;
}
