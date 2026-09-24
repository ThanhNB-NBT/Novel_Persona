import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Chất liệu cổ phong của Tu Tiên (GĐ7): nền giấy lụa, viền kép màu mực nâu, vân mây ở
/// bốn góc. CHỈ dùng trong khu Tu Tiên — khung app giữ tối giản.
class Silk {
  final Color paper, paperEdge, ink, inkSoft, line, seal;
  const Silk._(this.paper, this.paperEdge, this.ink, this.inkSoft, this.line, this.seal);

  static const _light = Silk._(Color(0xFFF6EFE0), Color(0xFFEADCC0), Color(0xFF3B2A1E),
      Color(0xFF7A6250), Color(0xFF9C6B3F), Pal.seal);
  static const _dark = Silk._(Color(0xFF2B241D), Color(0xFF211B15), Color(0xFFEFE2C8),
      Color(0xFFB9A58A), Color(0xFFC89A62), Pal.dSeal);

  static Silk of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

class SilkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const SilkCard({super.key, required this.child, this.onTap,
      this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final s = Silk.of(context);
    final radius = BorderRadius.circular(Rad.md);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: CustomPaint(
          painter: _SilkPainter(s),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _SilkPainter extends CustomPainter {
  final Silk s;
  _SilkPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Rad.md));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [s.paper, s.paperEdge],
        ).createShader(Offset.zero & size),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = s.line.withValues(alpha: 0.55)
      ..strokeWidth = 1.1;
    canvas.drawRRect(r.deflate(0.5), stroke);
    // viền trong mảnh — nét "bồi" của tranh cuộn
    canvas.drawRRect(r.deflate(4.5), stroke
      ..strokeWidth = 0.6
      ..color = s.line.withValues(alpha: 0.35));
    // vân mây: xoắn ốc hai vòng ở 4 góc, đối xứng qua tâm thẻ
    final cloud = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1
      ..color = s.line.withValues(alpha: 0.6);
    for (final (x, y) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
      canvas.save();
      canvas.translate(x > 0 ? 11 : size.width - 11, y > 0 ? 11 : size.height - 11);
      canvas.scale(x, y);
      canvas.drawArc(const Rect.fromLTWH(-1, -1, 10, 10), math.pi, math.pi * 1.5, false, cloud);
      canvas.drawArc(const Rect.fromLTWH(1.5, 1.5, 5, 5), math.pi, math.pi * 1.2, false, cloud);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SilkPainter old) => old.s != s;
}

/// Icon màu son đầu thẻ Tu Tiên — nét trơn, không đóng khung ô đỏ (3 ô đỏ
/// cạnh nhau nặng mắt; ô triện chỉ dành cho PageHeader và Động Phủ).
class SealIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const SealIcon(this.icon, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size * 0.8, color: Silk.of(context).seal);
}
