import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// Linh khí quấn quanh người + pháp trận dưới chân — dùng chung cho cảnh idle
// (màn Tu Tiên) và hộp thoại lên bậc/đột phá.
//
// Giả 3D bằng cách TÁCH LỚP: mỗi dải là một cung elip nghiêng; đoạn nào đang ở nửa
// SAU (sin(góc) < 0) vẽ ở lớp dưới nhân vật, nửa TRƯỚC vẽ đè lên → dải quấn quanh
// thân thật chứ không chỉ bay sau lưng. Thời gian [time] tính theo "vòng" 4 giây,
// tích luỹ liên tục (không reset) nên không giật khi loop.

const _tilts = [-0.34, 0.27, -0.12, 0.42, -0.5];
const _heights = [-24.0, 8.0, -6.0, 24.0, -40.0];

/// Vẽ các dải linh khí (mỗi màu một dải) — chỉ phần thuộc lớp [front].
/// [intro] 0→1: dải cuộn từ chân lên và nở rộng dần (hiệu ứng lên bậc); idle = 1.
/// [additive]: cộng sáng (BlendMode.plus) — chỉ dùng trên nền tối (hộp thoại).
void paintQiRibbons(
  Canvas canvas,
  Offset c,
  List<Color> colors,
  double time, {
  required bool front,
  double scale = 1,
  double intro = 1,
  bool additive = false,
  double width = 5,
}) {
  final n = colors.length;
  if (n == 0) return;
  final e = Curves.easeOutCubic.transform(intro.clamp(0.0, 1.0));
  if (e <= 0.001) return;
  final blend = additive ? BlendMode.plus : BlendMode.srcOver;
  const samples = 32;
  const span = 2.4; // độ dài dải (rad) ≈ 140°
  for (var i = 0; i < n; i++) {
    final col = colors[i];
    final tilt = _tilts[i % 5];
    final rx = (60 + (i % 3) * 9) * scale * (0.3 + 0.7 * e);
    final ry = (14 + (i % 2) * 6) * scale;
    final dy = lerpDouble(62 * scale, _heights[i % 5] * scale, e)!;
    final dir = i.isEven ? 1.0 : -1.0;
    final head = time * 2 * math.pi * (0.55 + 0.1 * (i % 3)) * dir + i * 2 * math.pi / n;
    final ct = math.cos(tilt), st = math.sin(tilt);

    // mẫu dọc dải: vị trí, độ sâu, bề rộng (thon về đuôi, đoạn trước to hơn)
    final pts = <Offset>[];
    final depth = <double>[];
    final wid = <double>[];
    for (var k = 0; k <= samples; k++) {
      final u = k / samples;
      final a = head - dir * span * u;
      final x = math.cos(a) * rx, y = math.sin(a) * ry;
      pts.add(c + Offset(x * ct - y * st, x * st + y * ct + dy));
      final d = math.sin(a);
      depth.add(d);
      wid.add(width * scale * math.pow(1 - u, 0.65) * (0.7 + 0.3 * d) + 0.4);
    }

    // gom các đoạn liên tiếp cùng lớp → mỗi đoạn một đa giác thon
    var k0 = 0;
    while (k0 < samples) {
      if ((depth[k0] > 0) != front) {
        k0++;
        continue;
      }
      var k1 = k0;
      while (k1 < samples && (depth[k1 + 1] > 0) == front) {
        k1++;
      }
      // nối thêm 1 mẫu để 2 lớp gặp nhau liền mạch ở mép người
      final end = math.min(k1 + 1, samples);
      if (end > k0) {
        _ribbonRun(canvas, pts, wid, k0, end, col, e, blend, pts[0],
            (pts[0] - pts[samples]).distance, scale);
      }
      k0 = end;
    }
    // đầu dải: hạt sáng có quầng
    if ((depth[0] > 0) == front) {
      _bloomDot(canvas, pts[0], 2.2 * scale, col, e, blend);
    }
  }
}

