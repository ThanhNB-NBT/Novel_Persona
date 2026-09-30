import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Các painter hiệu ứng đột phá/lên tầng — tách khỏi cultivation.dart.
// Mốc thời gian "lộ kết quả" dùng CHUNG giữa _AdvanceFxDialog và BurstPainter
// (painter không thấy state của dialog nên phải là hằng public).

/// Phần trăm timeline dialog mà tại đó kết quả (thành/bại) được lộ ra.
const advanceResultStart = 0.86;

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

/// Vẽ [shader] vào [dst] ở độ phân giải LOGIC/[k] rồi phóng lên (bilinear). Khói/mây
/// ray-march vốn mềm nên phóng không lộ, mà rẻ hơn ~(dpr·k)² lần so với chạy shader
/// trên từng px vật lý — máy yếu/giả lập mới giữ được khung hình.
/// [setUniforms] nhận k: toạ độ uniform tính theo px ảnh nhỏ, gốc tại dst.topLeft.
void paintShaderLowRes(Canvas canvas, Rect dst, ui.FragmentShader shader, double k,
    void Function(double k) setUniforms) {
  final w = math.max(1, (dst.width / k).ceil());
  final h = math.max(1, (dst.height / k).ceil());
  setUniforms(k);
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = shader);
  final pic = rec.endRecording();
  // ponytail: ảnh mỗi khung để GC dọn (không dispose được khi layer còn giữ); cache
  // theo khung nếu hồ sơ bộ nhớ thấy áp lực.
  final img = pic.toImageSync(w, h);
  pic.dispose();
  canvas.drawImageRect(img, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), dst,
      Paint()..filterQuality = FilterQuality.low);
}

/// Tâm Ma 3D (shaders/tamma.frag): khối ma khí thể tích quanh [center]. Vẽ 2 lượt
/// — front=false sau ảnh mặt quỷ (có lõi sáng), front=true trước ảnh (khói mỏng).
/// Cả hai lượt dùng CHUNG một FragmentShader: uniform đặt ngay trước mỗi drawRect.
class TammaVolumePainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double v; // tiến trình pha Tâm Ma 0..1
  final double time; // giây
  final bool win;
  final bool front;
  final double radius;
  const TammaVolumePainter(this.shader, this.v, this.time, this.win,
      {required this.front, this.radius = 130});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final box = Rect.fromCircle(center: c, radius: radius * 1.5);
    paintShaderLowRes(canvas, box, shader, 1.2, (k) {
      shader
        ..setFloat(0, box.width / k)
        ..setFloat(1, box.height / k)
        ..setFloat(2, box.width / 2 / k)
        ..setFloat(3, box.height / 2 / k)
        ..setFloat(4, radius / k)
        ..setFloat(5, time)
        ..setFloat(6, v)
        ..setFloat(7, win ? 1 : 0)
        ..setFloat(8, front ? 1 : 0);
    });
  }

  @override
  bool shouldRepaint(TammaVolumePainter old) => old.v != v || old.time != time;
}

