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

// ===== Nhân vật pixel theo CHỦNG TỘC (sprite 24×26, kiểu 16-bit JRPG) =====
// Ngồi thiền chính diện, full body, palette giới hạn theo tộc — chung khung
// thân để "cùng một game": Nhân áo lam + trâm + đai ngọc · Yêu tai cáo + đuôi
// chóp trắng, tông thổ · Ma sừng xương + mắt đỏ, tông tím đen · Linh áo trắng
// viền vàng + linh quang + tóc bạc.

const _cultBase = <String>[
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
  '....kAAAAAffffAAAAAk....', // 18 tay bắt ấn trong lòng
  '...kAAAAAAffffAAAAAAk...', // 19
  '...kAAAAAAAAAAAAAAAAk...', // 20 vạt áo xòe phủ chân
  '..kAAAAAAAAAAAAAAAAAAk..', // 21
  '..kABBAAAAAAAAAAAABBAk..', // 22 gối bắt sáng
  '..kCAAAAAAAAAAAAAAAACk..', // 23
  '...kkkkkkkkkkkkkkkkkk...', // 24
  '........................', // 25
];

/// Grid theo tộc: nền chung + thay các hàng đặc trưng (đầu, tóc, đuôi).
List<String> cultivatorGrid(String? race) {
  final g = List<String>.of(_cultBase);
  switch (race) {
    case 'yeu': // tai cáo lộ da trong + đuôi cong bên phải chóp trắng, đầu trần
      g[1] = '.......hh......hh.......';
      g[2] = '.......hhh....hhh.......';
      g[3] = '.......hfhh..hhfh.......';
      g[15] = '.....kAAAABwwBAAAAk..ww.';
      g[16] = '....kAAAAABwwBAAAAAk.BB.';
      g[17] = '....kASSSSSSSSSSSSAk.BB.';
      g[18] = '....kAAAAAffffAAAAAk..BB';
      g[19] = '...kAAAAAAffffAAAAAAk.BB';
      g[20] = '...kAAAAAAAAAAAAAAAAk.B.';
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
  return g;
}

/// Palette giới hạn theo tộc (theo race design rules đã chốt).
({Color a, Color b, Color c, Color s, Color hair, Color eye, Color skin})
    _racePal(String? race) => switch (race) {
          'yeu' => (
              a: const Color(0xFFC2703A), // áo nâu cam thổ
              b: const Color(0xFFE8A05C),
              c: const Color(0xFF8A4A22),
              s: const Color(0xFF5C3A1E), // đai da
              hair: const Color(0xFF7A4A26),
              eye: const Color(0xFF241F31),
              skin: const Color(0xFFF1C27D),
            ),
          'ma' => (
              a: const Color(0xFF463058), // áo tím đen
              b: const Color(0xFF6E4A85),
              c: const Color(0xFF2A1836),
              s: const Color(0xFFB02A37), // đai đỏ thẫm
              hair: const Color(0xFF231A2F),
              eye: const Color(0xFFE03131), // mắt đỏ
              skin: const Color(0xFFE0C2B8), // da tái
            ),
          'linh' => (
              a: const Color(0xFFE4DCC8), // áo trắng ngà
              b: const Color(0xFFE9C46A), // viền vàng
              c: const Color(0xFFB8A888),
              s: const Color(0xFFD4A017), // linh quang + đai vàng
              hair: const Color(0xFFE8E4F0), // tóc bạc
              eye: const Color(0xFF3BC9DB),
              skin: const Color(0xFFF6DCB5),
            ),
          _ => (
              a: const Color(0xFF3E63B0), // Nhân: áo thanh lam
              b: const Color(0xFF6E8FD6),
              c: const Color(0xFF2A4578),
              s: const Color(0xFF2F9E77), // đai ngọc bích
              hair: const Color(0xFF2E2A3B),
              eye: const Color(0xFF241F31),
              skin: const Color(0xFFF1C27D),
            ),
        };

/// Vẽ nhân vật vào [rect]: căn giữa ngang theo rect, ĐÁY sprite chạm đáy rect
/// (đặt đáy rect lên mặt chỗ ngồi là nhân vật "ngồi" đúng chỗ).
void drawCultivator(Canvas canvas, Rect rect, String? race) {
  final grid = cultivatorGrid(race);
  final pal = _racePal(race);
  final cell = rect.width / grid[0].length;
  final oy = rect.bottom - grid.length * cell;
  final paint = Paint();
  for (var y = 0; y < grid.length; y++) {
    final row = grid[y];
    for (var x = 0; x < row.length; x++) {
      final ch = row[x];
      if (ch == '.') continue;
      paint.color = switch (ch) {
        'k' => const Color(0xFF241F31), // viền mực
        'w' => const Color(0xFFF6F4EF),
        'y' => const Color(0xFFCBB9A0), // xương sừng
        'z' => const Color(0xFFC6CCDA), // trâm bạc
        'A' => pal.a,
        'B' => pal.b,
        'C' => pal.c,
        'S' => pal.s,
        'h' => pal.hair,
        'e' => pal.eye,
        'f' => pal.skin,
        _ => const Color(0x00000000),
      };
      // +0.5 phủ mép: tránh khe hở hairline giữa các ô khi scale lẻ
      canvas.drawRect(
          Rect.fromLTWH(
              rect.left + x * cell, oy + y * cell, cell + 0.5, cell + 0.5),
          paint);
    }
  }
}