void _ribbonRun(Canvas canvas, List<Offset> pts, List<double> wid, int a, int b,
    Color col, double alpha, BlendMode blend, Offset head, double len, double scale) {
  Path poly(double wk) {
    final left = <Offset>[], right = <Offset>[];
    for (var k = a; k <= b; k++) {
      final prev = pts[math.max(k - 1, 0)], next = pts[math.min(k + 1, pts.length - 1)];
      var t = next - prev;
      final l = t.distance;
      t = l > 0 ? t / l : const Offset(1, 0);
      final nrm = Offset(-t.dy, t.dx) * (wid[k] * wk / 2);
      left.add(pts[k] + nrm);
      right.add(pts[k] - nrm);
    }
    return Path()..addPolygon([...left, ...right.reversed], true);
  }

  // tan dần theo khoảng cách từ đầu dải
  Shader fade(Color c0, double a0) => RadialGradient(
        colors: [c0.withValues(alpha: a0), c0.withValues(alpha: a0 * 0.5), c0.withValues(alpha: 0)],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: head, radius: math.max(len, 1)));

  canvas.drawPath(
    poly(2.6),
    Paint()
      ..blendMode = blend
      ..shader = fade(col, (blend == BlendMode.plus ? 0.45 : 0.32) * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
  );
  canvas.drawPath(poly(1),
      Paint()..blendMode = blend..shader = fade(col, (blend == BlendMode.plus ? 0.55 : 0.8) * alpha));
  canvas.drawPath(
    poly(0.32),
    Paint()
      ..blendMode = blend
      ..shader = fade(Color.lerp(col, Colors.white, blend == BlendMode.plus ? 0.4 : 0.75)!,
          (blend == BlendMode.plus ? 0.6 : 0.95) * alpha),
  );
}

void _bloomDot(Canvas canvas, Offset p, double r, Color col, double a, BlendMode blend) {
  canvas.drawCircle(
    p,
    r * 4,
    Paint()
      ..blendMode = blend
      ..shader = RadialGradient(colors: [
        col.withValues(alpha: 0.5 * a),
        col.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: p, radius: r * 4)),
  );
  canvas.drawCircle(p, r, Paint()..blendMode = blend..color = Colors.white.withValues(alpha: 0.95 * a));
}

