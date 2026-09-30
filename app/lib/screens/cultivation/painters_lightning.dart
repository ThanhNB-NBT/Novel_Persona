import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'painters_fx.dart' show paintShaderLowRes;

// Lôi kiếp vẽ THỦ TỤC (thay WebP động + nét gãy khúc cũ). Mô phỏng theo sét thật:
//   1. tia dẫn (stepped leader): kênh mờ phân nhánh bò từ mây xuống trong ~150ms;
//   2. cú đánh chính (return stroke): kênh sáng rực + lóe cả trời, rồi 2 lần chớp lại
//      trên CÙNG kênh (sét thật nhấp nháy vì nhiều cú đánh nối nhau);
//   3. tàn sáng: kênh nguội dần sang lam tím, hồ quang bò quanh điểm chạm, tia lửa bắn.
// Giữa các đạo: chớp ẩn trong mây (sheet lightning) để trời kiếp không lúc nào chết.
// Mọi thứ tất định theo seed → không nháy lung tung giữa các khung, chỉ hồ quang đổi
// hình theo thời gian cho cảm giác điện đang "bò".

/// Mốc chạm (theo timeline dialog đại cảnh giới 0..1) — khớp rung màn `_strikeShake`.
const tribulationHits = [0.38, 0.56, 0.74];

class LightningStormPainter extends CustomPainter {
  final double v; // timeline dialog 0..1
  final double from; // bắt đầu hiện trời kiếp
  final double to; // tắt hẳn (lúc lộ kết quả)
  final Offset? target; // điểm chạm; null = giữa màn hơi cao
  final ui.FragmentShader? cloud; // shaders/storm.frag — null = mây canvas cũ
  final double seconds; // đồng hồ cho mây trôi (shader)
  LightningStormPainter(this.v,
      {required this.from, required this.to, this.target, this.cloud, this.seconds = 0});

  static const _core = Colors.white;
  static const _mid = Color(0xFFBFD9FF);
  static const _glow = Color(0xFF6E8BFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (v < from || v >= to) return;
    final s = size.shortestSide;
    final hit = target ?? Offset(size.width / 2, size.height * 0.46);
    final fadeIn = ((v - from) / 0.05).clamp(0.0, 1.0);
    final fadeOut = ((to - v) / 0.03).clamp(0.0, 1.0);
    final env = fadeIn * fadeOut;

    // cường độ lóe tổng (cho trời + mây)
    var sky = 0.0;
    var skyX = size.width / 2;
    for (final (i, h) in tribulationHits.indexed) {
      final a = _intensity(v - h) * (0.75 + i * 0.12);
      if (a > sky) (sky, skyX) = (a, _rootX(i, size, s));
    }
    // chớp ẩn trong mây giữa các đạo
    var sheet = 0.0;
    Offset sheetAt = Offset.zero;
    for (final (i, h) in [0.30, 0.47, 0.51, 0.66, 0.80].indexed) {
      final d = v - h;
      if (d < 0 || d > 0.03) continue;
      final a = math.exp(-d / 0.006) * (0.55 + 0.45 * math.sin(d * 900).abs());
      if (a > sheet) {
        sheet = a;
        sheetAt = Offset(size.width * (0.18 + (i * 0.37) % 0.7), s * (0.06 + (i % 3) * 0.05));
      }
    }

    _drawSky(canvas, size, s, env, sky, sheet, sheetAt, skyX);

    for (final (i, h) in tribulationHits.indexed) {
      final d = v - h;
      if (d < -0.022 || d > 0.12) continue;
      final rnd = math.Random(7919 * (i + 1));
      final x0 = _rootX(i, size, s);
      rnd.nextDouble(); // giữ nguyên chuỗi ngẫu nhiên như bản 2D (x0 từng rút 1 số)
      final (main, ks) = _bolt3d(Offset(x0, -s * 0.05), hit, rnd, s);
      final branches = _branches(main, rnd, s, depth: 1, count: 4 + i, ks: ks);
      final width = 2.2 + i * 0.7;
      if (d < 0) {
        // tia dẫn: bò xuống, mờ, đầu tia nhấp nháy
        final g = 1 + d / 0.022; // 0 → 1
        final n = (main.length * Curves.easeIn.transform(g)).ceil().clamp(2, main.length);
        final a = 0.28 + 0.2 * math.sin(v * 3000).abs();
        _strokeDepth(canvas, main.sublist(0, n), ks, width * 0.45, a * env);
        for (final b in branches) {
          final k = b.$1;
          if (k >= n) continue;
          final bn = ((n - k) * 1.3).ceil().clamp(2, b.$2.length);
          _stroke(canvas, b.$2.sublist(0, bn), width * 0.25, a * 0.6 * env);
        }
        _dot(canvas, main[n - 1], s * 0.012, 0.8 * env);
        continue;
      }
      final inten = _intensity(d) * env;
      if (inten < 0.01) continue;
      // kênh nguội dần: trắng → lam tím
      _strokeDepth(canvas, main, ks, width, inten, cool: (d / 0.09).clamp(0.0, 1.0));
      if (i == 2 && d < 0.05) {
        // đạo cuối: kênh đôi song song lệch nhẹ — nặng tay hơn
        final twin = [for (final (j, p) in main.indexed) p + Offset(s * 0.012 * ks[j], 0)];
        _strokeDepth(canvas, twin, ks, width * 0.5, inten * 0.6);
      }
      for (final b in branches) {
        _stroke(canvas, b.$2, width * 0.42, inten * 0.7, cool: (d / 0.04).clamp(0.0, 1.0));
      }
      _impact(canvas, hit, s, d, inten, i);
    }
  }

