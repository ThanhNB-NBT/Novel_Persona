import 'package:flutter/material.dart';

/// Pixel art tự vẽ bằng code: sprite 12×12 mã hóa chuỗi ký tự → CustomPainter.
/// Ký tự chung: '.'=trong suốt, k=viền, w=trắng, x=gỗ, y/z=kim loại, r=đỏ,
/// f=da, g=quầng sáng mờ. A/B/C = màu theo PHẨM CẤP (đổi tông → 1 grid ra 5 icon).

/// Bảng màu 5 phẩm (1 Hoàng → 5 Tiên), theo ngôn ngữ rarity quen mắt:
/// xám đồng → lục → lam → tím → kim.
const _grades = [
  (a: Color(0xFF9A8C6E), b: Color(0xFFC0B394), c: Color(0xFF6E6249)), // 1 Hoàng
  (a: Color(0xFF51CF66), b: Color(0xFF8CE99A), c: Color(0xFF2F9E44)), // 2 Huyền
  (a: Color(0xFF4DABF7), b: Color(0xFF74C0FC), c: Color(0xFF1C7ED6)), // 3 Địa
  (a: Color(0xFF9775FA), b: Color(0xFFB197FC), c: Color(0xFF7048E8)), // 4 Thiên
  (a: Color(0xFFFFC94D), b: Color(0xFFFFE066), c: Color(0xFFE8A80C)), // 5 Tiên
];

Color gradeColor(int grade) => _grades[(grade - 1).clamp(0, 4)].a;

/// Trọn bộ 3 tông màu của 1 phẩm — cho painter vẽ nhân vật vector.
({Color a, Color b, Color c}) gradePalette(int grade) =>
    _grades[(grade - 1).clamp(0, 4)];

const _sprites = <String, List<String>>{
  // sách công pháp
  'book': [
    '............',
    '.kkkkkkkkk..',
    '.kAAAAAAAk..',
    '.kABBBBBAk..',
    '.kABkkkBAk..',
    '.kABkBkBAk..',
    '.kABkkkBAk..',
    '.kABBBBBAk..',
    '.kAAAAAAAk..',
    '.kCwwwwwCk..',
    '.kkkkkkkkk..',
    '............',
  ],
  // đan dược viên (linh căn)
  'pill': [
    '............',
    '...kkkkk....',
    '..kAABBAk...',
    '.kAABBBAAk..',
    '.kABBwBBAk..',
    '.kABwwBBAk..',
    '.kAABBBAAk..',
    '.kCAAAAACk..',
    '..kCCCCCk...',
    '...kkkkk....',
    '............',
    '............',
  ],
  // hồ lô (đan buff + pháp bảo hồ lô)
  'gourd': [
    '.....kk.....',
    '....kxxk....',
    '...kkAAkk...',
    '...kABBAk...',
    '...kkAAkk...',
    '..kAABBAAk..',
    '.kABBwBBBAk.',
    '.kABwwBBBAk.',
    '.kAABBBBAAk.',
    '..kAAAAAAk..',
    '...kkkkkk...',
    '............',
  ],
  // đan hộ thân (khiên)
  'shield_pill': [
    '............',
    '..kkkkkkkk..',
    '..kABBBBAk..',
    '..kABwwBAk..',
    '..kABwwBAk..',
    '..kABBBBAk..',
    '..kAABBAAk..',
    '...kABBAk...',
    '...kAABAk...',
    '....kAAk....',
    '.....kk.....',
    '............',
  ],
  'sword': [
    '.....kk.....',
    '....kzwk....',
    '....kzwk....',
    '....kzwk....',
    '....kzwk....',
    '....kzwk....',
    '...kkzwkk...',
    '..kAAAAAAk..',
    '....kxxk....',
    '....kxxk....',
    '.....kk.....',
    '............',
  ],
  // đao lưỡi cong
  'saber': [
    '......kkk...',
    '.....kzwk...',
    '.....kzwk...',
    '....kzwk....',
    '....kzwk....',
    '...kzwk.....',
    '...kzwk.....',
    '..kAAAAk....',
    '...kxxk.....',
    '...kxxk.....',
    '....kk......',
    '............',
  ],
  'spear': [
    '.....kk.....',
    '....kABk....',
    '....kBBk....',
    '.....kk.....',
    '....kxxk....',
    '....kxxk....',
    '....kxxk....',
    '....kxxk....',
    '....kxxk....',
    '....kxxk....',
    '.....kk.....',
    '............',
  ],
  'bow': [
    '...kkk......',
    '..kABk......',
    '.kABk..w....',
    '.kABk..w....',
    '.kABk..w....',
    '.kABk..w....',
    '.kABk..w....',
    '.kABk..w....',
    '.kABk..w....',
    '..kABk......',
    '...kkk......',
    '............',
  ],
  // la bàn tầm linh
  'compass': [
    '............',
    '...kkkkk....',
    '..kzzzzzk...',
    '.kzzwrwzzk..',
    '.kzzwrwzzk..',
    '.kzzzrzzzk..',
    '.kzzzAzzzk..',
    '.kzzzzzzzk..',
    '..kzzzzzk...',
    '...kkkkk....',
    '............',
    '............',
  ],
  // túi càn khôn
  'pouch': [
    '............',
    '....kkkk....',
    '...kxwwxk...',
    '....kxxk....',
    '...kAAAAk...',
    '..kAABBAAk..',
    '..kABBBBAk..',
    '..kABBBBAk..',
    '..kAABBAAk..',
    '...kAAAAk...',
    '....kkkk....',
    '............',
  ],
  // ngọc bội
  'jade': [
    '............',
    '.....kk.....',
    '....kABk....',
    '...kABBAk...',
    '..kABwBBAk..',
    '.kABBwBBBAk.',
    '..kABBBBAk..',
    '...kABBAk...',
    '....kABk....',
    '.....kk.....',
    '............',
    '............',
  ],
  // trận bàn tụ linh
  'array': [
    '............',
    '...kkkkkk...',
    '..kAzzzzAk..',
    '.kAzBkkBzAk.',
    '.kAzkBBkzAk.',
    '.kAzkBBkzAk.',
    '.kAzBkkBzAk.',
    '..kAzzzzAk..',
    '...kkkkkk...',
    '............',
    '............',
    '............',
  ],
  // gương kim quang
  'mirror': [
    '...kkkkk....',
    '..kAzwzAk...',
    '.kAzwwwzAk..',
    '.kAzwwzzAk..',
    '.kAzzzzzAk..',
    '..kAzzzAk...',
    '...kkkkk....',
    '....kxxk....',
    '....kxxk....',
    '.....kk.....',
    '............',
    '............',
  ],
  // đỉnh (vạc 3 chân)
  'cauldron': [
    '............',
    '..kk....kk..',
    '..kAkkkkAk..',
    '...kAAAAk...',
    '..kABBBBAk..',
    '.kABBBBBBAk.',
    '.kABBwBBBAk.',
    '..kABBBBAk..',
    '...kAAAAk...',
    '..kCk..kCk..',
    '..kk....kk..',
    '............',
  ],
  // tháp thất bảo
  'pagoda': [
    '.....kk.....',
    '....kAAk....',
    '...kAAAAk...',
    '..kkkkkkkk..',
    '...kBBBBk...',
    '..kkkkkkkk..',
    '..kBBBBBBk..',
    '.kkkkkkkkkk.',
    '.kBBBBBBBBk.',
    '.kkkkkkkkkk.',
    '............',
    '............',
  ],
  // châu báu phát sáng
  'orb': [
    '............',
    '....g..g....',
    '...kkkkk....',
    '..kABBBAk...',
    '.gkBBwBBkg..',
    '.kABwwwBAk..',
    '.gkBBwBBkg..',
    '..kABBBAk...',
    '...kkkkk....',
    '....g..g....',
    '............',
    '............',
  ],
  // thái cực đồ
  'taiji': [
    '............',
    '...kkkkkk...',
    '..kwwwAAAk..',
    '.kwwwwAAAAk.',
    '.kwkwwAAkAk.',
    '.kwwwwAAAAk.',
    '.kwwwAAAAAk.',
    '..kwwwAAAk..',
    '...kkkkkk...',
    '............',
    '............',
    '............',
  ],
  // phù chú (giấy bùa)
  'talisman': [
    '............',
    '....kkkk....',
    '...kBBBBk...',
    '...kBrrBk...',
    '...kBBBBk...',
    '...kBrrBk...',
    '...kBBBBk...',
    '...kBrrBk...',
    '...kBBBBk...',
    '....kkkk....',
    '............',
    '............',
  ],
  // linh thạch (tinh thể)
  'stone': [
    '............',
    '.....kk.....',
    '....kBBk....',
    '...kBwwBk...',
    '..kABBwBAk..',
    '..kABBBBAk..',
    '..kAABBAAk..',
    '...kAABAk...',
    '....kAAk....',
    '.....kk.....',
    '............',
    '............',
  ],
  // cuộn trục công pháp (mở ngang, hai đầu trục gỗ)
  'scroll': [
    '............',
    '.kkkkkkkkkk.',
    '.kxkwwwwkxk.',
    '.kxkwAAwkxk.',
    '.kxkwwwwkxk.',
    '.kxkwAAwkxk.',
    '.kxkwwwwkxk.',
    '.kxkwAAwkxk.',
    '.kxkwwwwkxk.',
    '.kkkkkkkkkk.',
    '..kk....kk..',
    '............',
  ],
  // thẻ ngọc (ngọc giản khắc công pháp, tua đỏ dưới)
  'slip': [
    '............',
    '....kkkk....',
    '...kABBAk...',
    '...kABBAk...',
    '...kABwAk...',
    '...kABBAk...',
    '...kABwAk...',
    '...kABBAk...',
    '...kABBAk...',
    '....kkkk....',
    '.....rr.....',
    '............',
  ],
  // ấn chú (con dấu vuông, mặt son đỏ)
  'seal': [
    '............',
    '.....kk.....',
    '....kAAk....',
    '....kAAk....',
    '...kAAAAk...',
    '..kABBBBAk..',
    '..kABBBBAk..',
    '..kAAAAAAk..',
    '..kkkkkkkk..',
    '..krrrrrrk..',
    '...kkkkkk...',
    '............',
  ],
  // quạt xếp mở (công pháp hệ gió): nan xòe trên, chụm về chuôi dưới
  'fan': [
    '............',
    '..kkk..kkk..',
    '.kBBBkkBBBk.',
    '.kBABBBBABk.',
    '..kBBAABBk..',
    '..kBABBABk..',
    '...kBBBBk...',
    '....kBBk....',
    '....kxxk....',
    '.....kk.....',
    '............',
    '............',
  ],
  // y phục / đạo bào (đai lưng sáng giữa)
  'robe': [
    '............',
    '...kk..kk...',
    '..kABkkBAk..',
    '.kAABBBBAAk.',
    '.kAkBBBBkAk.',
    '.kkkBwwBkkk.',
    '...kBBBBk...',
    '...kBBBBk...',
    '..kABBBBAk..',
    '..kABBBBAk..',
    '..kkkkkkkk..',
    '............',
  ],
  // hài / ngoa (nhìn nghiêng, đế sẫm)
  'boot': [
    '............',
    '....kkkk....',
    '...kABBAk...',
    '...kABBAk...',
    '...kABBAk...',
    '...kABBAkk..',
    '...kABBBBkk.',
    '...kABBBBBk.',
    '..kkkkkkkkk.',
    '..kCCCCCCk..',
    '...kkkkkk...',
    '............',
  ],
  // rương quà trong chương
  'gift': [
    '............',
    '...kkkkkk...',
    '..kABBBBAk..',
    '..kkkwwkkk..',
    '..kAAwwAAk..',
    '..kAAwwAAk..',
    '..kAAAAAAk..',
    '..kkkkkkkk..',
    '............',
    '............',
    '............',
    '............',
  ],
};
// (nhân vật giờ vẽ vector trong cultivation.dart — _HumanPainter, không dùng sprite nữa)

