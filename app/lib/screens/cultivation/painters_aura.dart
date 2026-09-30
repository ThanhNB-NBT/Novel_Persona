import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'painters_qi.dart';

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

/// Màu các dải linh khí theo bộ hệ linh căn; đơn hệ thêm 1 dải sáng hơn cho đầy.
List<Color> qiColors(List<String> elements, Color fallback) {
  final cols = [for (final e in elements) elemAura[e]?.$2 ?? fallback];
  if (cols.length == 1) cols.add(Color.lerp(cols[0], Colors.white, 0.45)!);
  return cols;
}

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
  final int tienTier; // bậc tiên (0..14) → hào quang sau đầu; -1 = không vẽ
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
    paintQiRibbons(canvas, Offset(c.dx, c.dy + 6), qiColors(elements, aura),
        elementTime, front: false, width: 4.2);

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

  /// Hào quang cõi tiên: đĩa vàng ấm + tia sáng xoay quanh đầu, càng lên bậc (tier)
  /// càng nhiều tia + rực hơn. Vẽ ở lớp nền → nằm SAU nhân vật.
  void _drawTienCorona(Canvas canvas, Offset hc, int level) {
    // Cỡ + độ rực chỉ tăng tới bậc 9 (quá nữa tia dài ra ngoài khung 150px).
    // Cung Siêu Thoát (10..14, migration 124) đổi màu: vàng → trắng tím, càng cao càng lạnh.
    final tier = math.min(level, 9);
    final gold = Color.lerp(const Color(0xFFFFD25A), const Color(0xFFE6D6FF),
        ((level - 9) / 5).clamp(0.0, 1.0))!;
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
    // Tia hình NÊM thon (gốc rộng → mũi nhọn) tô gradient tan dần ra ngoài, hai lớp
    // xoay ngược chiều: lớp dài thưa + lớp ngắn dày → ánh sáng có nhịp, không còn
    // là các nét kẻ đều như nan quạt.
    for (final (layer, n, lenK, spin, wid) in [
      (0, 6 + tier, 1.0, 0.15, 0.10),
      (1, 10 + tier, 0.55, -0.1, 0.06),
    ]) {
      final len = (20.0 + tier * 3 + pulse * 4) * lenK;
      canvas.save();
      canvas.translate(hc.dx, hc.dy);
      canvas.rotate(t * 2 * math.pi * spin + layer * 0.3);
      for (var i = 0; i < n; i++) {
        final a = i / n * 2 * math.pi;
        final flick = 0.7 + 0.3 * math.sin(a * 3 + t * 2 * math.pi * 2 + layer);
        final r0 = r * 0.72;
        final r1 = r + len * flick;
        final ray = Path()
          ..moveTo(math.cos(a - wid) * r0, math.sin(a - wid) * r0)
          ..lineTo(math.cos(a) * r1, math.sin(a) * r1)
          ..lineTo(math.cos(a + wid) * r0, math.sin(a + wid) * r0)
          ..close();
        canvas.drawPath(
          ray,
          Paint()
            ..shader = RadialGradient(
              colors: [
                gold.withValues(alpha: (0.34 + 0.04 * tier) * (1 - layer * 0.3)),
                gold.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: Offset.zero, radius: r1)),
        );
      }
      canvas.restore();
    }
    // vành sáng mảnh sát đĩa — chốt viền cho hào quang có hình khối
    canvas.drawCircle(
      hc,
      r * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.lerp(gold, Colors.white, 0.5)!
            .withValues(alpha: 0.35 + 0.25 * pulse),
    );
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
/// qi hạt linh khí đuôi sao chổi · ice tinh thể lục giác + sương băng ·
/// wind dải lụa gió thon · earth đá đa giác lơ lửng · sword lưỡi kiếm khí có
/// đuôi quang · gold kim quang xoắn ốc bốc lên · star chòm tinh quang lấp lánh ·
/// fire lưỡi lửa chuyển sắc + tàn lửa · leaf phiến lá lật theo gió.
/// Kèm VŨ KHÍ ĐANG ĐEO bay quanh người (quỹ đạo Lissajous — không tròn đều).
class AuraPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  final Aura style;
  final ui.Image? weaponImg; // icon vũ khí đang đeo — null = không vẽ
  final ui.Image? phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  final List<String> elements; // bộ hệ linh căn → nửa TRƯỚC của dải linh khí
  final double elementTime; // cùng đồng hồ với SkyPainter
  AuraPainter(
    this.t,
    this.color,
    this.style, {
    this.weaponImg,
    this.phapbaoImg,
    this.elements = const [],
    this.elementTime = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (elements.isNotEmpty) {
      paintQiRibbons(canvas, Offset(c.dx, c.dy + 6), qiColors(elements, color),
          elementTime, front: true, width: 4.2);
    }
    switch (style) {
      case Aura.qi:
        _qi(canvas, c);
      case Aura.ice:
        _shards(canvas, c);
      case Aura.wind:
        _arcs(canvas, c);
      case Aura.earth:
        _rocks(canvas, c);
      case Aura.sword:
        _blades(canvas, c);
      case Aura.gold:
        _gold(canvas, c); // không dùng vòng ellip lan từng đợt (đã bỏ theo yêu cầu)
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

  // ---- nét vẽ dùng chung: hạt phát sáng + đuôi sao chổi ----
  // Mọi hiệu ứng dựng từ 2 nét này thay vì chấm/vạch trơn: quầng mềm (gradient
  // tỏa, không dùng blur cho nhẹ máy) + lõi sáng + tâm trắng → đọc được cả trên
  // nền sáng lẫn tối; đuôi thon dần theo quỹ đạo nên thấy hướng bay.

  /// Hạt linh khí: quầng tỏa r×3 + lõi pha trắng + tâm trắng.
  void _spark(Canvas canvas, Offset p, double r, double a, {Color? col}) {
    final c0 = col ?? color;
    final halo = r * 3;
    canvas.drawCircle(
      p,
      halo,
      Paint()
        ..shader = RadialGradient(
          colors: [c0.withValues(alpha: a * 0.42), c0.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: halo)),
    );
    canvas.drawCircle(
      p,
      r,
      Paint()..color = Color.lerp(c0, Colors.white, 0.3)!.withValues(alpha: a),
    );
    canvas.drawCircle(
      p,
      r * 0.45,
      Paint()..color = Colors.white.withValues(alpha: a * 0.9),
    );
  }

  /// Đuôi thon dần: nối các vị trí quá khứ của [at] (thời gian lùi dt mỗi đốt).
  void _trail(
    Canvas canvas,
    Offset Function(double) at,
    double t0, {
    int n = 9,
    double dt = 0.012,
    double w = 3,
    double a = 0.6,
    Color? col,
  }) {
    final c0 = col ?? color;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    var prev = at(t0);
    for (var k = 1; k <= n; k++) {
      final q = at(t0 - k * dt);
      final f = 1 - k / (n + 1);
      paint
        ..strokeWidth = w * f + 0.3
        ..color = c0.withValues(alpha: a * f * f);
      canvas.drawLine(prev, q, paint);
      prev = q;
    }
  }

  /// Điểm trên elip nghiêng [tilt] quanh [c] — quỹ đạo chung của các hiệu ứng.
  static Offset _ell(Offset c, double ang,
      {double rx = 56, double ry = 20, double tilt = -0.2, double dy = 0}) {
    final x = math.cos(ang) * rx, y = math.sin(ang) * ry;
    return c +
        Offset(
          x * math.cos(tilt) - y * math.sin(tilt),
          x * math.sin(tilt) + y * math.cos(tilt) + dy,
        );
  }

  /// Linh khí (mặc định): 5 hạt đuôi sao chổi trên HAI elip nghiêng ngược nhau,
  /// hạt ở nửa sau nhỏ + mờ để có chiều sâu.
  void _qi(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final tilt = i.isEven ? -0.28 : 0.3;
      final dy = i.isEven ? -6.0 : 10.0;
      Offset at(double tt) =>
          _ell(c, (tt + i / 5) * 2 * math.pi, rx: 54, ry: 18, tilt: tilt, dy: dy);
      final front = math.sin((t + i / 5) * 2 * math.pi) > 0;
      final a = front ? 0.9 : 0.4;
      _trail(canvas, at, t, w: front ? 3 : 2, a: a * 0.7);
      _spark(canvas, at(t), front ? 2.2 : 1.5, a);
    }
  }

  /// Kim quang: hạt vàng xoắn ốc bốc lên từ chân tới đỉnh đầu + vài tia lóe 4 cánh.
  void _gold(Canvas canvas, Offset c) {
    for (var i = 0; i < 8; i++) {
      Offset at(double tt) {
        final ph = (tt + i / 8) % 1;
        final ang = ph * 2 * math.pi * 1.5 + i * 0.8;
        return Offset(
          c.dx + math.cos(ang) * (42 - ph * 16),
          c.dy + 44 - ph * 90,
        );
      }

      final ph = (t + i / 8) % 1;
      final fade = math.sin(ph * math.pi); // hiện dần ở chân, tắt dần trên đầu
      final front = math.sin(ph * 2 * math.pi * 1.5 + i * 0.8) > 0;
      final a = fade * (front ? 0.95 : 0.4);
      if (ph > 0.06) _trail(canvas, at, t, n: 6, w: 2.4, a: a * 0.6);
      _spark(canvas, at(t), front ? 1.9 : 1.3, a);
    }
    for (var i = 0; i < 3; i++) {
      final tw = math.max(0.0, math.sin(2 * math.pi * (t * 2 + i / 3)));
      if (tw < 0.05) continue;
      final p = c + Offset([-34.0, 30.0, 8.0][i], [-30.0, -8.0, 26.0][i]);
      _sparkle(canvas, p, 3 + tw * 5, tw * 0.9, rot: 0.3 * i);
    }
  }

  /// Tinh quang 4 cánh lõm (kiểu lấp lánh), không phải chữ thập thẳng.
  void _sparkle(Canvas canvas, Offset p, double r, double a,
      {double rot = 0, Color? col}) {
    final c0 = col ?? color;
    final path = Path();
    for (var k = 0; k < 8; k++) {
      final ang = rot + k * math.pi / 4;
      final rr = k.isEven ? r : r * 0.22;
      final q = p + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
      k == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    path.close();
    canvas.drawCircle(
      p,
      r * 1.4,
      Paint()
        ..shader = RadialGradient(
          colors: [c0.withValues(alpha: a * 0.35), c0.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: r * 1.4)),
    );
    canvas.drawPath(
      path,
      Paint()..color = Color.lerp(c0, Colors.white, 0.55)!.withValues(alpha: a),
    );
  }

  /// Lửa: lưỡi lửa bốc từ quanh chân lên — gốc tròn sáng, mũi cong lệch theo gió
  /// (cubic, không đối xứng), 2 lớp: vỏ màu hệ tan dần lên trên + lõi vàng trắng;
  /// kèm tàn lửa li ti bay vụt lên.
  void _flames(Canvas canvas, Offset c) {
    Path tongue(Offset base, double w, double h, double bend) => Path()
      ..moveTo(base.dx - w, base.dy)
      ..cubicTo(base.dx - w * 1.1, base.dy - h * 0.45, base.dx + bend * 0.4 - w * 0.2,
          base.dy - h * 0.7, base.dx + bend, base.dy - h)
      ..cubicTo(base.dx + bend * 0.3 + w * 0.5, base.dy - h * 0.62,
          base.dx + w * 1.15, base.dy - h * 0.4, base.dx + w, base.dy)
      ..arcToPoint(Offset(base.dx - w, base.dy),
          radius: Radius.circular(w), clockwise: true);

    for (var i = 0; i < 8; i++) {
      final ph = (t * 2 + i / 8) % 1; // 2 đợt/loop
      // gốc lửa ôm quanh thân (hai bên + dưới chân), bốc lên rồi tắt
      final side = i.isEven ? -1.0 : 1.0;
      final x = c.dx + side * (16 + (i * 7) % 20);
      final y = c.dy + 48 - ph * 38;
      final grow = math.sin(ph * math.pi); // nhỏ → to → tắt
      final w = 2.5 + grow * 3.2;
      final h = 9 + grow * 16;
      final bend = math.sin((t * 4 + i / 5) * 2 * math.pi) * w * 1.2 - side * 2;
      final base = Offset(x, y);
      final a = grow * 0.9;
      if (a < 0.03) continue;
      final rect = Rect.fromLTRB(x - w * 1.2, y - h, x + w * 1.2, y + w);
      canvas.drawCircle(
        base.translate(0, -h * 0.3),
        h * 0.55,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: a * 0.28),
            color.withValues(alpha: 0),
          ]).createShader(
              Rect.fromCircle(center: base.translate(0, -h * 0.3), radius: h * 0.55)),
      );
      canvas.drawPath(
        tongue(base, w, h, bend),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color.lerp(color, const Color(0xFFFFE066), 0.5)!.withValues(alpha: a),
              color.withValues(alpha: a * 0.85),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(rect),
      );
      canvas.drawPath(
        tongue(base.translate(0, -0.5), w * 0.5, h * 0.55, bend * 0.6),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              const Color(0xFFFFFBE6).withValues(alpha: a),
              const Color(0xFFFFE066).withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    for (var i = 0; i < 7; i++) {
      final ph = (t * 3 + i / 7) % 1;
      final p = Offset(
        c.dx + ((i * 31) % 70 - 35) + math.sin((ph + i) * 2 * math.pi) * 6,
        c.dy + 30 - ph * 84,
      );
      _spark(canvas, p, 0.9, (1 - ph) * 0.9,
          col: Color.lerp(color, const Color(0xFFFFE066), 0.5));
    }
  }

  /// Lá: phiến lá có gân, tự lật (co trục ngắn theo cos) khi cuốn theo gió xoắn.
  void _leaves(Canvas canvas, Offset c) {
    for (var i = 0; i < 7; i++) {
      final ang = (t + i / 7) * 2 * math.pi;
      final p = _ell(c, ang,
          rx: 52 + (i % 3) * 5, ry: 20, tilt: -0.15, dy: math.sin(ang * 2 + i) * 8);
      final front = math.sin(ang) > 0;
      final a = front ? 0.95 : 0.45;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang * 2 + i);
      canvas.scale(1, 0.35 + 0.65 * math.cos(ang * 3 + i).abs()); // lật mặt lá
      final l = front ? 6.5 : 5.0, w = l * 0.45;
      final leaf = Path()
        ..moveTo(-l, 0)
        ..quadraticBezierTo(0, -w * 1.6, l, 0)
        ..quadraticBezierTo(0, w * 1.6, -l, 0);
      canvas.drawPath(
        leaf,
        Paint()
          ..shader = LinearGradient(colors: [
            Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: a),
            color.withValues(alpha: a),
            Color.lerp(color, Colors.black, 0.25)!.withValues(alpha: a),
          ]).createShader(Rect.fromLTRB(-l, -w, l, w)),
      );
      canvas.drawLine(
        Offset(-l * 0.9, 0),
        Offset(l * 0.8, 0),
        Paint()
          ..strokeWidth = 0.6
          ..color = Colors.white.withValues(alpha: a * 0.55),
      );
      canvas.restore();
    }
  }

  /// Băng: tinh thể lục giác (3 trục + nhánh) xoay quanh + sương băng rơi lấm tấm.
  void _shards(Canvas canvas, Offset c) {
    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final ang = (t + i / 6) * 2 * math.pi;
      final p = _ell(c, ang, rx: 54, ry: 20, tilt: 0.12, dy: (i % 2) * 8 - 4);
      final front = math.sin(ang) > 0;
      final a = front ? 0.95 : 0.4;
      final r = front ? 5.0 : 3.6;
      _spark(canvas, p, r * 0.35, a * 0.7);
      line
        ..strokeWidth = front ? 1.2 : 0.9
        ..color = Color.lerp(color, Colors.white, 0.5)!.withValues(alpha: a);
      for (var k = 0; k < 3; k++) {
        final d = t * 2 * math.pi * 0.5 + i + k * math.pi / 3;
        final u = Offset(math.cos(d), math.sin(d));
        final nrm = Offset(-u.dy, u.dx);
        canvas.drawLine(p - u * r, p + u * r, line);
        for (final s in [-1.0, 1.0]) {
          final b = p + u * r * 0.55 * s; // nhánh chữ V ở 2 đầu trục
          canvas.drawLine(b, b + (u * s + nrm) * r * 0.28, line);
          canvas.drawLine(b, b + (u * s - nrm) * r * 0.28, line);
        }
      }
    }
    for (var i = 0; i < 8; i++) {
      final ph = (t + i / 8) % 1;
      final p = Offset(
        c.dx + ((i * 37) % 96 - 48) + math.sin((ph * 2 + i) * math.pi) * 4,
        c.dy - 40 + ph * 86,
      );
      _spark(canvas, p, 0.8, math.sin(ph * math.pi) * 0.7);
    }
  }

  /// Gió: dải lụa gió thon hai đầu quét quanh người (3 elip lệch trục/tốc độ).
  void _arcs(Canvas canvas, Offset c) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final start = (t * (i.isEven ? 1 : -1) + i / 4) * 2 * math.pi;
      const seg = 14;
      const span = 1.6;
      final rx = 50.0 + i * 5, ry = 15.0 + i * 3;
      final tilt = [-0.25, 0.18, -0.08, 0.3][i];
      final dy = [-14.0, 4.0, 18.0, -2.0][i];
      var prev = _ell(c, start, rx: rx, ry: ry, tilt: tilt, dy: dy);
      for (var k = 1; k <= seg; k++) {
        final a = start + span * k / seg * (i.isEven ? 1 : -1);
        final q = _ell(c, a, rx: rx, ry: ry, tilt: tilt, dy: dy);
        final prof = math.sin(math.pi * k / seg); // thon hai đầu
        final front = math.sin(a) > 0;
        paint
          ..strokeWidth = 0.4 + prof * 2.6
          ..color = color.withValues(alpha: prof * (front ? 0.75 : 0.3));
        canvas.drawLine(prev, q, paint);
        prev = q;
      }
    }
  }

  /// Thổ: đá vụn gồ ghề (5-7 đỉnh, góc + bán kính lệch tất định) lơ lửng nhấp
  /// nhô quanh đùi, tự xoay; mặt vát sáng phía trên + đáy tối + bụi rơi.
  void _rocks(Canvas canvas, Offset c) {
    for (var i = 0; i < 5; i++) {
      final ang = (t * 0.5 + i / 5) * 2 * math.pi;
      final bob = math.sin((t * 2 + i / 5) * 2 * math.pi) * 3;
      final p = _ell(c, ang, rx: 52, ry: 11, tilt: 0, dy: 24 + bob);
      final front = math.sin(ang) > 0;
      final s = (front ? 5.2 : 3.8) * (0.8 + 0.25 * (i % 3));
      final nv = 5 + i % 3;
      final spin = t * 2 * math.pi * (i.isEven ? 0.5 : -0.5) + i;
      final pts = <Offset>[
        for (var k = 0; k < nv; k++)
          () {
            final jitter = ((i * 13 + k * 7) % 9) / 9; // 0..1 tất định
            final a = spin + (k + jitter * 0.6) * 2 * math.pi / nv;
            final r = s * (0.65 + 0.5 * (((i * 5 + k * 3) % 7) / 6));
            return p + Offset(math.cos(a) * r, math.sin(a) * r * 0.85);
          }(),
      ];
      final path = Path()..addPolygon(pts, true);
      final a = front ? 0.95 : 0.5;
      final light = Color.lerp(color, Colors.white, 0.45)!;
      final dark = Color.lerp(color, Colors.black, 0.45)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [light.withValues(alpha: a), dark.withValues(alpha: a)],
          ).createShader(Rect.fromCircle(center: p, radius: s)),
      );
      // mặt vát: tam giác nối tâm lệch trên-trái với 2 đỉnh cao nhất
      final top = [...pts]..sort((u, v) => u.dy.compareTo(v.dy));
      canvas.drawPath(
        Path()
          ..moveTo(p.dx - s * 0.15, p.dy - s * 0.1)
          ..lineTo(top[0].dx, top[0].dy)
          ..lineTo(top[1].dx, top[1].dy)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: a * 0.28),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeJoin = StrokeJoin.round
          ..color = dark.withValues(alpha: a * 0.8),
      );
      final dust = (t * 2 + i / 5) % 1;
      _spark(canvas, p + Offset(math.sin(i + dust * 4) * 3, s + dust * 8), 0.7,
          (1 - dust) * a * 0.6);
    }
  }

  /// Kiếm quang: 4 lưỡi khí hình thoi dài bay tiếp tuyến, đuôi quang kéo dài phía sau.
  void _blades(Canvas canvas, Offset c) {
    for (var i = 0; i < 4; i++) {
      final tilt = i.isEven ? -0.22 : 0.26;
      Offset at(double tt) =>
          _ell(c, (tt + i / 4) * 2 * math.pi, rx: 58, ry: 22, tilt: tilt, dy: i * 4 - 6);
      final p = at(t), q = at(t - 0.004);
      final dir = (p - q) / math.max((p - q).distance, 0.001);
      final nrm = Offset(-dir.dy, dir.dx);
      final front = math.sin((t + i / 4) * 2 * math.pi) > 0;
      final a = front ? 0.95 : 0.4;
      _trail(canvas, at, t, n: 10, dt: 0.01, w: 3.4, a: a * 0.55);
      final len = front ? 11.0 : 8.0, wid = front ? 2.2 : 1.6;
      final blade = Path()
        ..moveTo(p.dx + dir.dx * len, p.dy + dir.dy * len)
        ..lineTo(p.dx + nrm.dx * wid, p.dy + nrm.dy * wid)
        ..lineTo(p.dx - dir.dx * len * 0.5, p.dy - dir.dy * len * 0.5)
        ..lineTo(p.dx - nrm.dx * wid, p.dy - nrm.dy * wid)
        ..close();
      canvas.drawPath(
        blade,
        Paint()..color = Color.lerp(color, Colors.white, 0.6)!.withValues(alpha: a),
      );
      _spark(canvas, p + dir * len, 1.0, a); // lóe mũi kiếm
    }
  }

  /// Tinh tú: 7 tinh quang lấp lánh trôi chậm, nối nhau bằng đường chòm sao mờ.
  void _stars(Canvas canvas, Offset c) {
    final pts = <Offset>[];
    for (var i = 0; i < 7; i++) {
      final ang = i * 2 * math.pi / 7 + 0.4 + t * 2 * math.pi * 0.25;
      final r = 44.0 + 12 * ((i * 37) % 3);
      pts.add(c + Offset(math.cos(ang) * r, math.sin(ang) * r * 0.5 - 6));
    }
    final link = Paint()
      ..strokeWidth = 0.6
      ..color = color.withValues(alpha: 0.22);
    for (var i = 0; i < pts.length; i++) {
      canvas.drawLine(pts[i], pts[(i + 1) % pts.length], link);
    }
    for (var i = 0; i < pts.length; i++) {
      final tw = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / 7));
      _sparkle(canvas, pts[i], 3 + tw * 3.5, 0.35 + 0.6 * tw,
          rot: t * math.pi + i);
    }
  }

  @override
  bool shouldRepaint(AuraPainter old) =>
      old.t != t ||
      old.elementTime != elementTime ||
      old.elements.join() != elements.join() ||
      old.color != color ||
      old.style != style ||
      old.weaponImg != weaponImg ||
      old.phapbaoImg != phapbaoImg;
}
