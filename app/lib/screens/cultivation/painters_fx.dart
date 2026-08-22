import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Các painter hiệu ứng đột phá/lên tầng — tách khỏi cultivation.dart.
// Mốc thời gian "lộ kết quả" dùng CHUNG giữa _AdvanceFxDialog và BurstPainter
// (painter không thấy state của dialog nên phải là hằng public).

/// Phần trăm timeline dialog mà tại đó kết quả (thành/bại) được lộ ra.
const advanceResultStart = 0.86;

/// Chớp sáng + 2 vòng xung kích + 12 tia lan ra (thành công); quầng đỏ tắt dần (bại).
/// loi = lôi kiếp: thiên lôi vàng giáng từ trên xuống trong nửa đầu hoạt ảnh.
/// Lớp khí tượng chạy sau WebP: mây không đứng yên và từng đạo lôi có dư quang
/// riêng, còn tia chính vẫn do asset `tribulation_sequence.webp` đảm nhiệm.
class TribulationAtmospherePainter extends CustomPainter {
  final double t;
  const TribulationAtmospherePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sky = Rect.fromLTWH(0, 0, size.width, size.height * 0.48);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF02050D).withValues(alpha: 0.62),
            const Color(0xFF11162A).withValues(alpha: 0.28),
            Colors.transparent,
          ],
        ).createShader(sky),
    );

    final cloud = Paint()
      ..color = const Color(0xFF171B2A).withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    for (var i = 0; i < 9; i++) {
      final drift = math.sin(t * math.pi * 2 + i * 1.71) * s * 0.035;
      final x = (i + 0.35) * size.width / 9 + drift;
      final y = s * (0.045 + (i % 3) * 0.045) +
          math.cos(t * math.pi * 2.4 + i) * s * 0.014;
      final w = s * (0.30 + (i % 3) * 0.055);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.45),
        cloud,
      );
    }

    for (final (i, hit) in [0.29, 0.56, 0.82].indexed) {
      final d = (t - hit).abs();
      if (d >= 0.055) continue;
      final flash = 1 - d / 0.055;
      final x = size.width * (0.34 + i * 0.16);
      final bolt = Path()
        ..moveTo(x, 0)
        ..lineTo(x - s * 0.026, s * 0.11)
        ..lineTo(x + s * 0.018, s * 0.18)
        ..lineTo(x - s * 0.045, s * 0.28);
      canvas.drawPath(
        bolt,
        Paint()
          ..color = const Color(0xFFD7E7FF).withValues(alpha: flash * 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 + i * 0.35
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TribulationAtmospherePainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Ma khí bện quanh linh thể thay vì để riêng một sprite tĩnh giữa màn hình.
class TammaPainter extends CustomPainter {
  final double t;
  final bool subdued;
  const TammaPainter(this.t, this.subdued);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.43);
    final s = size.shortestSide;
    final color = subdued ? const Color(0xFF8B5CF6) : const Color(0xFFE03131);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 4);
    canvas.drawCircle(
      c,
      s * (0.18 + pulse * 0.025),
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.19), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.23)),
    );
    final smoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi * 2 / 6 + t * (subdued ? 1.1 : 2.0);
      final start = c + Offset(math.cos(a), math.sin(a) * 0.45) * s * 0.26;
      final end =
          c + Offset(math.cos(a + 1.7), math.sin(a + 1.7) * 0.52) * s * 0.10;
      smoke
        ..color = color.withValues(alpha: 0.22 + pulse * 0.18)
        ..strokeWidth = 1.4 + (i % 2);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx - math.sin(a) * s * 0.16,
          start.dy + math.cos(a) * s * 0.12,
          end.dx + math.cos(a) * s * 0.13,
          end.dy - math.sin(a) * s * 0.10,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, smoke);
    }
  }

  @override
  bool shouldRepaint(covariant TammaPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.subdued != subdued;
}

class BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final bool ok;
  final bool loi;
  final bool
  major; // true = đại cảnh giới → bản điện ảnh; false = lên tầng snappy
  final ui.FragmentShader? shader; // nấc 2: godray+bloom additive (chỉ major)
  BurstPainter(
    this.t,
    this.color,
    this.ok,
    this.loi, {
    this.major = false,
    this.shader,
  });

  Offset _spoke(Offset c, int i, int count, double radius, double ang0) {
    final ang = ang0 + i * (math.pi * 2 / count);
    return c + Offset(math.cos(ang), math.sin(ang)) * radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Tâm nổ đặt quanh nhân vật (nội dung căn giữa màn). s = co giãn theo cỡ màn
    // để hiệu ứng KHÔNG bé tí / KHÔNG chạm cứng mép khi vẽ toàn màn hình.
    final c = Offset(size.width / 2, size.height * 0.40);
    final s = size.shortestSide;

    // Mây kiếp là các khối mây đen tụ từ hai mép vào thiên tâm, không dùng vòng cung giả.
    if (loi) {
      final gather = Curves.easeInOut.transform((t / 0.24).clamp(0.0, 1.0));
      final sky = Rect.fromLTWH(0, 0, size.width, size.height * 0.34);
      canvas.drawRect(
        sky,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF05080F).withValues(alpha: 0.82 * gather),
              const Color(0xFF111827).withValues(alpha: 0.54 * gather),
              Colors.transparent,
            ],
          ).createShader(sky),
      );
      final cloudShadow = Paint()
        ..color = const Color(0xFF070A10).withValues(alpha: 0.92 * gather)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      final cloudBody = Paint()
        ..color = const Color(0xFF1A2230).withValues(alpha: 0.88 * gather)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      for (var i = 0; i < 13; i++) {
        final targetX = (i + 0.5) * size.width / 13;
        final edgeX = i.isEven ? -s * 0.28 : size.width + s * 0.28;
        final x = edgeX + (targetX - edgeX) * gather;
        final y = s * 0.02 + (i % 4) * s * 0.07 + gather * s * 0.05;
        final w = s * (0.32 + (i % 3) * 0.07);
        final h = w * 0.60;
        final blob = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
        canvas.drawOval(blob.inflate(s * 0.035), cloudShadow);
        canvas.drawOval(blob, cloudBody);
      }
    }

    // ---- THẤT BẠI: quầng đỏ + tàn tro rơi ----
    if (!ok) {
      if (major && t < advanceResultStart) return;
      final resultT = major
          ? ((t - advanceResultStart) /
                    (1 - advanceResultStart))
                .clamp(0.0, 1.0)
          : t;
      final a = (1 - resultT) * 0.35;
      final failHaze = Rect.fromLTWH(0, c.dy - s * 0.18, size.width, s * 0.42);
      canvas.drawRect(
        failHaze,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              color.withValues(alpha: a),
              Colors.transparent,
            ],
          ).createShader(failHaze),
      );
      final ash = Paint()..color = color.withValues(alpha: (1 - resultT) * 0.6);
      for (var i = 0; i < 10; i++) {
        final p = _spoke(c, i, 10, s * 0.08 + resultT * s * 0.12, i.toDouble());
        canvas.drawCircle(
          Offset(p.dx, p.dy + resultT * s * 0.18),
          (1 - resultT) * 2.4,
          ash,
        );
      }
      return;
    }

    if (major && t < advanceResultStart) return;

    // ================= THÀNH CÔNG =================
    // bt = thời gian vụ nổ ánh sáng: minor chạy cả hoạt ảnh, major tái chuẩn
    // hoá 0..1 từ lúc lộ kết quả (sét đã dứt) để chớp/vòng/tia nổ đúng nhịp.
    final bt = major
        ? ((t - advanceResultStart) /
                  (1 - advanceResultStart))
              .clamp(0.0, 1.0)
        : t;
    // 1) HỘI TỤ linh khí: hạt xoáy vào tâm, sáng dần trước va chạm (cả lên tầng)
    final gatherEnd = major ? 0.10 : 0.28;
    if (t < gatherEnd) {
      final g = t / gatherEnd;
      final n = major ? 16 : 12;
      final gp = Paint();
      for (var i = 0; i < n; i++) {
        final p = _spoke(
          c,
          i,
          n,
          (1 - g) * s * (major ? 0.42 : 0.30) + 8,
          g * 3 + i.toDouble(),
        );
        gp.color = color.withValues(alpha: g * 0.9);
        canvas.drawCircle(p, 1.5 + g * 1.6, gp);
      }
      if (!major) {
        canvas.drawCircle(
          c,
          s * 0.32 * (1 - g),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: g * 0.4),
        );
      }
    }

    // Tiểu cảnh giới: linh văn xoay khép trận và sóng tu vi dâng lên, không dùng kiếp lôi.
    if (!major) {
      final spin = t * math.pi * 2.4;
      final runePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: (1 - t) * 0.8);
      for (final (radius, reverse) in [(s * 0.16, false), (s * 0.23, true)]) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          reverse ? -spin : spin,
          math.pi * 1.35,
          false,
          runePaint,
        );
      }
      for (var i = 0; i < 8; i++) {
        final p = _spoke(c, i, 8, s * (0.20 + 0.05 * t), spin);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(spin + i);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 5, height: 5),
          runePaint,
        );
        canvas.restore();
      }
      final waveY = c.dy + s * 0.18 - t * s * 0.48;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx, waveY), width: s * 0.34, height: 18),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t) + 0.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..color = color.withValues(alpha: (1 - t) * 0.7),
      );
    }

    // 2) CHỚP va chạm — major nổ trắng to, lên tầng lóe MÀU dịu (không chói)
    const flashLen = 0.16;
    if (bt < flashLen) {
      final ft = bt / flashLen;
      final r = s * (major ? 0.5 : 0.34);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(
                color,
                Colors.white,
                major ? 0.75 : 0.55,
              )!.withValues(alpha: (1 - ft) * (major ? 0.85 : 0.7)),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Pháp trận sau va chạm: mảnh, lệch pha, để cảm giác "khai khiếu" thay vì HUD tròn đều.
    final wheel = ((bt - 0.04) / 0.68).clamp(0.0, 1.0);
    if (wheel > 0) {
      final ease = Curves.easeOut.transform(wheel);
      final spin = bt * math.pi * (major ? 0.9 : 1.4);
      final radius = s * (0.10 + ease * (major ? 0.38 : 0.28));
      final rune = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = major ? 1.4 : 1.1
        ..color = color.withValues(alpha: (1 - wheel) * (major ? 0.72 : 0.58));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(spin);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        -math.pi * 0.82,
        math.pi * 1.48,
        false,
        rune,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.78),
        math.pi * 0.18,
        math.pi * 1.35,
        false,
        rune,
      );
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi * 2 / 12;
        final inner = radius * (0.92 + (i.isEven ? 0.02 : 0.0));
        final outer = inner + (i.isEven ? s * 0.045 : s * 0.022);
        canvas.drawLine(
          Offset(math.cos(a) * inner, math.sin(a) * inner),
          Offset(math.cos(a) * outer, math.sin(a) * outer),
          rune,
        );
      }
      canvas.restore();
    }

    // Dải khí nâng người lên sau khi phá cảnh, chạy lệch nhịp để không thành vòng loading.
    final qi = ((bt - 0.12) / 0.72).clamp(0.0, 1.0);
    if (qi > 0) {
      final qiPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = major ? 2.0 : 1.3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      for (var i = 0; i < (major ? 5 : 3); i++) {
        final phase = bt * math.pi * 2.4 + i * 1.7;
        final y = c.dy + s * 0.28 - qi * s * (0.54 + i * 0.035);
        final w = s * (0.12 + qi * 0.18);
        qiPaint.color = color.withValues(
          alpha: (1 - qi) * (major ? 0.32 : 0.24),
        );
        final path = Path()
          ..moveTo(c.dx - w, y)
          ..cubicTo(
            c.dx - w * 0.35,
            y - 9 + math.sin(phase) * 8,
            c.dx + w * 0.35,
            y + 9 + math.cos(phase) * 8,
            c.dx + w,
            y,
          );
        canvas.drawPath(path, qiPaint);
      }
    }

    // 4) TRỤ SÁNG dựng lên — major cao vút, lên tầng cột ngắn nhẹ
    {
      final pt = (bt / (major ? 0.4 : 0.6)).clamp(0.0, 1.0);
      final h =
          (major ? size.height * 0.85 : s * 0.55) *
          Curves.easeOut.transform(pt);
      final w =
          ((major ? 32.0 : 16.0) + (major ? 18 : 9) * math.sin(bt * 30).abs()) *
          (1 - pt * 0.3);
      final rect = Rect.fromLTWH(c.dx - w / 2, c.dy - h, w, h + 20);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: (1 - bt) * (major ? 0.85 : 0.6)),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, major ? 8 : 5),
      );
    }

    // 5) VÒNG XUNG KÍCH (glow, scale theo màn — major lan rộng hơn)
    for (final delay in const [0.0, 0.22]) {
      final v = ((bt - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (v <= 0) continue;
      canvas.drawCircle(
        c,
        s * 0.05 + v * s * (major ? 0.52 : 0.36),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - v) * 5 + 0.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
          ..color = color.withValues(alpha: (1 - v) * 0.8),
      );
    }

    // 6) TIA SÁNG phóng ra
    {
      final ray = Paint()
        ..strokeWidth = major ? 2.2 : 1.8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: (1 - bt) * 0.85);
      for (var i = 0; i < 14; i++) {
        final ang = i * math.pi * 2 / 14 + 0.26;
        final dir = Offset(math.cos(ang), math.sin(ang));
        canvas.drawLine(
          c + dir * (s * 0.08 + bt * s * (major ? 0.36 : 0.28)),
          c + dir * (s * 0.12 + bt * s * (major ? 0.44 : 0.34)),
          ray,
        );
      }
    }

    // 7) ĐỐM LINH KHÍ bay lên
    final emberN = major ? 20 : 12;
    final ember = Paint();
    for (var i = 0; i < emberN; i++) {
      final seed = (i * 53) % 100 / 100.0;
      final x = c.dx + ((i * 37 % 200) - 100) / 100.0 * s * 0.4 * (0.4 + seed);
      final y = c.dy + s * 0.1 - bt * s * (major ? 0.7 : 0.5) * (0.6 + seed);
      final a = (1 - bt) * 0.9 * (bt > 0.15 ? 1.0 : bt / 0.15);
      ember.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), (1 - bt) * 2.4 + 0.6, ember);
    }

    // 8) NẤC 2: shader godray + bloom phủ additive lên trên (chỉ major, sau hội tụ)
    if (shader != null && major && t > advanceResultStart) {
      shader!
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, (t - 0.22) / 0.78) // tái chuẩn hoá 0..1 từ lúc va chạm
        ..setFloat(3, color.r)
        ..setFloat(4, color.g)
        ..setFloat(5, color.b)
        ..setFloat(6, c.dx)
        ..setFloat(7, c.dy);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus,
      );
    }
  }

  @override
  bool shouldRepaint(BurstPainter old) => old.t != t;
}