/// Icon pixel: sprite 12×12 tô màu theo phẩm cấp, vẽ nét vuông sắc cạnh.
class PixelIcon extends StatelessWidget {
  final String sprite;
  final int grade; // 1..5, đổi tông A/B/C
  final double size;
  const PixelIcon(this.sprite, {super.key, this.grade = 1, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PixelPainter(_sprites[sprite] ?? _sprites['pill']!, grade),
    );
  }
}

class _PixelPainter extends CustomPainter {
  final List<String> grid;
  final int grade;
  _PixelPainter(this.grid, this.grade);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _grades[(grade - 1).clamp(0, 4)];
    // ô vuông theo cạnh dài nhất của grid (sprite không vuông vẫn lọt khung),
    // căn giữa cả 2 chiều
    final cols = grid[0].length;
    final rows = grid.length;
    final cell = size.width / (cols > rows ? cols : rows);
    final ox = (size.width - cols * cell) / 2;
    final oy = (size.height - rows * cell) / 2;
    final paint = Paint();
    for (var y = 0; y < grid.length; y++) {
      final row = grid[y];
      for (var x = 0; x < row.length; x++) {
        final ch = row[x];
        if (ch == '.') continue;
        paint.color = switch (ch) {
          'k' => const Color(0xFF2E2A3B),
          'w' => const Color(0xFFF6F4EF),
          'x' => const Color(0xFF9C6B3C),
          'y' => const Color(0xFF8B93A6),
          'z' => const Color(0xFFC6CCDA),
          'r' => const Color(0xFFE03131),
          'h' => const Color(0xFF39344E), // tóc
          'f' => const Color(0xFFF1C27D),
          'g' => g.b.withValues(alpha: 0.45),
          'A' => g.a,
          'B' => g.b,
          'C' => g.c,
          _ => const Color(0x00000000),
        };
        // +0.5 phủ mép: tránh khe hở hairline giữa các ô khi scale lẻ
        canvas.drawRect(
            Rect.fromLTWH(ox + x * cell, oy + y * cell, cell + 0.5, cell + 0.5),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) => old.grid != grid || old.grade != grade;
}

// ===== Nhân vật vector "linh thể" theo TỘC + GIỚI TÍNH =====
// Silhouette bezier mượt, áo gradient theo tộc, mắt nhắm phát sáng, lõi đan
// điền rực + viền sáng vành phải. Đặc điểm tộc phóng đại cho nhìn-là-biết:
// Nhân búi tóc + trâm · Yêu tai cáo + đuôi chóp trắng · Ma sừng cong + mắt đỏ
// · Linh vòng quang + tai nhọn + tóc bạc. Nữ: dáng thon + tóc dài xõa hai bên.

/// Palette theo tộc; [glow] là màu năng lượng (mắt + đan điền + đai).
({Color a, Color b, Color c, Color s, Color glow, Color hair, Color skin})
    _racePal(String? race) => switch (race) {
          'yeu' => (
              a: const Color(0xFFC2703A), // áo nâu cam thổ
              b: const Color(0xFFE8A05C),
              c: const Color(0xFF5E3014),
              s: const Color(0xFF8A5A2E), // đai da
              glow: const Color(0xFFFFB566), // hổ phách
              hair: const Color(0xFF8A5430), // lông cáo
              skin: const Color(0xFFF1C27D),
            ),
          'ma' => (
              a: const Color(0xFF4A3260), // áo tím đen
              b: const Color(0xFF7B5496),
              c: const Color(0xFF1E1028),
              s: const Color(0xFFB02A37), // đai đỏ thẫm
              glow: const Color(0xFFFF4D5E), // mắt đỏ ma khí
              hair: const Color(0xFF1E1528),
              skin: const Color(0xFFE3C6BC), // da tái
            ),
          'linh' => (
              a: const Color(0xFFE7DFC9), // áo trắng ngà
              b: const Color(0xFFF4EEDD),
              c: const Color(0xFFA8946A),
              s: const Color(0xFFD4A017), // đai vàng
              glow: const Color(0xFFFFD166), // linh quang kim
              hair: const Color(0xFFE9E6F2), // tóc bạc
              skin: const Color(0xFFF6DCB5),
            ),
          _ => (
              a: const Color(0xFF3E63B0), // Nhân: áo thanh lam
              b: const Color(0xFF6E8FD6),
              c: const Color(0xFF1C2E52),
              s: const Color(0xFF2F9E77), // đai ngọc bích
              glow: const Color(0xFF5EEAD4), // ngọc lam
              hair: const Color(0xFF2A2438),
              skin: const Color(0xFFF1C27D),
            ),
        };

Color _mix(Color x, Color y, double t) => Color.lerp(x, y, t)!;

// ===== THỬ NGHIỆM: chibi pixel HD 64×64 (mắt to, shading, viền mềm) =====
// Mới dựng Nhân nam để duyệt style — duyệt xong mới nhân ra 4 tộc × 2 giới.
// Dựng bằng raster hoá hình khối vào grid + viền tự động, mắt đặt tay từng ô.

/// Mắt chibi 8×8: k viền/mi, i tròng, W highlight lớn, w highlight nhỏ.
const _chibiEye = [
  'kkkkkkk.',
  'kiWWiiik',
  'kiWWiiik',
  'kiiiiiik',
  'kiiiiiik',
  'kiiiiwik',
  '.kiiiik.',
  '..kkkk..',
];

void drawChibiCultivator(Canvas canvas, Rect rect, String? race, String? gender) {
  // ponytail: race/gender chưa dùng — bản duyệt chỉ có Nhân nam
  const n = 64;
  final g = List.generate(n, (_) => List<Color?>.filled(n, null)); // [y][x]

  const outline = Color(0xFF231C31);
  const skin = Color(0xFFF6D7A9), skinSh = Color(0xFFE0B183);
  const hair = Color(0xFF352A4E), hairLt = Color(0xFF52427A), hairDk = Color(0xFF241C36);
  const robe = Color(0xFF3E63B0);
  const robeDk = Color(0xFF2A4578), robeDk2 = Color(0xFF1D2C4E);
  const jade = Color(0xFF2F9E77), jadeLt = Color(0xFF55C79B);
  const iris = Color(0xFF544C7E); // tròng sáng hơn viền để mắt không thành hốc
  const silver = Color(0xFFC9CFDD);
  const white = Color(0xFFFFFFFF);

  void px(int x, int y, Color c) {
    if (x >= 0 && x < n && y >= 0 && y < n) g[y][x] = c;
  }

  void disk(double cx, double cy, double rx, double ry, Color c) {
    for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
      for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
        final dx = (x - cx) / rx, dy = (y - cy) / ry;
        if (dx * dx + dy * dy <= 1) px(x, y, c);
      }
    }
  }