  /// Độ sáng theo thời gian kể từ cú đánh (đơn vị timeline; 0.01 ≈ 80ms với dialog 8s):
  /// 3 cú trong ~250ms + tàn sáng ~0.5s — đủ dài để mắt (và máy 30fps) bắt được.
  /// 3 cú đánh trên cùng kênh + tàn sáng dài.
  static double _intensity(double d) {
    if (d < 0) return 0;
    var a = 0.0;
    for (final (k, (at, amp)) in [(0.0, 1.0), (0.012, 0.9), (0.027, 0.75)].indexed) {
      if (d >= at) a = math.max(a, amp * math.exp(-(d - at) / (0.009 + k * 0.002)));
    }
    return math.min(1.0, a + 0.35 * math.exp(-d / 0.05));
  }

  /// Hoành độ gốc sét trên màn (tất định theo seed như lúc sinh kênh).
  static double _rootX(int i, Size size, double s) {
    final rnd = math.Random(7919 * (i + 1));
    return size.width * [0.30, 0.72, 0.5][i] + (rnd.nextDouble() - 0.5) * s * 0.1;
  }

  void _drawSky(Canvas canvas, Size size, double s, double env, double flash,
      double sheet, Offset sheetAt, double flashX) {
    final top = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    final sh = cloud;
    if (sh != null) {
      paintShaderLowRes(canvas, Rect.fromLTWH(0, 0, size.width, size.height * 0.4), sh, 2, (k) {
        sh
          ..setFloat(0, size.width / k)
          ..setFloat(1, size.height / k)
          ..setFloat(2, seconds)
          ..setFloat(3, env)
          ..setFloat(4, flash)
          ..setFloat(5, flashX / k)
          ..setFloat(6, sheet)
          ..setFloat(7, sheetAt.dx / k)
          ..setFloat(8, sheetAt.dy / k);
      });
    }
    // mây kiếp: các khối tròn chồng, trôi chậm; sáng từ bên trong khi lóe
    final lit = math.max(flash, sheet * 0.6);
    final base = Color.lerp(const Color(0xFF0B1020), const Color(0xFF3A4A7A), lit)!;
    for (var i = 0; i < (sh == null ? 16 : 0); i++) {
      final drift = math.sin(v * 9 + i * 1.3) * s * 0.03;
      final x = (i + 0.5) * size.width / 16 * 1.1 - size.width * 0.05 + drift;
      final y = s * (0.02 + (i % 4) * 0.04) + math.cos(v * 7 + i) * s * 0.01;
      final r = s * (0.13 + (i % 3) * 0.04);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            base.withValues(alpha: 0.95 * env),
            base.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
      );
    }
    if (sheet > 0.01) {
      canvas.drawCircle(
        sheetAt,
        s * 0.3,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [
            _mid.withValues(alpha: 0.45 * sheet * env),
            _glow.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: sheetAt, radius: s * 0.3)),
      );
      // nhánh sét ngang ẩn trong mây
      final r = math.Random((sheetAt.dx * 13).toInt());
      final p = _bolt(sheetAt - Offset(s * 0.18, 0), sheetAt + Offset(s * 0.2, s * 0.03), r,
          segments: 16, rough: s * 0.03);
      _stroke(canvas, p, 1.2, 0.55 * sheet * env);
    }
    if (flash > 0.01) {
      // lóe cả trời: trắng lam phủ, đậm ở trên
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // có shader: mây đã tự sáng → lớp phủ này chỉ còn là chớp nhẹ toàn trời
              _mid.withValues(alpha: (cloud == null ? 0.5 : 0.22) * flash * env),
              _glow.withValues(alpha: 0.18 * flash * env),
              _glow.withValues(alpha: 0.05 * flash * env),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    // viền trời tối đè lên mép trên
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.5 * env * (1 - flash * 0.7)),
            Colors.transparent,
          ],
        ).createShader(top),
    );
  }

  void _impact(Canvas canvas, Offset p, double s, double d, double inten, int i) {
    // nổ sáng tại điểm chạm
    final r = s * (0.18 + i * 0.04) * (0.6 + inten * 0.6);
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.9 * inten),
          _mid.withValues(alpha: 0.5 * inten),
          _glow.withValues(alpha: 0),
        ], stops: const [0, 0.25, 1]).createShader(Rect.fromCircle(center: p, radius: r)),
    );
    // vòng xung kích dẹt dưới chân
    final u = (d / 0.07).clamp(0.0, 1.0);
    if (u < 1) {
      final ground = p + Offset(0, s * 0.2);
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: s * (0.1 + u * 0.9), height: s * (0.03 + u * 0.22)),
        Paint()
          ..blendMode = BlendMode.plus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - u) + 0.5
          ..color = _mid.withValues(alpha: 0.7 * (1 - u)),
      );
    }
    // tia lửa điện bắn ra theo đường đạn đạo
    final rnd = math.Random(31 * (i + 3));
    final sparkT = (d / 0.07).clamp(0.0, 1.0);
    if (sparkT < 1) {
      final spark = Paint()
        ..blendMode = BlendMode.plus
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 16; k++) {
        final ang = -math.pi * (0.1 + rnd.nextDouble() * 0.8);
        final sp = s * (0.25 + rnd.nextDouble() * 0.35);
        Offset at(double u) => p +
            Offset(math.cos(ang) * sp * u, math.sin(ang) * sp * u + s * 0.5 * u * u);
        final a = (1 - sparkT);
        spark
          ..strokeWidth = 1.6 * a + 0.3
          ..color = Color.lerp(_core, _mid, sparkT)!.withValues(alpha: a);
        canvas.drawLine(at(math.max(0, sparkT - 0.08)), at(sparkT), spark);
      }
    }
    // hồ quang bò quanh người: đổi hình mỗi ~40ms
    final crawl = (d / 0.1).clamp(0.0, 1.0);
    if (crawl < 1) {
      final r2 = math.Random((v * 200).floor() * 17 + i);
      for (var k = 0; k < 3; k++) {
        final a0 = r2.nextDouble() * math.pi * 2;
        final a1 = a0 + 0.8 + r2.nextDouble() * 1.2;
        final rr = s * (0.1 + r2.nextDouble() * 0.12);
        final pa = p + Offset(math.cos(a0) * rr, math.sin(a0) * rr * 1.4 + s * 0.05);
        final pb = p + Offset(math.cos(a1) * rr, math.sin(a1) * rr * 1.4 + s * 0.05);
        _stroke(canvas, _bolt(pa, pb, r2, segments: 10, rough: s * 0.02), 0.9,
            (1 - crawl) * 0.9);
      }
    }
  }

  /// Kênh sét: đi bộ ngẫu nhiên ngang có kéo về hai đầu + gãy góc nhỏ từng đoạn.
  static List<Offset> _bolt(Offset a, Offset b, math.Random r,
      {required int segments, required double rough}) {
    final dir = b - a;
    final len = dir.distance;
    final u = dir / len;
    final nrm = Offset(-u.dy, u.dx);
    final pts = <Offset>[a];
    var lateral = 0.0;
    for (var k = 1; k < segments; k++) {
      final t = k / segments;
      lateral += (r.nextDouble() - 0.5) * rough;
      lateral *= 0.8; // kéo về kênh chính, không trôi quá xa
      // hai đầu cố định, thân giữa tự do (sin cũ làm đoạn gần gần như thẳng)
      final pull = math.min(1.0, math.min(t, 1 - t) * 7);
      final along = t + (r.nextDouble() - 0.5) * 0.6 / segments;
      pts.add(a + u * (len * along) + nrm * (lateral * pull * 2.2));
    }
    pts.add(b);
    return pts;
  }

  /// Kênh sét 3D: đi bộ ngẫu nhiên trong không gian (x, z), gốc nằm SÂU trong mây
  /// (z = 2.2) và chạm đất ở z = 0, rồi chiếu phối cảnh về điểm tụ phía trên màn:
  /// đoạn xa co nhỏ + gãy khúc hẹp lại, đoạn gần to và vặn mạnh → sét lao VỀ phía
  /// người xem chứ không chỉ rơi phẳng. Trả kèm hệ số phối cảnh k (1 = gần) mỗi điểm.
  static (List<Offset>, List<double>) _bolt3d(Offset top, Offset hit, math.Random r, double s) {
    const z0 = 2.2, n = 28;
    final vp = Offset(top.dx * 0.6 + hit.dx * 0.4, -s * 0.35); // điểm tụ trên cao
    final w0 = vp + (top - vp) * (1 + z0); // gốc thế giới chiếu ra đúng [top]
    final pts = <Offset>[];
    final ks = <double>[];
    var lx = 0.0, lz = 0.0, zPrev = z0;
    for (var k = 0; k <= n; k++) {
      // phép chiếu nén đoạn xa → rải điểm dày dần về đầu gần cho khúc gãy đều trên màn
      final t = math.pow(k / n, 0.6).toDouble();
      // hai đầu cố định, thân giữa tự do (sin cũ làm đoạn gần gần như thẳng)
      final pull = math.min(1.0, math.min(t, 1 - t) * 7);
      if (k > 0 && k < n) {
        lx = (lx + (r.nextDouble() - 0.5) * s * 0.16) * 0.8;
        lz = (lz + (r.nextDouble() - 0.5) * 0.5) * 0.8;
      }
      // z chỉ được GIẢM: z lùi lại làm phép chiếu kéo điểm ngược → gãy thành tam giác
      final z = math.min(zPrev, math.max(0.0, z0 * math.pow(1 - t, 1.6) + lz * pull));
      zPrev = z;
      final w = Offset.lerp(w0, hit, t)! + Offset(lx * pull * 2.2, 0);
      final kk = 1 / (1 + z);
      pts.add(vp + (w - vp) * kk);
      ks.add(kk);
    }
    return (pts, ks);
  }

  /// Vẽ kênh theo từng khúc, bề dày nhân hệ số phối cảnh → mảnh ở xa, dày khi tới gần.
  static void _strokeDepth(Canvas canvas, List<Offset> pts, List<double> ks, double w, double a,
      {double cool = 0}) {
    const chunk = 5;
    for (var i = 0; i < pts.length - 1; i += chunk) {
      final j = math.min(i + chunk, pts.length - 1);
      final k = (ks[i] + ks[j]) / 2;
      _stroke(canvas, pts.sublist(i, j + 1), w * (0.3 + k * 1.1), a * (0.55 + 0.45 * k),
          cool: cool);
    }
  }

  /// Nhánh phụ: tách từ kênh chính, lệch góc 20–55°, ngắn dần; nhánh có thể tách tiếp.
  static List<(int, List<Offset>)> _branches(List<Offset> main, math.Random r, double s,
      {required int depth, required int count, List<double>? ks}) {
    final out = <(int, List<Offset>)>[];
    for (var j = 0; j < count; j++) {
      final k = 3 + r.nextInt(math.max(1, main.length * 2 ~/ 3));
      if (k >= main.length - 2) continue;
      final p = main[k];
      final d = main[k + 1] - main[k - 1];
      final base = math.atan2(d.dy, d.dx);
      final ang = base + (r.nextBool() ? 1 : -1) * (0.35 + r.nextDouble() * 0.6);
      final len = s * (0.12 + r.nextDouble() * 0.2) / depth * (ks == null ? 1 : 0.4 + ks[k]);
      final end = p + Offset(math.cos(ang), math.sin(ang)) * len;
      final pts = _bolt(p, end, r, segments: 10, rough: s * 0.03);
      out.add((k, pts));
      if (depth == 1 && r.nextDouble() < 0.5) {
        for (final sub in _branches(pts, r, s, depth: 2, count: 1)) {
          out.add((k + sub.$1, sub.$2));
        }
      }
    }
    return out;
  }

  /// 3 lớp: quầng rộng mờ (blur) → thân lam sáng → lõi trắng. Cộng sáng.
  static void _stroke(Canvas canvas, List<Offset> pts, double w, double a, {double cool = 0}) {
    if (pts.length < 2 || a <= 0.005) return;
    final path = Path()..addPolygon(pts, false);
    final core = Color.lerp(_core, const Color(0xFFD0C4FF), cool)!;
    final mid = Color.lerp(_mid, const Color(0xFF9C8CFF), cool)!;
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 7
        ..color = _glow.withValues(alpha: 0.28 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 2.2
        ..color = mid.withValues(alpha: 0.75 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w
        ..color = core.withValues(alpha: a),
    );
  }

  static void _dot(Canvas canvas, Offset p, double r, double a) {
    canvas.drawCircle(
      p,
      r * 3,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(colors: [
          _mid.withValues(alpha: a),
          _glow.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: p, radius: r * 3)),
    );
  }

  @override
  bool shouldRepaint(LightningStormPainter old) => old.v != v;
}