/// Pháp trận dưới chân (phối cảnh nằm): vòng kép + bát giác tinh + 8 quẻ bát quái
/// xoay ngược chiều nhau, đĩa sáng tỏa. [intro] 0→1 bung từ tâm ra.
void paintRuneCircle(Canvas canvas, Offset center, double radius, Color color,
    double time, {double intro = 1, bool additive = false}) {
  final e = Curves.easeOutBack.transform(intro.clamp(0.0, 1.0));
  if (e <= 0.001) return;
  final a = intro.clamp(0.0, 1.0);
  final r = radius * e;
  final blend = additive ? BlendMode.plus : BlendMode.srcOver;
  final hot = Color.lerp(color, Colors.white, 0.45)!;
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(1, 0.34);
  canvas.drawCircle(
    Offset.zero,
    r * 1.2,
    Paint()
      ..blendMode = blend
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: 0.4 * a),
        color.withValues(alpha: 0.12 * a),
        color.withValues(alpha: 0),
      ], stops: const [0, 0.7, 1]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.2)),
  );
  // mỗi nét vẽ 2 lần: quầng mờ rộng + nét sắc → ánh "bloom"
  void stroke(void Function(Paint p) draw, double w) {
    draw(Paint()
      ..blendMode = blend
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 3
      ..color = color.withValues(alpha: 0.35 * a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    draw(Paint()
      ..blendMode = blend
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = hot.withValues(alpha: 0.9 * a));
  }

  stroke((p) => canvas.drawCircle(Offset.zero, r, p), 1.8);
  stroke((p) => canvas.drawCircle(Offset.zero, r * 0.84, p), 1.0);
  stroke((p) => canvas.drawCircle(Offset.zero, r * 0.46, p), 1.0);

  // bát giác tinh: 2 hình vuông lệch 45°, xoay thuận
  canvas.save();
  canvas.rotate(time * 2 * math.pi * 0.12);
  for (final off in [0.0, math.pi / 4]) {
    final sq = Path();
    for (var k = 0; k < 4; k++) {
      final ang = off + k * math.pi / 2;
      final q = Offset(math.cos(ang), math.sin(ang)) * (r * 0.82);
      k == 0 ? sq.moveTo(q.dx, q.dy) : sq.lineTo(q.dx, q.dy);
    }
    sq.close();
    stroke((p) => canvas.drawPath(sq, p), 0.9);
  }
  canvas.restore();

  // 8 quẻ + 32 vạch khắc trên vành, xoay ngược
  canvas.save();
  canvas.rotate(-time * 2 * math.pi * 0.08);
  final tick = Paint()
    ..blendMode = blend
    ..strokeWidth = 1
    ..color = hot.withValues(alpha: 0.6 * a);
  for (var k = 0; k < 32; k++) {
    final ang = k * math.pi / 16;
    final u = Offset(math.cos(ang), math.sin(ang));
    canvas.drawLine(u * (r * 0.86), u * (r * (k.isEven ? 0.95 : 0.91)), tick);
  }
  final yao = Paint()
    ..blendMode = blend
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round
    ..color = hot.withValues(alpha: 0.95 * a);
  for (var i = 0; i < 8; i++) {
    final ang = i * math.pi / 4 + math.pi / 8;
    canvas.save();
    canvas.rotate(ang);
    canvas.translate(r * 0.65, 0);
    canvas.rotate(math.pi / 2);
    final bits = 7 - i;
    final s = radius / 70;
    for (var j = 0; j < 3; j++) {
      final y = (j - 1) * 3.2 * s;
      if ((bits >> j) & 1 == 1) {
        canvas.drawLine(Offset(-4.5 * s, y), Offset(4.5 * s, y), yao);
      } else {
        canvas.drawLine(Offset(-4.5 * s, y), Offset(-1.2 * s, y), yao);
        canvas.drawLine(Offset(1.2 * s, y), Offset(4.5 * s, y), yao);
      }
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// Hạt linh khí bốc lên theo đường xoắn ốc quanh thân, có đuôi — tách lớp như dải.
void paintRisingMotes(Canvas canvas, Offset c, Color color, double time,
    {required bool front, double scale = 1, int count = 14, double intro = 1, bool additive = false}) {
  final a0 = intro.clamp(0.0, 1.0);
  if (a0 <= 0.001) return;
  final blend = additive ? BlendMode.plus : BlendMode.srcOver;
  for (var i = 0; i < count; i++) {
    Offset at(double tt) {
      final ph = (tt * 0.45 + i / count) % 1;
      final ang = ph * 2 * math.pi * 1.5 + i * 2.1;
      return c +
          Offset(math.cos(ang) * (48 - ph * 16) * scale,
              (56 - ph * 130) * scale);
    }

    final ph = (time * 0.45 + i / count) % 1;
    final ang = ph * 2 * math.pi * 1.5 + i * 2.1;
    if ((math.sin(ang) > 0) != front) continue;
    final a = math.sin(ph * math.pi) * a0;
    final trail = Paint()
      ..blendMode = blend
      ..strokeCap = StrokeCap.round;
    var prev = at(time);
    for (var k = 1; k <= 5; k++) {
      final q = at(time - k * 0.02);
      if ((q - prev).distance > 20 * scale) break; // vừa quay vòng pha → bỏ đuôi
      final f = 1 - k / 6;
      trail
        ..strokeWidth = 2.2 * f * scale + 0.3
        ..color = color.withValues(alpha: 0.6 * a * f);
      canvas.drawLine(prev, q, trail);
      prev = q;
    }
    _bloomDot(canvas, at(time), 1.3 * scale, color, a, blend);
  }
}

/// Lớp linh khí cho hộp thoại lên bậc: pháp trận + dải quấn + hạt bốc (nền tối,
/// cộng sáng). Bọc quanh ảnh nhân vật 150×145: dùng làm `painter` (lớp sau) và
/// `foregroundPainter` (lớp trước) của cùng một CustomPaint.
class QiVortexPainter extends CustomPainter {
  final double time; // vòng 4s, tích luỹ
  final double intro; // 0→1 lúc mở màn
  final Color color;
  final bool front;
  final bool major;
  QiVortexPainter(this.time, this.intro, this.color,
      {required this.front, this.major = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.56);
    final s = major ? 0.95 : 1.1; // major đã được phóng 1.6× cả khối (_hero)
    if (!front) {
      paintRuneCircle(canvas, Offset(c.dx, size.height - 10), 74 * s, color, time,
          intro: intro, additive: true);
    }
    final cols = [
      color,
      Color.lerp(color, Colors.white, 0.45)!,
      Color.lerp(color, const Color(0xFFFFD25A), 0.55)!,
      if (major) Color.lerp(color, const Color(0xFF74C0FC), 0.4)!,
      if (major) Color.lerp(color, Colors.white, 0.2)!,
    ];
    paintQiRibbons(canvas, c, cols, time,
        front: front, scale: s, intro: intro, additive: true, width: 6);
    paintRisingMotes(canvas, c, Color.lerp(color, Colors.white, 0.3)!, time,
        front: front, scale: s, intro: intro, additive: true, count: major ? 18 : 12);
  }

  @override
  bool shouldRepaint(QiVortexPainter old) =>
      old.time != time || old.intro != intro || old.color != color;
}

/// Phông nền ĐIỆN ẢNH cho đột phá đại cảnh giới — phủ kín màn (che UI app phía sau):
/// trời kiếp đen xanh + viền tối; từ lúc lộ kết quả [resultStart] chuyển dần sang
/// "thiên quang": quầng màu phẩm tỏa từ nhân vật, tia sáng mềm xoay chậm, sao lấp lánh.
/// [t] = timeline dialog 0..1, [time] = đồng hồ liên tục (vòng 4s) cho chuyển động sau khi
/// timeline dừng. [ok]=false → không có thiên quang, chỉ ám đỏ nhẹ.
class MajorBackdropPainter extends CustomPainter {
  final double t;
  final double time;
  final Color color;
  final bool ok;
  final double resultStart;
  MajorBackdropPainter(this.t, this.time, this.color,
      {required this.ok, required this.resultStart});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const fadeIn = 1.0; // đậm ngay: Tâm Ma → kiếp nối liền, không được lộ UI app giữa hai pha
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF03050B).withValues(alpha: 0.96 * fadeIn),
            const Color(0xFF0A1020).withValues(alpha: 0.96 * fadeIn),
            const Color(0xFF05070E).withValues(alpha: 0.97 * fadeIn),
          ],
        ).createShader(rect),
    );
    final c = Offset(size.width / 2, size.height * 0.42);
    final s = size.shortestSide;
    final e = Curves.easeOut.transform(((t - resultStart) / 0.1).clamp(0.0, 1.0));
    if (e > 0) {
      final glow = ok ? Color.lerp(color, Colors.white, 0.25)! : const Color(0xFFC92A2A);
      canvas.drawCircle(
        c,
        s * 1.1,
        Paint()
          ..shader = RadialGradient(colors: [
            glow.withValues(alpha: (ok ? 0.55 : 0.3) * e),
            glow.withValues(alpha: 0.12 * e),
            glow.withValues(alpha: 0),
          ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: s * 1.1)),
      );
      if (ok) {
        // tia thiên quang: nêm mềm dài quá mép màn, 2 lớp xoay ngược
        for (final (n, spin, a0, w) in [(12, 0.03, 0.16, 0.07), (18, -0.02, 0.09, 0.04)]) {
          for (var i = 0; i < n; i++) {
            final ang = i * 2 * math.pi / n + time * 2 * math.pi * spin;
            final r1 = s * (0.9 + 0.25 * math.sin(i * 1.7 + time * 3));
            final ray = Path()
              ..moveTo(c.dx, c.dy)
              ..lineTo(c.dx + math.cos(ang - w) * r1, c.dy + math.sin(ang - w) * r1)
              ..lineTo(c.dx + math.cos(ang + w) * r1, c.dy + math.sin(ang + w) * r1)
              ..close();
            canvas.drawPath(
              ray,
              Paint()
                ..blendMode = BlendMode.plus
                ..shader = RadialGradient(colors: [
                  glow.withValues(alpha: a0 * e),
                  glow.withValues(alpha: 0),
                ]).createShader(Rect.fromCircle(center: c, radius: r1)),
            );
          }
        }
        // sao trời lấp lánh (vị trí tất định)
        final star = Paint()..blendMode = BlendMode.plus;
        for (var i = 0; i < 46; i++) {
          final p = Offset((i * 97 % 101) / 101 * size.width, (i * 61 % 89) / 89 * size.height * 0.8);
          final tw = 0.5 + 0.5 * math.sin(time * 2 * math.pi * (0.6 + (i % 5) * 0.2) + i);
          star.color = Colors.white.withValues(alpha: (0.15 + 0.55 * tw) * e);
          canvas.drawCircle(p, 0.6 + tw * (i % 3 == 0 ? 1.4 : 0.7), star);
        }
      }
    }
    // viền tối (vignette) — dồn mắt vào giữa
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.15),
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55 * fadeIn)],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(MajorBackdropPainter old) =>
      old.t != t || old.time != time || old.color != color || old.ok != ok;
}