  void rectF(int x0, int y0, int x1, int y1, Color c) {
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        px(x, y, c);
      }
    }
  }

  const cx = 32;

  // ---------- BÚI TÓC (trâm vẽ SAU pass viền — không thì bị nhuộm đen) ----------
  disk(32, 4.5, 4.5, 4, hair);
  disk(31, 3, 2.2, 1.6, hairLt); // lọn bắt sáng
  rectF(30, 8, 34, 9, hairDk); // dây buộc nối búi vào đầu

  // ---------- ĐẦU (mặt r~10, nhường chỗ cho thân) ----------
  disk(32, 18, 13.5, 12.5, hair); // khối tóc sau
  disk(32, 20, 11, 10, skin); // mặt
  // má hồng phấn nhẹ
  disk(24, 26, 1.6, 1.2, skinSh);
  disk(40, 26, 1.6, 1.2, skinSh);
  // mái xẻ lọn: giữa dài, xen kẽ lọn ngắn
  int bangY(int dx) => switch (dx.abs()) {
        <= 1 => 18,
        <= 4 => 15,
        <= 7 => 17,
        <= 10 => 14,
        _ => 18,
      };
  for (var x = cx - 12; x <= cx + 12; x++) {
    for (var y = 6; y <= bangY(x - cx); y++) {
      final ddx = (x - 32) / 13.5, ddy = (y - 18) / 12.5;
      if (ddx * ddx + ddy * ddy <= 1) px(x, y, hair);
    }
  }
  // tóc mai ôm mặt
  rectF(19, 16, 21, 28, hair);
  rectF(43, 16, 45, 28, hair);
  px(20, 29, hair);
  px(44, 29, hair);
  // lọn sáng trên mái
  rectF(25, 8, 30, 9, hairLt);
  rectF(36, 10, 39, 11, hairLt);
  // viền tối đáy mái (tách mái khỏi trán)
  for (var x = cx - 12; x <= cx + 12; x++) {
    final y = bangY(x - cx);
    if (g[y][x] == hair && g[y + 1][x] == skin) px(x, y, hairDk);
  }

  // ---------- MẮT TO (đặt tay từng ô) ----------
  void eye(int x0, int y0, {bool flip = false}) {
    for (var r = 0; r < _chibiEye.length; r++) {
      final row = _chibiEye[r];
      for (var c = 0; c < row.length; c++) {
        final ch = row[flip ? row.length - 1 - c : c];
        if (ch == '.') continue;
        px(x0 + c, y0 + r, switch (ch) {
          'k' => outline,
          'i' => iris,
          'W' => white,
          _ => const Color(0xFFD8D2E8), // w — highlight mờ
        });
      }
    }
  }

  // hai mắt cùng chiều highlight (nguồn sáng trên-trái, như mẫu)
  eye(21, 17);
  eye(35, 17);
  // mũi + miệng nhỏ
  px(33, 26, skinSh);
  rectF(31, 28, 32, 28, const Color(0xFFB4766A));

  // ---------- CỔ + THÂN NGỒI THIỀN (chiếm nửa dưới) ----------
  rectF(30, 30, 34, 33, skin);
  px(30, 30, skinSh);
  px(34, 30, skinSh);
  // thân: vai tròn → loe dần → đáy bo (ngồi xếp bằng)
  int half(int y) => switch (y) {
        31 => 7,
        32 => 10,
        33 => 12,
        <= 42 => 13,
        <= 52 => 13 + (y - 42), // loe tới 23
        <= 56 => 23,
        57 => 22,
        58 => 20,
        59 => 17,
        _ => 12,
      };
  for (var y = 31; y <= 60; y++) {
    rectF(cx - half(y), y, cx + half(y), y, robe);
  }
  // hai cột sẫm sát mép thân (khối tay áo rủ)
  for (var y = 34; y <= 56; y++) {
    rectF(cx - half(y), y, cx - half(y) + 2, y, robeDk);
    rectF(cx + half(y) - 2, y, cx + half(y), y, robeDk);
  }
  // giao lĩnh: hai nẹp trắng viền ngọc bắt chéo trước ngực (đối xứng)
  for (var y = 31; y <= 39; y++) {
    final w = ((y - 30) * 0.8).round().clamp(1, 7);
    px(cx - w - 1, y, jade);
    px(cx - w, y, white);
    px(cx - w + 1, y, white);
    px(cx + w + 1, y, jade);
    px(cx + w, y, white);
    px(cx + w - 1, y, white);
  }
  // đai ngọc + nút thắt
  rectF(cx - half(43) + 1, 43, cx + half(43) - 1, 43, jadeLt);
  rectF(cx - half(44) + 1, 44, cx + half(44) - 1, 45, jade);
  rectF(31, 43, 33, 45, jadeLt);
  // hai tay bắt ấn trong lòng (viền tối quanh tay để tách khỏi áo)
  rectF(28, 46, 36, 50, outline);
  rectF(29, 47, 35, 49, skin);
  rectF(29, 49, 35, 49, skinSh);
  // nếp gấp chân xếp bằng + hem tối
  rectF(cx - 18, 53, cx + 18, 53, robeDk);
  rectF(cx - 14, 56, cx - 11, 56, robeDk);
  rectF(cx + 11, 56, cx + 14, 56, robeDk);
  rectF(cx - half(58), 58, cx + half(58), 60, robeDk2);

  // ---------- VIỀN TỰ ĐỘNG: ô có cạnh chạm nền → tô màu viền ----------
  final edged = <(int, int)>[];
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (g[y][x] == null) continue;
      final bare = (y == 0 || g[y - 1][x] == null) ||
          (y == n - 1 || g[y + 1][x] == null) ||
          (x == 0 || g[y][x - 1] == null) ||
          (x == n - 1 || g[y][x + 1] == null);
      if (bare) edged.add((x, y));
    }
  }
  for (final (x, y) in edged) {
    g[y][x] = outline;
  }

  // ---------- CHI TIẾT MẢNH VẼ SAU PASS VIỀN ----------
  rectF(22, 4, 30, 5, silver); // trâm xuyên qua búi (đè lên mép búi)
  rectF(34, 4, 42, 5, silver);
  rectF(42, 4, 43, 5, jade); // ngọc đầu trâm

  // ---------- XUẤT RA CANVAS ----------
  final cell = rect.width / n;
  final oy = rect.bottom - n * cell;
  final paint = Paint();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final c = g[y][x];
      if (c == null) continue;
      paint.color = c;
      canvas.drawRect(
          Rect.fromLTWH(rect.left + x * cell, oy + y * cell, cell + 0.5, cell + 0.5),
          paint);
    }
  }
}

