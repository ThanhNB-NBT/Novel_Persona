import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Painters cảnh Tu Tiên (nền trời + aura trước người) và bảng màu/quỹ đạo
// dùng chung — tách khỏi cultivation.dart.

/// Kiểu hiệu ứng quanh người theo CÔNG PHÁP đang tu (mỗi công pháp một "hệ").
enum Aura { qi, ice, wind, earth, sword, gold, star, fire, leaf }

/// hệ ngũ hành → (kiểu hiệu ứng, màu hệ) — nguồn màu CHÍNH của trận pháp/aura.
const elemAura = <String, (Aura, Color)>{
  'hoa': (Aura.fire, Color(0xFFFF7043)),
  'thuy': (Aura.ice, Color(0xFF74C0FC)),
  'moc': (Aura.leaf, Color(0xFF69DB7C)),
  'kim': (Aura.gold, Color(0xFFFFC94D)),
  'tho': (Aura.earth, Color(0xFFB08968)),
  'all': (Aura.star, Color(0xFFB197FC)),
};

/// Cơ chế màu trận pháp/aura, ưu tiên từ trên xuống:
/// 1. code công pháp có kiểu RIÊNG (kiếm quang, tinh tú...) → dùng override;
/// 2. hệ trong effect của công pháp (server) → tra [elemAura];
/// 3. hệ LINH CĂN người chơi ([element]) → tra [elemAura] — công pháp nhập
///    môn không gắn hệ (dan_khi/tho_nap) vẫn ăn màu theo người tu;
/// 4. còn lại (qi, null) → dùng màu cảnh giới.
(Aura, Color?) auraFor(String? code, String? cpElem, String? element) {
  final override = switch (code) {
    'cp_huyen_bang' => (Aura.ice, const Color(0xFF74C0FC)),
    'cp_ngu_phong' => (Aura.wind, const Color(0xFF63E6BE)),
    'cp_huyen_thien' => (Aura.qi, const Color(0xFF748FFC)),
    'cp_dia_sat' => (Aura.earth, const Color(0xFFB08968)),
    'cp_luyen_the' => (Aura.gold, const Color(0xFFFFA94D)),
    'cp_cuu_chuyen' => (Aura.gold, const Color(0xFFFFC94D)),
    'cp_thien_cang' => (Aura.sword, const Color(0xFFCED4DA)),
    'cp_liet_hoa' => (Aura.fire, const Color(0xFFFF7043)),
    'cp_xich_diem' => (Aura.fire, const Color(0xFFFF5722)),
    'cp_thanh_moc' => (Aura.leaf, const Color(0xFF69DB7C)),
    'cp_dai_dien' => (Aura.star, const Color(0xFFB197FC)),
    'cp_hon_don' => (Aura.star, const Color(0xFF9775FA)),
    'cp_thai_co' => (Aura.star, const Color(0xFFFFE066)),
    _ => null,
  };
  if (override != null) return override;
  final byElem = elemAura[cpElem] ?? elemAura[element];
  return byElem ?? (Aura.qi, null);
}