/// Chớp sáng + vòng xung kích + tia lan ra (thành công); quầng đỏ + vết nứt (bại).
/// loi = lôi kiếp: mây đen tụ từ hai mép (thân sét vẽ ở painters_lightning.dart).
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

  /// Hạt sáng: quầng gradient + lõi pha trắng (không blur — vẽ mỗi khung).
  static void _glow(Canvas canvas, Offset p, double r, Color col, double a) {
    if (a <= 0.01) return;
    canvas.drawCircle(
      p,
      r * 3,
      Paint()
        ..shader = RadialGradient(colors: [
          col.withValues(alpha: a * 0.45),
          col.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: p, radius: r * 3)),
    );
    canvas.drawCircle(
        p, r, Paint()..color = Color.lerp(col, Colors.white, 0.45)!.withValues(alpha: a));
  }

  /// Đuôi thon nối các điểm [pts] (đầu → đuôi), mảnh + mờ dần về cuối.
  static void _tail(Canvas canvas, List<Offset> pts, double w, Color col, double a) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var k = 1; k < pts.length; k++) {
      final f = 1 - k / pts.length;
      paint
        ..strokeWidth = w * f + 0.3
        ..color = col.withValues(alpha: a * f * f);
      canvas.drawLine(pts[k - 1], pts[k], paint);
    }
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
      // tâm mạch nứt: 8 tia gãy khúc lóe ra từ tâm rồi tắt trong nửa đầu
      final crack = (1 - resultT * 1.8).clamp(0.0, 1.0);
      if (crack > 0) {
        final cp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (var i = 0; i < 8; i++) {
          final dir0 = i * math.pi / 4 + 0.3;
          var ang = dir0;
          var q = c;
          final path = Path()..moveTo(q.dx, q.dy);
          for (var k = 0; k < 6; k++) {
            // gãy khúc tất định nhưng luôn kéo về hướng gốc → tia nứt, không thành cành cây
            ang = dir0 + ((i * 7 + k * 5) % 5 - 2) * 0.16;
            q += Offset(math.cos(ang), math.sin(ang)) * s * (0.03 + 0.006 * (i % 3));
            path.lineTo(q.dx, q.dy);
          }
          cp
            ..strokeWidth = 3.5
            ..color = color.withValues(alpha: crack * 0.35);
          canvas.drawPath(path, cp);
          cp
            ..strokeWidth = 1.1
            ..color = Color.lerp(color, Colors.white, 0.5)!.withValues(alpha: crack * 0.9);
          canvas.drawPath(path, cp);
        }
      }
      // tàn đỏ bắn ra rồi rơi xuống theo trọng lực, có đuôi
      for (var i = 0; i < 14; i++) {
        final ang = i * math.pi * 2 / 14 + i * 0.37;
        final v0 = s * (0.18 + (i % 4) * 0.05);
        Offset at(double u) => c +
            Offset(math.cos(ang) * v0 * u, math.sin(ang) * v0 * u * 0.6 + s * 0.35 * u * u);
        final u = resultT;
        _tail(canvas, [for (var k = 0; k < 6; k++) at(math.max(0, u - k * 0.03))],
            1.8, color, (1 - u) * 0.7);
        _glow(canvas, at(u), 1.4, color, (1 - u) * 0.9);
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
    // 1) HỘI TỤ linh khí: dải khí xoắn ốc hút vào tâm (đuôi thon chỉ hướng bay),
    // tâm sáng dần trước va chạm. Major không có pha này (kết quả lộ sau kiếp).
    final gatherEnd = major ? 0.10 : 0.28;
    if (!major && t < gatherEnd) {
      final g = t / gatherEnd;
      const n = 12;
      for (var i = 0; i < n; i++) {
        Offset at(double gg) {
          final ang = gg * 3.2 + i * math.pi * 2 / n;
          final r = (1 - gg) * s * 0.34 + 6;
          return c + Offset(math.cos(ang), math.sin(ang) * 0.8) * r;
        }

        _tail(canvas, [for (var k = 0; k < 7; k++) at(math.max(0, g - k * 0.035))],
            2.4, color, 0.25 + g * 0.6);
        _glow(canvas, at(g), 1.3 + g * 0.8, color, 0.3 + g * 0.6);
      }
      _glow(canvas, c, 3 + g * 6, color, g * 0.8);
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
      // 8 quẻ bát quái xoay quanh (mỗi quẻ 3 hào: liền = dương, đứt = âm), đặt
      // tiếp tuyến vòng trận + quầng sáng mờ — thay cho ô vuông trơn.
      final yao = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6
        ..color = Color.lerp(color, Colors.white, 0.35)!
            .withValues(alpha: (1 - t) * 0.9);
      for (var i = 0; i < 8; i++) {
        final ang = spin + i * math.pi / 4;
        final p = _spoke(c, i, 8, s * (0.20 + 0.05 * t), spin);
        canvas.drawCircle(
          p,
          9,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: (1 - t) * 0.35),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: p, radius: 9)),
        );
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(ang + math.pi / 2);
        final bits = 7 - i; // Càn ☰ … Khôn ☷
        for (var j = 0; j < 3; j++) {
          final y = (j - 1) * 2.8;
          if ((bits >> j) & 1 == 1) {
            canvas.drawLine(Offset(-3.6, y), Offset(3.6, y), yao);
          } else {
            canvas.drawLine(Offset(-3.6, y), Offset(-0.9, y), yao);
            canvas.drawLine(Offset(0.9, y), Offset(3.6, y), yao);
          }
        }
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

    // 2) CHỚP va chạm — major nổ trắng to, lên tầng lóe MÀU dịu (không chói);
    // kèm vệt sáng ngang mảnh (lens streak) cho cảm giác chói lóa thật.
    const flashLen = 0.16;
    if (bt < flashLen) {
      final ft = bt / flashLen;
      final r = s * (major ? 0.5 : 0.34);
      final hot = Color.lerp(color, Colors.white, major ? 0.75 : 0.55)!;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              hot.withValues(alpha: (1 - ft) * (major ? 0.85 : 0.7)),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      final streak = Rect.fromCenter(
          center: c, width: s * (major ? 1.6 : 1.0) * (0.5 + ft), height: 6 + (1 - ft) * 6);
      canvas.drawOval(
        streak,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: (1 - ft) * 0.9),
            hot.withValues(alpha: 0),
          ]).createShader(streak),
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

    // 4) TRỤ SÁNG — cột THON (gốc rộng, ngọn nhỏ) dựng từ 3 lớp lồng nhau (rộng mờ →
    // hẹp đậm → lõi trắng) cho mép mềm, mỗi lớp tan dần lên ngọn; major cao vút.
    {
      final pt = (bt / (major ? 0.4 : 0.6)).clamp(0.0, 1.0);
      final h = (major ? size.height * 0.85 : s * 0.55) * Curves.easeOut.transform(pt);
      final fade = 1 - bt;
      final w0 = ((major ? 44.0 : 22.0) + (major ? 14 : 7) * math.sin(bt * 30).abs()) *
          (1 - pt * 0.3);
      final base = c.dy + 20;
      for (final (wk, col, a) in [
        (1.0, color, 0.22),
        (0.55, color, 0.4),
        (0.22, Colors.white, 0.75),
      ]) {
        final w = w0 * wk;
        final path = Path()
          ..moveTo(c.dx - w / 2, base)
          ..lineTo(c.dx - w * 0.15, base - h)
          ..lineTo(c.dx + w * 0.15, base - h)
          ..lineTo(c.dx + w / 2, base)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                col.withValues(alpha: fade * a * (major ? 1 : 0.8)),
                col.withValues(alpha: fade * a * 0.6),
                col.withValues(alpha: 0),
              ],
              stops: const [0, 0.55, 1],
            ).createShader(Rect.fromLTWH(c.dx - w / 2, base - h, w, math.max(h, 1))),
        );
      }
    }

    // 5) VÒNG XUNG KÍCH: dải sáng có bề dày (gradient viền mờ hai phía) thay vòng
    // nét mảnh + vòng sóng phẳng dưới chân lan theo phối cảnh.
    for (final delay in const [0.0, 0.22]) {
      final v = ((bt - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (v <= 0 || v >= 1) continue;
      final r = s * 0.05 + Curves.easeOut.transform(v) * s * (major ? 0.52 : 0.36);
      final band = 4 + (1 - v) * (major ? 14 : 9);
      canvas.drawCircle(
        c,
        r + band,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0),
              Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: (1 - v) * 0.75),
              color.withValues(alpha: 0),
            ],
            stops: [
              ((r - band) / (r + band)).clamp(0.0, 1.0),
              (r / (r + band)).clamp(0.0, 1.0),
              1,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r + band)),
      );
      final ground = Rect.fromCenter(
        center: Offset(c.dx, c.dy + s * 0.2),
        width: r * 2.2,
        height: r * 0.5,
      );
      canvas.drawOval(
        ground,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - v) * 3 + 0.5
          ..color = color.withValues(alpha: (1 - v) * 0.5),
      );
    }

    // 6) TIA SÁNG phóng ra — hình nêm gradient, dài/ngắn xen kẽ, không còn là vạch.
    {
      final n = major ? 18 : 12;
      for (var i = 0; i < n; i++) {
        final ang = i * math.pi * 2 / n + 0.26;
        final long = i.isEven ? 1.0 : 0.6;
        final r0 = s * 0.06 + bt * s * 0.1;
        final r1 = r0 + (s * (major ? 0.42 : 0.3)) * long * Curves.easeOut.transform(bt);
        const wid = 0.05;
        final ray = Path()
          ..moveTo(c.dx + math.cos(ang - wid) * r0, c.dy + math.sin(ang - wid) * r0)
          ..lineTo(c.dx + math.cos(ang) * r1, c.dy + math.sin(ang) * r1)
          ..lineTo(c.dx + math.cos(ang + wid) * r0, c.dy + math.sin(ang + wid) * r0)
          ..close();
        canvas.drawPath(
          ray,
          Paint()
            ..shader = RadialGradient(colors: [
              Color.lerp(color, Colors.white, 0.5)!.withValues(alpha: (1 - bt) * 0.8),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: math.max(r1, 1))),
        );
      }
    }

    // 7) TÀN QUANG bay lên: hạt sáng có đuôi, lắc ngang nhẹ, nhấp nháy lệch pha.
    final emberN = major ? 22 : 12;
    for (var i = 0; i < emberN; i++) {
      final seed = (i * 53) % 100 / 100.0;
      Offset at(double u) => Offset(
            c.dx +
                ((i * 37 % 200) - 100) / 100.0 * s * 0.4 * (0.4 + seed) +
                math.sin(u * 9 + i) * 6,
            c.dy + s * 0.1 - u * s * (major ? 0.7 : 0.5) * (0.6 + seed),
          );
      final a = (1 - bt) * (bt > 0.15 ? 1.0 : bt / 0.15) *
          (0.6 + 0.4 * math.sin(bt * 40 + i));
      _tail(canvas, [for (var k = 0; k < 5; k++) at(math.max(0, bt - k * 0.02))], 1.6,
          color, a * 0.6);
      _glow(canvas, at(bt), (1 - bt) * 1.6 + 0.7, color, a);
    }

    // 7b) Major: cánh hoa ánh sáng rơi xoay chậm — "thiên hoa loạn trụy" chúc mừng phá cảnh.
    if (major && bt > 0.2) {
      final pt = (bt - 0.2) / 0.8;
      final petal = Color.lerp(color, const Color(0xFFFFF3BF), 0.6)!;
      for (var i = 0; i < 20; i++) {
        final seed = (i * 29 % 100) / 100;
        final x = (i + 0.5) / 20 * size.width + math.sin(pt * 6 + i) * 14;
        final y = -10 + (pt * (0.7 + seed * 0.5) + seed * 0.3) * size.height * 0.8;
        final a = math.sin(math.min(pt * 1.4, 1) * math.pi) * 0.75;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(pt * 8 + i);
        final k = s / 260; // cỡ cánh theo màn — màn thật ~400dp, 5px là mất hút
        canvas.scale(k, k * (0.4 + 0.6 * math.cos(pt * 10 + i).abs())); // lật cánh
        final path = Path()
          ..moveTo(0, -5)
          ..quadraticBezierTo(3.4, 0, 0, 5)
          ..quadraticBezierTo(-3.4, 0, 0, -5);
        canvas.drawPath(
          path,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.white.withValues(alpha: a),
              petal.withValues(alpha: a * 0.7),
            ]).createShader(const Rect.fromLTRB(-4, -5, 4, 5)),
        );
        canvas.restore();
      }
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