/// Vẽ nhân vật vào [rect] (tỷ lệ đẹp nhất khi rect cao ≈ 1.06 × rộng):
/// căn giữa ngang, ĐÁY hình chạm đáy rect — đặt đáy rect lên mặt chỗ ngồi.
void drawCultivator(Canvas canvas, Rect rect, String? race, String? gender) {
  final pal = _racePal(race);
  final nu = gender == 'nu';
  canvas.save();
  canvas.translate(rect.left, rect.top);
  final k = rect.width / 100;
  canvas.scale(k, k); // thiết kế trong không gian 100 × ~106

  const cx = 50.0;
  final shoulder = nu ? 15.5 : 18.5; // nửa vai
  final base = nu ? 28.0 : 31.0; // nửa đáy vạt áo (ngồi xếp bằng)
  final fill = Paint()..isAntiAlias = true;
  final line = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // ---------- SAU LƯNG: đuôi cáo / vòng linh quang ----------
  if (race == 'yeu') {
    // đuôi cong chữ S vươn lên bên phải, chóp trắng
    final tail = Path()
      ..moveTo(60, 97)
      ..cubicTo(90, 91, 95, 62, 81, 48)
      ..cubicTo(74, 41, 63, 43, 62, 51)
      ..cubicTo(71, 51, 79, 61, 73, 73)
      ..cubicTo(69, 84, 64, 91, 55, 95)
      ..close();
    fill.shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [pal.hair, _mix(pal.hair, pal.b, 0.6)],
    ).createShader(const Rect.fromLTWH(55, 40, 40, 60));
    canvas.drawPath(tail, fill);
    fill.shader = null;
    // chóp đuôi trắng
    canvas.drawPath(
        Path()
          ..moveTo(81, 48)
          ..cubicTo(74, 41, 63, 43, 62, 51)
          ..cubicTo(68, 50, 76, 52, 79, 57)
          ..close(),
        fill..color = const Color(0xFFF6F1E7));
  }
  if (race == 'linh') {
    // vòng linh quang lơ lửng trên đầu, có quầng
    final halo = Rect.fromCenter(
        center: const Offset(cx, 3.5), width: 23, height: 6.5);
    canvas.drawOval(
        halo,
        line
          ..strokeWidth = 3.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
          ..color = pal.glow.withValues(alpha: 0.55));
    canvas.drawOval(
        halo,
        line
          ..strokeWidth = 1.4
          ..maskFilter = null
          ..color = pal.glow);
  }

  // ---------- THÂN: một khối silhouette, gradient dọc màu tộc ----------
  final body = Path()
    ..moveTo(cx - base, 97)
    ..quadraticBezierTo(cx, 105, cx + base, 97) // đáy bo tròn
    // sườn phải: thắt eo rồi vồng lên vai
    ..cubicTo(cx + base - 2, 76, cx + shoulder + 2, 58, cx + shoulder, 42)
    ..quadraticBezierTo(cx + shoulder - 1, 34.5, cx + 5, 32.5)
    ..lineTo(cx - 5, 32.5) // hõm cổ
    ..quadraticBezierTo(cx - shoulder + 1, 34.5, cx - shoulder, 42)
    ..cubicTo(cx - shoulder - 2, 58, cx - base + 2, 76, cx - base, 97)
    ..close();
  fill.shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [pal.b, pal.a, pal.c],
    stops: const [0, 0.4, 1],
  ).createShader(const Rect.fromLTWH(0, 32, 100, 74));
  canvas.drawPath(body, fill);
  fill.shader = null;

  // viền tà áo sáng chạy dọc đáy (nẹp thêu)
  canvas.drawPath(
      Path()
        ..moveTo(cx - base + 3, 95.5)
        ..quadraticBezierTo(cx, 102.5, cx + base - 3, 95.5),
      line
        ..strokeWidth = 2.2
        ..color = pal.b.withValues(alpha: 0.5));

  // cổ áo chữ V lộ lớp trong sáng, viền màu đai
  canvas.drawPath(
      Path()
        ..moveTo(cx - 5.5, 32.5)
        ..lineTo(cx, 47)
        ..lineTo(cx + 5.5, 32.5)
        ..close(),
      fill..color = _mix(pal.b, Colors.white, 0.5));
  line
    ..strokeWidth = 1.2
    ..color = pal.s.withValues(alpha: 0.85);
  canvas.drawLine(const Offset(cx - 5.5, 32.5), const Offset(cx, 47), line);
  canvas.drawLine(const Offset(cx + 5.5, 32.5), const Offset(cx, 47), line);

  // tay áo rộng khoanh trước ngực: lớp vải sẫm chụm về giữa (bắt ấn)
  final sleeves = Path()
    ..moveTo(cx - shoulder + 1, 44)
    ..cubicTo(cx - shoulder - 5, 56, cx - 17, 69, cx - 5.5, 71.5)
    ..quadraticBezierTo(cx, 73.5, cx + 5.5, 71.5)
    ..cubicTo(cx + 17, 69, cx + shoulder + 5, 56, cx + shoulder - 1, 44)
    ..quadraticBezierTo(cx + 10, 56, cx, 56.5)
    ..quadraticBezierTo(cx - 10, 56, cx - shoulder + 1, 44)
    ..close();
  fill.shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_mix(pal.a, pal.c, 0.45), _mix(pal.c, pal.a, 0.15)],
  ).createShader(const Rect.fromLTWH(0, 44, 100, 30));
  canvas.drawPath(sleeves, fill);
  fill.shader = null;
  // mép tay áo bắt sáng
  canvas.drawPath(
      Path()
        ..moveTo(cx - 16, 68)
        ..quadraticBezierTo(cx, 74.5, cx + 16, 68),
      line
        ..strokeWidth = 1.1
        ..color = pal.b.withValues(alpha: 0.6));

  // đai lưng phát sáng + nút thắt (trên mép tay áo)
  final sash = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: const Offset(cx, 60.5),
          width: (shoulder + 2.5) * 2,
          height: 3.4),
      const Radius.circular(2));
  canvas.drawRRect(
      sash,
      Paint()
        ..isAntiAlias = true
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..color = pal.glow.withValues(alpha: 0.4));
  canvas.drawRRect(sash, fill..color = pal.s);
  canvas.drawCircle(
      const Offset(cx, 60.5), 1.8, fill..color = _mix(pal.s, Colors.white, 0.35));

  // lõi đan điền lơ lửng giữa hai tay — "pin năng lượng" của nhân vật
  canvas.drawCircle(
      const Offset(cx, 70.5),
      6.5,
      Paint()
        ..isAntiAlias = true
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = pal.glow.withValues(alpha: 0.6));
  canvas.drawCircle(const Offset(cx, 70.5), 2.4,
      fill..color = _mix(pal.glow, Colors.white, 0.65));

  // viền sáng vành phải (bắt trăng)
  line
    ..strokeWidth = 1.2
    ..color = Colors.white.withValues(alpha: 0.5);
  canvas.drawPath(
      Path()
        ..moveTo(cx + shoulder - 0.5, 43)
        ..cubicTo(cx + shoulder + 1.5, 58, cx + base - 2.5, 76, cx + base - 0.8, 95),
      line);

  // ---------- ĐẦU (r 9.2 — thanh thoát hơn, bớt chibi) ----------
  const headC = Offset(cx, 20.5);
  // cổ
  canvas.drawRect(Rect.fromLTRB(cx - 3, 26, cx + 3, 33.5),
      fill..color = _mix(pal.skin, pal.c, 0.25));
  // mặt
  fill.shader = RadialGradient(
    center: const Alignment(-0.3, -0.4),
    colors: [_mix(pal.skin, Colors.white, 0.18), pal.skin],
  ).createShader(Rect.fromCircle(center: headC, radius: 9.2));
  canvas.drawCircle(headC, 9.2, fill);
  fill.shader = null;
  // tai nhọn Linh tộc (chĩa ngang, màu da)
  if (race == 'linh') {
    for (final d in [-1.0, 1.0]) {
      canvas.drawPath(
          Path()
            ..moveTo(cx + d * 8.3, 19.5)
            ..lineTo(cx + d * 14, 16.5)
            ..lineTo(cx + d * 7.7, 23.5)
            ..close(),
          fill..color = pal.skin);
    }
  }
  // sừng Ma tộc: bản dày mọc từ thái dương, cong ra ngoài như sừng bò
  // (vẽ trước tóc để chân sừng lẩn dưới tóc)
  if (race == 'ma') {
    for (final d in [-1.0, 1.0]) {
      final horn = Path()
        ..moveTo(cx + d * 4, 14)
        ..cubicTo(cx + d * 13, 12.5, cx + d * 19, 7, cx + d * 18.5, -1)
        ..cubicTo(cx + d * 17.5, 4.5, cx + d * 12, 9.5, cx + d * 9, 16.5)
        ..close();
      fill.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [const Color(0xFF9E9077), const Color(0xFFEDE4D3)],
      ).createShader(const Rect.fromLTWH(30, 0, 40, 16));
      canvas.drawPath(horn, fill);
      fill.shader = null;
    }
  }

  // ---------- TÓC ----------
  final hairLight = _mix(pal.hair, Colors.white, 0.22);
  fill.shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [hairLight, pal.hair],
  ).createShader(const Rect.fromLTWH(35, 7, 30, 16));
  // vòm tóc ôm đỉnh đầu, mái chữ M
  canvas.drawPath(
      Path()
        ..moveTo(cx - 9.5, 21)
        ..cubicTo(cx - 9.2, 8.8, cx + 9.2, 8.8, cx + 9.5, 21)
        ..quadraticBezierTo(cx + 6, 14.6, cx + 2.6, 15.3)
        ..quadraticBezierTo(cx, 17.6, cx - 2.6, 15.3)
        ..quadraticBezierTo(cx - 6, 14.6, cx - 9.5, 21)
        ..close(),
      fill);
  fill.shader = null;
  // tóc dài xõa hai bên: nữ dài chấm gối, Linh nam cũng để dài vừa
  final strandLen = nu ? 90.0 : (race == 'linh' ? 58.0 : 0.0);
  if (strandLen > 0) {
    for (final d in [-1.0, 1.0]) {
      canvas.drawPath(
          Path()
            ..moveTo(cx + d * 8.3, 16.5)
            ..cubicTo(cx + d * 14, 33, cx + d * 16, 58, cx + d * 22, strandLen)
            ..quadraticBezierTo(
                cx + d * 18, strandLen + 2, cx + d * 16.5, strandLen - 2)
            ..cubicTo(cx + d * 12, 60, cx + d * 10.5, 38, cx + d * 6.5, 22)
            ..close(),
          fill..color = pal.hair);
    }
  }
  // vệt bóng tóc
  canvas.drawPath(
      Path()
        ..moveTo(cx - 6.5, 11.5)
        ..quadraticBezierTo(cx - 1.5, 9.2, cx + 3.5, 10),
      line
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.3));

  // kiểu tóc + phụ kiện theo tộc
  switch (race) {
    case 'yeu': // tai cáo trên đỉnh, lòng tai sáng
      for (final d in [-1.0, 1.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(cx + d * 2.8, 11.5)
              ..lineTo(cx + d * 10.5, 0)
              ..lineTo(cx + d * 9, 13)
              ..close(),
            fill..color = pal.hair);
        canvas.drawPath(
            Path()
              ..moveTo(cx + d * 4.8, 10)
              ..lineTo(cx + d * 9.4, 3)
              ..lineTo(cx + d * 8.4, 11.2)
              ..close(),
            fill..color = _mix(pal.skin, Colors.white, 0.35));
      }
    case 'ma': // đầu trần khoe sừng — thêm vệt tóc vuốt ngược
      canvas.drawPath(
          Path()
            ..moveTo(cx - 3.5, 10.5)
            ..quadraticBezierTo(cx, 7.8, cx + 3.5, 10.5)
            ..quadraticBezierTo(cx, 9.5, cx - 3.5, 10.5)
            ..close(),
          fill..color = hairLight);
    case 'linh': // không búi — tóc bạc + vòng quang đã đủ nhận diện
      break;
    default: // Nhân: búi tóc + trâm cài (nam ngang bạc · nữ chếch + ngọc)
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, nu ? 8.2 : 7.6),
              width: nu ? 7.0 : 7.8,
              height: nu ? 6.4 : 8.2),
          fill..color = pal.hair);
      line
        ..strokeWidth = 1.3
        ..color = const Color(0xFFC6CCDA);
      if (nu) {
        canvas.drawLine(const Offset(cx - 4, 6.2), const Offset(cx + 6.5, 10), line);
        canvas.drawCircle(const Offset(cx + 7.2, 10.5), 1.4,
            fill..color = pal.s); // ngọc bội đầu trâm
      } else {
        // trâm chếch nhẹ xuyên qua búi
        canvas.drawLine(const Offset(cx - 5, 8.6), const Offset(cx + 5, 6.6), line);
      }
  }

  // ---------- MẮT NHẮM PHÁT SÁNG (thiền định) ----------
  for (final d in [-1.0, 1.0]) {
    final eye = Path()
      ..moveTo(cx + d * 5.8, 22.3)
      ..quadraticBezierTo(cx + d * 4.2, 23.5, cx + d * 2.6, 22.5);
    canvas.drawPath(
        eye,
        line
          ..strokeWidth = 1.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7)
          ..color = pal.glow.withValues(alpha: 0.3));
    canvas.drawPath(
        eye,
        line
          ..strokeWidth = 0.9
          ..maskFilter = null
          ..color = _mix(pal.glow, Colors.white, 0.25));
  }
  // viền sáng má phải
  canvas.drawArc(
      Rect.fromCircle(center: headC, radius: 8.8),
      -0.9,
      1.5,
      false,
      line
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.4));

  canvas.restore();
}