/// Nền cảnh tu luyện — vẽ TRƯỚC bóng người (background painter):
/// sao (realm 5+) → KIẾM LUÂN NGŨ SẮC sau đầu → bóng chân → quầng thở →
/// sương trôi → đom đóm linh khí.
/// Hình học khớp docs/tu-tien.md §3: canvas 150×145, đầu nhân vật ≈ (75, 37).
class SkyPainter extends CustomPainter {
  final double t; // 0..1
  final double elementTime; // thời gian tích luỹ, không reset theo vòng idle 4s
  final Color moon; // màu cảnh giới
  final Color aura; // màu hệ công pháp (quầng thở)
  final int realm; // 1..9 — kiếm luân nhích to, sao từ Hóa Thần
  final String?
  halo; // kiểu vòng từ pháp bảo: nguyet/tinh/loi/kim — null = vòng trơn
  final ui.Image? weaponImg; // vũ khí đang đeo — nửa vòng SAU vẽ ở lớp nền này
  final ui.Image? phapbaoImg; // pháp bảo đang đeo — như trên, lệch pha nửa vòng
  final ui.Image? swordWheelImg; // kiếm luân minh họa sau đầu
  final int tienTier; // bậc tiên (0..6) → hào quang vàng sau đầu; -1 = không vẽ
  final List<String> elements; // bộ hệ linh căn → sương linh khí ngũ sắc bay quanh
  final ui.Image? haloImg; // trận pháp đang đội — vòng lớn xoay sau lưng (nền)
  SkyPainter(
    this.t,
    this.moon,
    this.aura,
    this.realm, {
    this.halo,
    this.weaponImg,
    this.phapbaoImg,
    this.swordWheelImg,
    this.tienTier = -1,
    this.elements = const [],
    this.haloImg,
    this.elementTime = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // trận pháp hào quang đội sau lưng — lớp SÂU nhất, vòng to gần kín khung, xoay chậm
    // + thở nhẹ; nằm sau cả nhân vật nên chỉ ló vành quanh người.
    if (haloImg != null) {
      final side = size.width * (0.98 + 0.03 * math.sin(t * 2 * math.pi));
      final hc = Offset(c.dx, c.dy + 2);
      canvas.save();
      canvas.translate(hc.dx, hc.dy);
      canvas.rotate(t * 2 * math.pi * 0.08); // xoay rất chậm
      canvas.drawImageRect(
        haloImg!,
        Rect.fromLTWH(0, 0, haloImg!.width.toDouble(), haloImg!.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(
              alpha: 0.85 + 0.15 * math.sin(t * 2 * math.pi)),
      );
      canvas.restore();
    }
    // sao trời từ Hóa Thần (realm 5+): vị trí tất định, nhấp nháy lệch pha
    if (realm >= 5) {
      final star = Paint();
      for (var i = 0; i < (realm - 3) * 2; i++) {
        final x = (i * 53 + 17) % 140 + 5.0;
        final y = (i * 37 + 11) % 52 + 6.0;
        final tw = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 5));
        star.color = Colors.white.withValues(alpha: 0.15 + 0.35 * tw);
        canvas.drawCircle(Offset(x, y), 1.0 + tw * 0.6, star);
      }
    }

    // ---- kiếm luân ngũ sắc: quay + BÁM nhịp lơ lửng của nhân vật cho dính lưng ----
    // dùng CÙNG công thức trôi của thân người (child) để vòng dập dềnh đồng bộ,
    // bỏ hằng số +10 để giữ nguyên vị trí neo gốc, chỉ theo phần chuyển động.
    final ph = t * 2 * math.pi;
    final chBob = math.sin(ph);
    final hc = Offset(
      c.dx + chBob * 1.5 + math.sin(ph * 2 + 0.9) * 0.7,
      c.dy - 29 + chBob * 4,
    );
    _drawSwordWheel(canvas, hc, 30.0 + realm * 0.65);
    // hào quang cõi tiên hậu Phi Thăng — nằm ở lớp nền nên SAU nhân vật
    if (tienTier >= 0) _drawTienCorona(canvas, hc, tienTier);
    // sương linh khí NGŨ SẮC theo bộ hệ linh căn — mỗi hệ một đốm màu bay quanh người
    _drawElementWisps(canvas, Offset(c.dx, c.dy + 6));

    // Bỏ trận pháp: chỉ còn bóng chân để nhân vật neo vào nền tranh.
    final fc = Offset(c.dx, size.height - 13);
    final bob = math.sin(t * 2 * math.pi);
    // bóng hứng dưới chân, NGƯỢC pha với độ nhấp nhô của người (bob>0 = người
    // hạ thấp → bóng to + đậm; bay lên → nhỏ + nhạt) — bán cảm giác lơ lửng
    canvas.drawOval(
      Rect.fromCenter(center: fc, width: 30 + bob * 5, height: 7 + bob * 1.4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22 + bob * 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // quầng linh khí thở (theo màu công pháp) — nằm SAU bóng người
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    for (final (r0, a) in [(38.0, 0.20), (54.0, 0.09)]) {
      final r = r0 + breathe * 6;
      canvas.drawCircle(
        Offset(c.dx, c.dy + 14),
        r,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  aura.withValues(alpha: a),
                  aura.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(center: Offset(c.dx, c.dy + 14), radius: r),
              ),
      );
    }

    // 3 dải sương trôi ngang, mỗi dải tốc độ/độ cao khác nhau, lượn theo sin
    final mist = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (final (i, (y, w, speed)) in [
      (0, (0.62, 66.0, 1.0)),
      (1, (0.76, 88.0, 0.6)),
      (2, (0.50, 52.0, 1.4)),
    ]) {
      // x chạy vòng: -w → size.width+w rồi lặp
      final x = (((t * speed + i / 3) % 1) * (size.width + 2 * w)) - w;
      mist.color = Colors.white.withValues(alpha: 0.05 + 0.02 * i);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            x,
            size.height * y + math.sin(t * 2 * math.pi + i) * 3,
          ),
          width: w,
          height: 10,
        ),
        mist,
      );
    }

    // đom đóm linh khí bay lên — lệch pha nhau, mờ dần khi lên cao (loop khớp t)
    final mote = Paint();
    for (var i = 0; i < 10; i++) {
      final ph = (t + i / 10) % 1;
      final x =
          (i * 41 + 13) % 140 + 5 + math.sin((t * 2 + i) * 2 * math.pi) * 3;
      final tw =
          0.5 + 0.5 * math.sin((t * 3 + i / 3) * 2 * math.pi); // nhấp nháy
      mote.color = aura.withValues(alpha: (0.20 + 0.25 * tw) * (1 - ph));
      canvas.drawCircle(
        Offset(x, size.height - 8 - ph * (size.height - 30)),
        1.0 + (i % 3) * 0.35,
        mote,
      );
    }

    // đồ bay quanh đang ở nửa vòng SAU — vẽ ở lớp nền để thân người che thật
    if (weaponImg != null) {
      drawOrbiter(canvas, t, c, aura, weaponImg!, frontLayer: false);
    }
    if (phapbaoImg != null) {
      drawOrbiter(
        canvas,
        t,
        c,
        moon,
        phapbaoImg!,
        frontLayer: false,
        scale: 0.82,
        orbit: phapbaoOrbit,
      );
    }
  }

  void _drawSwordWheel(Canvas canvas, Offset c, double radius) {
    final img = swordWheelImg;
    if (img == null) return;
    final side = radius * 2.35;
    final speed = halo == 'loi' ? 1.5 : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi * speed);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: side, height: side),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  /// Hạt linh khí trôi quanh đan điền theo các tần số vô tỉ. Thời gian tích luỹ không
  /// reset theo vòng idle nên dòng hạt không lặp lại thành một quỹ đạo đóng hay bị giật.
  void _drawElementWisps(Canvas canvas, Offset c) {
    if (elements.isEmpty) return;
    final n = elements.length;
    final golden = (1 + math.sqrt(5)) / 2;
    for (var i = 0; i < n; i++) {
      final element = elements[i];
      final col = elemAura[element]?.$2 ?? aura;
      final lane = i / n;
      final phase = lane * math.pi * 2;
      final direction = i.isOdd ? -1.0 : 1.0;

      Offset orbitAt(double time) {
        final wave = time * math.pi * 2;
        final a = wave * direction / golden + phase;
        final rx = 29 + 5 * math.sin(wave * golden + phase);
        final ry = 16 + 4 * math.cos(wave * math.sqrt(2) - phase);
        final side = 5 * math.sin(wave * math.sqrt(3) + phase * 0.7);
        final lift = 4 * math.cos(wave / golden - phase * 1.3);
        return Offset(
          c.dx + math.cos(a) * rx + side,
          c.dy - 4 + math.sin(a) * ry + lift,
        );
      }

      // Mỗi hệ là một dòng 6 hạt, đuôi thưa và mờ dần như linh khí tản ra.
      for (var particle = 5; particle >= 0; particle--) {
        final age = particle / 6;
        final p = orbitAt(elementTime - particle * 0.115);
        final pulse = 0.5 + 0.5 * math.sin(elementTime * 7 + particle + phase);
        final radius = 0.75 + (1 - age) * (1.35 + pulse * 0.45);
        final alpha = (1 - age) * (0.22 + pulse * 0.22);
        canvas.drawCircle(
          p,
          radius * 2.6,
          Paint()
            ..color = col.withValues(alpha: alpha * 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
        );
        canvas.drawCircle(
          p,
          radius,
          Paint()..color = col.withValues(alpha: alpha),
        );
        if (particle == 0) {
          canvas.drawCircle(
            p,
            radius * 0.42,
            Paint()..color = Colors.white.withValues(alpha: 0.72),
          );
        }
      }
    }
  }

  /// Hào quang cõi tiên: đĩa vàng ấm + tia sáng xoay quanh đầu, càng lên bậc (tier)
  /// càng nhiều tia + rực hơn. Vẽ ở lớp nền → nằm SAU nhân vật.
  void _drawTienCorona(Canvas canvas, Offset hc, int tier) {
    const gold = Color(0xFFFFD25A);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final r = 22.0 + tier * 1.5;
    canvas.drawCircle(
      hc,
      r,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                gold.withValues(alpha: 0.22 + 0.05 * tier),
                gold.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: hc, radius: r)),
    );
    final rays = 8 + tier * 2;
    final len = 20.0 + tier * 3 + pulse * 4;
    final ray = Paint()
      ..color = gold.withValues(alpha: 0.30 + 0.04 * tier)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(hc.dx, hc.dy);
    canvas.rotate(t * 2 * math.pi * 0.15); // xoay chậm
    for (var i = 0; i < rays; i++) {
      final a = i / rays * 2 * math.pi;
      final r0 = r + 2;
      final r1 = r + len * (0.7 + 0.3 * math.sin(a * 3 + t * 6));
      canvas.drawLine(
        Offset(math.cos(a) * r0, math.sin(a) * r0),
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        ray,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.t != t ||
      old.elementTime != elementTime ||
      old.moon != moon ||
      old.aura != aura ||
      old.realm != realm ||
      old.halo != halo ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg ||
      old.swordWheelImg != swordWheelImg ||
      old.tienTier != tienTier ||
      old.haloImg != haloImg ||
      old.elements.join() != elements.join();
}

/// Quỹ đạo VŨ KHÍ: vòng ngang quanh eo, góc quét đều nhưng bán kính + cao độ
/// dao động theo sin TẦN SỐ LỆCH NHAU (đường Lissajous) → quỹ tích bất quy
/// tắc như "ý niệm điều khiển", không phải vòng tròn máy móc.
/// Trả về (vị trí, đang ở nửa TRƯỚC người hay không).
(Offset, bool) weaponOrbit(double t, Offset c) {
  final a = t * 2 * math.pi;
  final r = 44 + 10 * math.sin(a * 3 + 1.3);
  return (
    Offset(
      c.dx + math.cos(a) * r,
      c.dy - 6 + math.sin(a) * r * 0.40 + math.sin(a * 2 + 0.7) * 6,
    ),
    math.sin(a) > 0, // nửa vòng dưới coi như bay TRƯỚC người
  );
}

/// Quỹ đạo PHÁP BẢO: TRỤC KHÁC HẲN vũ khí — ellipse dựng đứng hơn, NGHIÊNG
/// chéo ~29°, tâm nâng lên ngang ngực, quay NGƯỢC chiều, bán kính thở theo
/// tần số khác → hai món không bao giờ trùng nhịp hay trùng đường.
(Offset, bool) phapbaoOrbit(double t, Offset c) {
  final a = -t * 2 * math.pi + 2.6; // ngược chiều, mọc lệch góc so với vũ khí
  final r = 34 + 8 * math.sin(a * 2 + 0.5);
  final raw = Offset(math.cos(a) * r * 0.55, math.sin(a) * r * 0.72);
  const ct = 0.8776, st = 0.4794; // cos/sin 0.5 rad — góc nghiêng trục
  return (
    c + Offset(raw.dx * ct - raw.dy * st, -10 + raw.dx * st + raw.dy * ct),
    raw.dy > 0, // nửa thấp của vòng chéo coi như TRƯỚC người
  );
}

/// Vẽ 1 món bay quanh + vệt đuôi theo quỹ đạo [orbit], TÁCH LỚP: nửa vòng sau
/// gọi từ SkyPainter (dưới ảnh nhân vật → thân che thật), nửa trước từ
/// AuraPainter.
void drawOrbiter(
  Canvas canvas,
  double t,
  Offset c,
  Color color,
  ui.Image img, {
  required bool frontLayer,
  double scale = 1,
  (Offset, bool) Function(double, Offset) orbit = weaponOrbit,
}) {
  final (p, front) = orbit(t, c);
  if (front != frontLayer) return;
  // đuôi kiếm quang: lấy lại vị trí các pha ngay trước → chuỗi đốm nhỏ mờ dần
  final tail = Paint();
  for (var k = 6; k >= 1; k--) {
    final (q, _) = orbit(t - k * 0.013, c);
    tail.color = color.withValues(alpha: 0.30 * (1 - k / 7));
    canvas.drawCircle(q, (2.4 - k * 0.28) * scale, tail);
  }
  // ra sau nhỏ lại một chút cho có chiều sâu
  final side = (front ? 26.0 : 21.0) * scale;
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromCenter(center: p, width: side, height: side),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: front ? 1 : 0.88),
  );
}

