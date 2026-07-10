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
  // vòng sáng (pháp bảo halo — Nguyệt/Tinh/Lôi/Kim Hoàn)
  'halo': [
    '............',
    '...kkkkkk...',
    '..kBwBBBBk..',
    '.kBwk..kBBk.',
    '.kwk....kBk.',
    '.kBk....kAk.',
    '.kBk....kAk.',
    '.kBAk..kAAk.',
    '..kBAAAAAk..',
    '...kkkkkk...',
    '............',
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

/// Icon vật phẩm minh hoạ riêng; fallback pixel giữ được catalog cũ nếu server trả key lạ.
class PixelIcon extends StatelessWidget {
  final String sprite;
  final int grade; // 1..5, đổi tông A/B/C
  final double size;
  const PixelIcon(this.sprite, {super.key, this.grade = 1, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final key = sprite == 'gourd_big' ? 'gourd' : sprite;
    return Image.asset(
      'assets/cult_items/$key.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => CustomPaint(
        size: Size.square(size),
        painter: _PixelPainter(_sprites[sprite] ?? _sprites['pill']!, grade),
      ),
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
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.grid != grid || old.grade != grade;
}