// ===== Nhân vật PIXEL đơn giản hoá — đồng bộ khối với sprite vật phẩm 12×12 =====
// Sprite 24×26, cùng convention màu k/w/h/f/A/B/C như _sprites phía trên (khối
// vuông sắc cạnh, không bo mượt) — khác hẳn vector "linh thể" mềm ở trên.
// ĐỨNG thẳng, full body (đầu/vai/tay giữ nguyên khung gốc, chỉ đổi vạt áo +
// chân cho đứng thay vì ngồi kiết già).

String _rep(String ch, int n) => List.filled(n, ch).join();

/// Hàng đối xứng 24 cột: dấu chấm | k | [mid] | k | dấu chấm, luôn ra đúng
/// 24 ký tự bất kể độ dài [mid] — tránh đếm tay sai lệch hàng.
String _sym(String mid) {
  final total = 22 - mid.length;
  final left = total ~/ 2, right = total - left;
  return '${_rep('.', left)}k$mid' 'k${_rep('.', right)}';
}

final _cultBase = <String>[
  '........................', //  0
  '...........hh...........', //  1 búi tóc
  '..........hhhh..........', //  2
  '.......zzzhhhhzzz.......', //  3 trâm cài ngang
  '........kkkkkkkk........', //  4 đỉnh đầu
  '.......khhhhhhhhk.......', //  5
  '......khhhhhhhhhhk......', //  6
  '......khhffffffhhk......', //  7 mái tóc ôm mặt
  '......khfeffffefhk......', //  8 mắt
  '......khffffffffhk......', //  9
  '.......kffffffffk.......', // 10
  '........kffffffk........', // 11 cằm
  '..........kffk..........', // 12 cổ
  '......kkAAAAAAAAkk......', // 13 vai
  '.....kAAABwwwwBAAAk.....', // 14 cổ áo chéo lộ lớp trong
  '.....kAAAABwwBAAAAk.....', // 15
  '....kAAAAABwwBAAAAAk....', // 16
  '....kASSSSSSSSSSSSAk....', // 17 đai lưng
  '....kAAAAAffffAAAAAk....', // 18 tay bắt ấn trước bụng
  '...kAAAAAAffffAAAAAAk...', // 19
  // ---- áo dài đứng thẳng: nhiều hàng hơn hẳn bản ngồi để chân có tỉ lệ ----
  _sym(_rep('A', 14)), // 20 nối từ eo, hơi thon
  _sym(_rep('A', 13)), // 21
  _sym('${_rep('A', 5)}${_rep('B', 2)}${_rep('A', 5)}'), // 22 nếp gấp sáng
  _sym(_rep('A', 12)), // 23 thân áo dài
  _sym(_rep('A', 12)), // 24
  _sym('${_rep('A', 5)}${_rep('B', 2)}${_rep('A', 5)}'), // 25 nếp gấp sáng
  _sym(_rep('A', 12)), // 26
  _sym(_rep('A', 11)), // 27 bắt đầu thon về gấu áo
  _sym('${_rep('A', 4)}k${_rep('A', 4)}'), // 28 gấu áo hé mở, tách chân
  _sym('${_rep('A', 4)}k${_rep('A', 4)}'), // 29
  _sym('${_rep('A', 3)}k${_rep('A', 3)}'), // 30 sát mắt cá
  _sym('${_rep('y', 3)}..${_rep('y', 3)}'), // 31 hài, hai chân đứng tách rõ
  _rep('.', 24), // 32
  _rep('.', 24), // 33
];