/// Hiệu ứng bay quanh theo HỆ công pháp (vẽ ĐÈ lên bóng người — quầng thở
/// nằm bên SkyPainter phía sau):
/// qi đốm sáng · ice mảnh băng · wind cung gió xoáy · earth đá vụn ·
/// sword kiếm quang · gold vòng kim quang lan · star tinh tú nhấp nháy ·
/// fire lưỡi lửa bốc lên · leaf lá cuốn theo gió.
/// Kèm VŨ KHÍ ĐANG ĐEO bay quanh người (quỹ đạo Lissajous — không tròn đều).
class AuraPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final Aura style;
  final ui.Image? weaponImg; // icon vũ khí đang đeo — null = không vẽ
  final ui.Image? phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  AuraPainter(
    this.t,
    this.color,
    this.style, {
    this.weaponImg,
    this.phapbaoImg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (style) {
      case Aura.qi:
        _dots(canvas, c);
      case Aura.ice:
        _shards(canvas, c);
      case Aura.wind:
        _arcs(canvas, c);
      case Aura.earth:
        _rocks(canvas, c);
      case Aura.sword:
        _blades(canvas, c);
      case Aura.gold:
        _dots(canvas, c); // bỏ _rings (vòng ellip lan từng đợt) theo yêu cầu
      case Aura.star:
        _stars(canvas, c);
      case Aura.fire:
        _flames(canvas, c);
      case Aura.leaf:
        _leaves(canvas, c);
    }
    if (weaponImg != null) {
      drawOrbiter(canvas, t, c, color, weaponImg!, frontLayer: true);
    }
    if (phapbaoImg != null) {
      drawOrbiter(
        canvas,
        t,
        c,
        color,
        phapbaoImg!,
        frontLayer: true,
        scale: 0.82,
        orbit: phapbaoOrbit,
      );
    }
  }

  /// lưỡi lửa bốc từ quanh thân lên, lắc ngang + nhỏ dần khi lên cao
  void _flames(Canvas canvas, Offset c) {
    for (var i = 0; i < 6; i++) {
      final ph = (t * 2 + i / 6) % 1; // 2 đợt/loop
      final x =
          c.dx + ((i * 29) % 76 - 38) + math.sin((t + i) * 2 * math.pi) * 4;
      final y = c.dy + 34 - ph * 66;
      final s = (1 - ph) * 4.2 + 0.8;
      final flame = Path()
        ..moveTo(x, y - s * 1.7)
        ..quadraticBezierTo(x + s, y - s * 0.3, x, y + s)
        ..quadraticBezierTo(x - s, y - s * 0.3, x, y - s * 1.7);
      canvas.drawPath(flame, _glow(0.75 * (1 - ph) + 0.1));
    }
  }

  /// lá cuốn: bay quanh theo elip đồng thời tự xoay, rơi nhẹ rồi cuốn lên
  void _leaves(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final ang = (t + i / 5) * 2 * math.pi;
      final p =
          c +
          Offset(
            math.cos(ang) * 56,
            math.sin(ang) * 24 + math.sin(ang * 2 + i) * 5,
          );
      final front = math.sin(ang) > 0;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang * 2 + i); // lá tự xoay khi bay
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 7, height: 3),
        _glow(front ? 0.85 : 0.35),
      );
      canvas.restore();
    }
  }

  Paint _glow(double alpha) => Paint()
    ..color = color.withValues(alpha: alpha)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  /// đốm linh khí chạy quỹ đạo elip (mặc định)
  void _dots(Canvas canvas, Offset c) {
    for (var i = 0; i < 3; i++) {
      final ang = (t + i / 3) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 58, math.sin(ang) * 22);
      final front = math.sin(ang) > 0;
      canvas.drawCircle(p, front ? 3 : 2, _glow(front ? 0.9 : 0.35));
    }
  }

  /// mảnh băng hình thoi xoay quanh
  void _shards(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final ang = (t + i / 5) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 56, math.sin(ang) * 26);
      final front = math.sin(ang) > 0;
      final s = front ? 4.5 : 3.0;
      final shard = Path()
        ..moveTo(p.dx, p.dy - s)
        ..lineTo(p.dx + s * 0.6, p.dy)
        ..lineTo(p.dx, p.dy + s)
        ..lineTo(p.dx - s * 0.6, p.dy)
        ..close();
      canvas.drawPath(shard, _glow(front ? 0.9 : 0.4));
    }
  }

  /// cung gió xoáy quanh người
  void _arcs(Canvas canvas, Offset c) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final start = (t + i / 3) * 2 * math.pi;
      paint
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: 0.55);
      canvas.drawArc(
        Rect.fromCenter(center: c, width: 112, height: 52),
        start,
        1.1,
        false,
        paint,
      );
    }
  }

  /// đá vụn lơ lửng vòng quanh chân (quỹ đạo thấp, chậm)
  void _rocks(Canvas canvas, Offset c) {
    for (var i = 0; i < 4; i++) {
      final ang = (t * 0.5 + i / 4) * 2 * math.pi;
      final p =
          c +
          Offset(math.cos(ang) * 54, 22 + math.sin(ang) * 10); // lửng quanh đùi
      final s = math.sin(ang) > 0 ? 3.4 : 2.4;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 1.6),
        _glow(0.75),
      );
      canvas.restore();
    }
  }

  /// kiếm quang: vạch sáng bay tiếp tuyến quỹ đạo
  void _blades(Canvas canvas, Offset c) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final ang = (t + i / 3) * 2 * math.pi;
      final p = c + Offset(math.cos(ang) * 58, math.sin(ang) * 24);
      final dir = Offset(-math.sin(ang), math.cos(ang)); // tiếp tuyến
      final front = math.sin(ang) > 0;
      paint.color = color.withValues(alpha: front ? 0.95 : 0.4);
      canvas.drawLine(p - dir * 8, p + dir * 8, paint);
      // ánh lóe đầu kiếm
      canvas.drawCircle(p + dir * 8, 1.6, _glow(front ? 0.9 : 0.4));
    }
  }

  /// tinh tú nhấp nháy quanh người (chữ thập 4 cánh)
  void _stars(Canvas canvas, Offset c) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final ang = i * math.pi / 3 + 0.4;
      final r = 46.0 + 14 * ((i * 37) % 3);
      final p = c + Offset(math.cos(ang) * r, math.sin(ang) * r * 0.5);
      final tw =
          (0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 6))));
      final s = 2.0 + tw * 2.5;
      paint
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: tw);
      canvas.drawLine(p - Offset(s, 0), p + Offset(s, 0), paint);
      canvas.drawLine(p - Offset(0, s), p + Offset(0, s), paint);
    }
  }

  @override
  bool shouldRepaint(AuraPainter old) =>
      old.t != t ||
      old.color != color ||
      old.style != style ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg;
}