/// Grid theo tộc + giới tính: nền chung + thay hàng đặc trưng (đầu/tóc/đuôi),
/// nữ poke thêm tóc dài xoã 2 bên sát viền vai/thân.
List<String> cultivatorGridPixel(String? race, String? gender) {
  final g = List<String>.of(_cultBase);
  switch (race) {
    case 'yeu': // tai cáo lộ da trong, đầu trần + đuôi cong nhô bên phải hông
      g[1] = '.......hh......hh.......';
      g[2] = '.......hhh....hhh.......';
      g[3] = '.......hfhh..hhfh.......';
      g[17] = '....kASSSSSSSSSSSSAk.B..';
      g[18] = '....kAAAAAffffAAAAAk.BB.';
      g[19] = '...kAAAAAAffffAAAAAAk.B.';
    case 'ma': // hai sừng xương cong ra ngoài, đầu trần
      g[1] = '.....y............y.....';
      g[2] = '.....yy..........yy.....';
      g[3] = '......yy........yy......';
      g[4] = '......yykkkkkkkkyy......';
    case 'linh': // vòng linh quang lơ lửng + tóc dài xõa qua vai
      g[0] = '.........SSSSSS.........';
      g[1] = '........S......S........';
      g[2] = '.........SSSSSS.........';
      g[3] = '..........hhhh..........';
      g[13] = '.....hkkAAAAAAAAkkh.....';
      g[14] = '....hkAAABwwwwBAAAkh....';
      g[15] = '....hkAAAABwwBAAAAkh....';
      g[16] = '...hkAAAAABwwBAAAAAkh...';
  }
  if (gender == 'nu') {
    for (final y in [15, 17, 19, 21, 24, 27]) {
      final chars = g[y].split('');
      if (chars[1] == '.') chars[1] = 'h';
      if (chars[chars.length - 2] == '.') chars[chars.length - 2] = 'h';
      g[y] = chars.join();
    }
  }
  return g;
}

/// Palette giới hạn theo tộc, riêng cho sprite pixel (khác record của vector).
({Color a, Color b, Color c, Color s, Color hair, Color eye, Color skin})
    pixelRacePal(String? race) => switch (race) {
          'yeu' => (
              a: const Color(0xFFC2703A),
              b: const Color(0xFFE8A05C),
              c: const Color(0xFF8A4A22),
              s: const Color(0xFF5C3A1E),
              hair: const Color(0xFF7A4A26),
              eye: const Color(0xFF241F31),
              skin: const Color(0xFFF1C27D),
            ),
          'ma' => (
              a: const Color(0xFF463058),
              b: const Color(0xFF6E4A85),
              c: const Color(0xFF2A1836),
              s: const Color(0xFFB02A37),
              hair: const Color(0xFF231A2F),
              eye: const Color(0xFFE03131),
              skin: const Color(0xFFE0C2B8),
            ),
          'linh' => (
              a: const Color(0xFFE4DCC8),
              b: const Color(0xFFE9C46A),
              c: const Color(0xFFB8A888),
              s: const Color(0xFFD4A017),
              hair: const Color(0xFFE8E4F0),
              eye: const Color(0xFF3BC9DB),
              skin: const Color(0xFFF6DCB5),
            ),
          _ => (
              a: const Color(0xFF3E63B0),
              b: const Color(0xFF6E8FD6),
              c: const Color(0xFF2A4578),
              s: const Color(0xFF2F9E77),
              hair: const Color(0xFF2E2A3B),
              eye: const Color(0xFF241F31),
              skin: const Color(0xFFF1C27D),
            ),
        };

/// Vẽ nhân vật pixel vào [rect]: căn giữa ngang, ĐÁY sprite chạm đáy rect.
void drawCultivatorPixel(Canvas canvas, Rect rect, String? race, String? gender) {
  final grid = cultivatorGridPixel(race, gender);
  final pal = pixelRacePal(race);
  final cell = rect.width / grid[0].length;
  final oy = rect.bottom - grid.length * cell;
  final paint = Paint();
  for (var y = 0; y < grid.length; y++) {
    final row = grid[y];
    for (var x = 0; x < row.length; x++) {
      final ch = row[x];
      if (ch == '.') continue;
      paint.color = switch (ch) {
        'k' => const Color(0xFF241F31),
        'w' => const Color(0xFFF6F4EF),
        'y' => const Color(0xFFCBB9A0),
        'z' => const Color(0xFFC6CCDA),
        'A' => pal.a,
        'B' => pal.b,
        'C' => pal.c,
        'S' => pal.s,
        'h' => pal.hair,
        'e' => pal.eye,
        'f' => pal.skin,
        _ => const Color(0x00000000),
      };
      canvas.drawRect(
          Rect.fromLTWH(rect.left + x * cell, oy + y * cell, cell + 0.5, cell + 0.5),
          paint);
    }
  }
}

/// Vẽ 1 sprite vật phẩm (đã có trong [_sprites]) tại toạ độ bất kỳ trên canvas
/// — dùng cho vũ khí ĐANG ĐEO bay quanh người, không phải icon trong danh sách.
void paintOrbitSprite(Canvas canvas, Offset center, double cellSize, String spriteKey, int grade,
    {double opacity = 1}) {
  final grid = _sprites[spriteKey] ?? _sprites['sword']!;
  final g = _grades[(grade - 1).clamp(0, 4)];
  final cols = grid[0].length, rows = grid.length;
  final ox = center.dx - cols * cellSize / 2;
  final oy = center.dy - rows * cellSize / 2;
  final paint = Paint();
  for (var y = 0; y < rows; y++) {
    final row = grid[y];
    for (var x = 0; x < row.length; x++) {
      final ch = row[x];
      if (ch == '.') continue;
      paint.color = switch (ch) {
        'k' => const Color(0xFF2E2A3B),
        'w' => const Color(0xFFF6F4EF),
        'x' => const Color(0xFF9C6B3C),
        'y' => const Color(0xFF8B93A6),
        'z' => const Color(0xFFC6CCDA),
        'r' => const Color(0xFFE03131),
        'A' => g.a,
        'B' => g.b,
        'C' => g.c,
        _ => const Color(0x00000000),
      }
          .withValues(alpha: opacity);
      canvas.drawRect(
          Rect.fromLTWH(ox + x * cellSize, oy + y * cellSize, cellSize + 0.5, cellSize + 0.5),
          paint);
    }
  }
}

// ===== Nhân vật CHIBI kiểu Guardian Tales × MapleStory =====
// Đầu to tròn (~45% chiều cao), MẮT TO long lanh mở, thân nhỏ đứng, hanfu tay
// áo loe, viền pixel + cel-shading 2 tông. Raster hoá hình khối vào grid rồi
// tự sinh viền — nét vẫn "pixel" đồng bộ vật phẩm nhưng mặt dễ thương đọc được.
// drawChibiHero(canvas, rect, race, gender): rect nên cao ≈ 1.3× rộng.

typedef _ChibiPal = ({
  Color robe, Color robeLt, Color robeDk, // áo
  Color sash, Color sashLt, // đai
  Color hair, Color hairLt, // tóc
  Color skin, Color skinSh, // da
  Color iris, Color accent, Color trim, // mắt · linh khí · viền sáng
});

_ChibiPal _chibiPal(String? race) => switch (race) {
      'yeu' => (
          robe: const Color(0xFFCE8A4A), robeLt: const Color(0xFFEDB472), robeDk: const Color(0xFF8A5424),
          sash: const Color(0xFF6E4A28), sashLt: const Color(0xFFAD814C),
          hair: const Color(0xFFEDE3CC), hairLt: const Color(0xFFFAF4E4), // tóc bạch hồ
          skin: const Color(0xFFF6D7A9), skinSh: const Color(0xFFE0B183),
          iris: const Color(0xFFC97E2E), accent: const Color(0xFFFFB566), trim: const Color(0xFFFFF3DE),
        ),
      'ma' => (
          robe: const Color(0xFF4A3462), robeLt: const Color(0xFF6E4E90), robeDk: const Color(0xFF261636),
          sash: const Color(0xFFB02A37), sashLt: const Color(0xFFE0555F),
          hair: const Color(0xFF2A2036), hairLt: const Color(0xFF4A3A5E),
          skin: const Color(0xFFE7CCC4), skinSh: const Color(0xFFD0AAA0),
          iris: const Color(0xFFE83A46), accent: const Color(0xFFFF4D5E), trim: const Color(0xFFFFC0C6),
        ),
      'linh' => (
          robe: const Color(0xFFEDE6D2), robeLt: const Color(0xFFFAF6EA), robeDk: const Color(0xFFBFB08C),
          sash: const Color(0xFFD4A017), sashLt: const Color(0xFFF2CE5C),
          hair: const Color(0xFFE9E5F0), hairLt: const Color(0xFFFFFFFF), // tóc bạc
          skin: const Color(0xFFF6DCB5), skinSh: const Color(0xFFE6C295),
          iris: const Color(0xFF39B9CC), accent: const Color(0xFFFFD166), trim: const Color(0xFFFFF0C4),
        ),
      _ => (
          robe: const Color(0xFF3E63B0), robeLt: const Color(0xFF6E8FD6), robeDk: const Color(0xFF27406F),
          sash: const Color(0xFF2F9E77), sashLt: const Color(0xFF62CCA0),
          hair: const Color(0xFF322C42), hairLt: const Color(0xFF544C6E),
          skin: const Color(0xFFF6D7A9), skinSh: const Color(0xFFE0B183),
          iris: const Color(0xFF4C74C8), accent: const Color(0xFF5EEAD4), trim: const Color(0xFFFFFFFF),
        ),
    };

void drawChibiHero(Canvas canvas, Rect rect, String? race, String? gender) {
  const cols = 40, rows = 52;
  const cx = 20.0;
  final nu = gender == 'nu';
  final pal = _chibiPal(race);
  const outline = Color(0xFF231C31);
  final longHair = nu || race == 'linh' || race == 'yeu';
  final g = List.generate(rows, (_) => List<Color?>.filled(cols, null));

  void px(int x, int y, Color c) {
    if (x >= 0 && x < cols && y >= 0 && y < rows) g[y][x] = c;
  }

  void disk(double dcx, double dcy, double rx, double ry, Color c) {
    for (var y = (dcy - ry).floor(); y <= (dcy + ry).ceil(); y++) {
      for (var x = (dcx - rx).floor(); x <= (dcx + rx).ceil(); x++) {
        final dx = (x - dcx) / rx, dy = (y - dcy) / ry;
        if (dx * dx + dy * dy <= 1) px(x, y, c);
      }
    }
  }

  void rectF(int x0, int y0, int x1, int y1, Color c) {
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        px(x, y, c);
      }
    }
  }

  // ---------- BACK LAYER: tóc dài + đuôi cáo (vẽ trước, thân đè lên) ----------
  if (longHair) {
    for (final d in [-1.0, 1.0]) {
      // suối tóc buông hai bên má xuống quá vai
      disk(cx + d * 9.5, 24, 3.5, 12, pal.hair);
      disk(cx + d * 9, 33, 3.0, 7, pal.hair);
      px((cx + d * 9).round(), 40, pal.hair);
    }
  }
  if (race == 'yeu') {
    // đuôi cáo phồng vắt bên phải hông, chóp sáng
    disk(31, 40, 5, 8, pal.hair);
    disk(33, 34, 3.5, 5, pal.hair);
    disk(34, 30, 2.4, 3, pal.hairLt);
  }

  // ---------- KHỐI TÓC SAU + MẶT ----------
  disk(cx, 15, 13.5, 13, pal.hair); // vòm tóc bao quanh đầu
  disk(cx, 17, 11, 11, pal.skin); // mặt

  // ---------- SỪNG (ma) / TAI (yeu, linh): trước outline để có viền ----------
  if (race == 'ma') {
    for (final d in [-1.0, 1.0]) {
      disk(cx + d * 8, 6, 2.2, 4.5, const Color(0xFFCBB9A0)); // sừng xương
      disk(cx + d * 10.5, 2.5, 1.6, 3, const Color(0xFFCBB9A0));
      disk(cx + d * 12, 0, 1.2, 2, const Color(0xFFE6DAC2)); // chóp sáng
    }
  }
  if (race == 'yeu') {
    for (final d in [-1.0, 1.0]) {
      // tai cáo lớn dựng chếch
      for (var i = 0; i < 8; i++) {
        final w = 4 - i * 0.45;
        disk(cx + d * (7.5 + i * 0.8), 6.0 - i * 1.1, w.clamp(0.6, 4), w.clamp(0.6, 4), pal.hair);
      }
      disk(cx + d * 8.5, 3.5, 1.6, 2.4, const Color(0xFFE9B7C4)); // lòng tai hồng
    }
  }
  if (race == 'linh') {
    for (final d in [-1.0, 1.0]) {
      // tai nhọn tiên tộc chĩa ngang
      disk(cx + d * 11, 16, 1.6, 2.4, pal.skin);
      px((cx + d * 13).round(), 15, pal.skin);
    }
  }

  // ---------- TÓC TRƯỚC: mái chữ M + tóc mai ôm mặt ----------
  int bangBottom(int dx) => switch (dx.abs()) {
        <= 2 => 15, // rẽ ngôi giữa dài xuống
        <= 5 => 11,
        <= 8 => 14,
        <= 11 => 12,
        _ => 16,
      };
  for (var x = (cx - 12).round(); x <= (cx + 12).round(); x++) {
    for (var y = 2; y <= bangBottom(x - cx.round()); y++) {
      final dx = (x - cx) / 13.5, dy = (y - 15) / 13;
      if (dx * dx + dy * dy <= 1) px(x, y, pal.hair);
    }
  }
  // tóc mai hai bên ôm tới quai hàm
  for (final d in [-1.0, 1.0]) {
    disk(cx + d * 10, 18, 2.2, 6, pal.hair);
  }

  // búi tóc (nhan) — thêm trên đỉnh
  if (race == null || race == 'nhan') {
    disk(cx, 3.5, 3.2, 3, pal.hair);
    disk(cx - 1, 2.2, 1.4, 1.2, pal.hairLt);
  }

  // ---------- THÂN NGƯỜI ĐỨNG (hanfu) ----------
  // cổ
  rectF((cx - 2).round(), 26, (cx + 2).round(), 28, pal.skin);
  // nửa rộng thân theo hàng
  double hw(int y) {
    if (y <= 29) return 5 + (y - 28) * 2.0; // vai loe
    if (y <= 35) return nu ? 6.5 : 7.5; // eo
    return (nu ? 6.5 : 7.5) + (y - 35) * 0.62; // loe xuống gấu
  }

  for (var y = 28; y <= 46; y++) {
    final h = hw(y).round();
    rectF((cx - h).round(), y, (cx + h).round(), y, pal.robe);
  }
  // tay áo loe hình chuông hai bên
  for (final d in [-1.0, 1.0]) {
    disk(cx + d * 10.5, 34, 4.2, 6.5, pal.robe);
    disk(cx + d * 10, 40, 2.2, 2.2, pal.skin); // bàn tay ló khỏi tay áo
  }
  // hài
  rectF((cx - 5).round(), 47, (cx - 1).round(), 48, outline);
  rectF((cx + 1).round(), 47, (cx + 5).round(), 48, outline);

  // cel-shading áo: highlight trái + shadow phải
  for (var y = 30; y <= 45; y++) {
    final h = hw(y).round();
    px((cx - h + 1).round(), y, pal.robeLt);
    px((cx + h - 1).round(), y, pal.robeDk);
    px((cx + h).round(), y, pal.robeDk);
  }

  // ---------- PASS VIỀN: ô chạm nền → outline ----------
  final edge = <(int, int)>[];
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if (g[y][x] == null) continue;
      final bare = (y == 0 || g[y - 1][x] == null) ||
          (y == rows - 1 || g[y + 1][x] == null) ||
          (x == 0 || g[y][x - 1] == null) ||
          (x == cols - 1 || g[y][x + 1] == null);
      if (bare) edge.add((x, y));
    }
  }
  for (final (x, y) in edge) {
    g[y][x] = outline;
  }

  // ---------- CHI TIẾT trên cùng (không outline) ----------
  // cổ áo giao lĩnh trắng chữ V
  for (var y = 28; y <= 34; y++) {
    final w = ((y - 27) * 0.7).round().clamp(1, 5);
    px((cx - w).round(), y, pal.trim);
    px((cx - w + 1).round(), y, pal.trim);
    px((cx + w).round(), y, pal.trim);
    px((cx + w - 1).round(), y, pal.trim);
  }
  // đai lưng + nút
  rectF((cx - hw(35)).round() + 1, 35, (cx + hw(35)).round() - 1, 36, pal.sash);
  rectF((cx - hw(34)).round() + 1, 34, (cx + hw(34)).round() - 1, 34, pal.sashLt);
  rectF((cx - 1).round(), 35, (cx + 1).round(), 38, pal.sash); // dải đai rủ

  // MẮT TO long lanh (MapleStory/GT): tròng lớn + 2 vệt sáng
  void eye(double ex) {
    final iris = race == 'ma' ? pal.iris : pal.iris;
    disk(ex, 19.5, 2.2, 3.0, outline); // khung mi
    disk(ex, 20, 1.5, 2.3, iris); // tròng
    disk(ex, 21, 1.2, 1.4, _mix(iris, Colors.black, 0.35)); // đáy tròng sẫm
    px((ex - 1).round(), 18, Colors.white); // bóng sáng lớn
    px(ex.round(), 18, Colors.white);
    px((ex + 1).round(), 21, const Color(0xFFCFE8FF)); // đốm sáng nhỏ dưới
  }

  eye(cx - 5);
  eye(cx + 5);
  // lông mày mảnh
  rectF((cx - 7).round(), 15, (cx - 4).round(), 15, pal.hair);
  rectF((cx + 4).round(), 15, (cx + 7).round(), 15, pal.hair);
  // má hồng + mũi + miệng cười
  disk(cx - 8, 22.5, 1.6, 1.1, const Color(0x66FF8FA3));
  disk(cx + 8, 22.5, 1.6, 1.1, const Color(0x66FF8FA3));
  px(cx.round(), 22, pal.skinSh);
  rectF((cx - 1).round(), 24, cx.round(), 24, const Color(0xFFB56A5E));

  // tóc: vệt highlight vòm
  for (var x = (cx - 7).round(); x <= (cx + 3).round(); x++) {
    if (g[8][x] == pal.hair) px(x, 8, pal.hairLt);
  }

  // trâm bạc (nhan) xuyên búi
  if (race == null || race == 'nhan') {
    rectF((cx - 4).round(), 3, (cx + 4).round(), 3, const Color(0xFFC9CFDD));
    px((cx + 5).round(), 3, pal.sash);
  }

  // vòng linh quang (linh) lơ lửng — vẽ đè cả tóc
  if (race == 'linh') {
    for (var x = (cx - 9).round(); x <= (cx + 9).round(); x++) {
      final onRing = ((x - cx) / 9).abs();
      final y = (-2 + onRing * onRing * 3).round();
      if (y >= 0) px(x, y, pal.accent);
      if (y - 1 >= 0) px(x, y - 1, pal.accent.withValues(alpha: 0.5));
    }
  }

  // ---------- XUẤT: fit rect giữ tỉ lệ, đáy chạm đáy rect ----------
  final cell = (rect.width / cols < rect.height / rows) ? rect.width / cols : rect.height / rows;
  final ox = rect.left + (rect.width - cols * cell) / 2;
  final oy = rect.bottom - rows * cell;
  final paint = Paint();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final c = g[y][x];
      if (c == null) continue;
      paint.color = c;
      canvas.drawRect(
          Rect.fromLTWH(ox + x * cell, oy + y * cell, cell + 0.5, cell + 0.5), paint);
    }
  }
}
