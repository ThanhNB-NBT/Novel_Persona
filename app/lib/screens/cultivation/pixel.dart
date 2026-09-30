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

/// Bản phối màu riêng theo MÃ vật phẩm → `assets/cult_items/<key>_<phối>.webp`
/// (sinh bằng `app/tool/recolor_items.py` từ minh hoạ gốc cùng key). Catalog server vẫn
/// giữ `pixel` = key gốc, nên bản app cũ chỉ thấy hình gốc chứ không vỡ. Món không có
/// trong map dùng hình gốc. Phối: xich đỏ · tu tím · bich lục · kim hổ phách · bang băng lam ·
/// huyen hắc · bach bạch ngân · tho nâu đất · lam lam.
const itemArt = <String, String>{
  // y phục
  'yp_tho_bo': 'robe_tho', 'yp_huyen_vu': 'robe_huyen', 'yp_thanh_giao': 'robe_bang',
  'yp_tu_van': 'robe_tu', 'yp_bach_lan': 'robe_bach', 'yp_bich_lan': 'robe_bich',
  'yp_kim_tam': 'robe_kim', 'yp_thien_tinh': 'celestial_robe_kim',
  'yp_vo_cau': 'celestial_robe_bang', 'yp_bat_diet': 'robe_xich',
  'yp_hon_nguyen': 'celestial_robe_tu',
  'yp_chu_tuoc': 'celestial_robe_xich', 'yp_huyen_minh': 'celestial_robe_huyen',
  // giày
  'gi_bo_ngoa': 'boot_tho', 'gi_thao_hai': 'boot_bich', 'gi_truy_phong': 'boot_bang',
  'gi_van_tung': 'boot_bach', 'gi_lang_ba': 'boot_lam', 'gi_liet_hoa_hai': 'boot_xich',
  'gi_dap_van': 'boot_kim', 'gi_hu_khong': 'boot_huyen', 'gi_tung_dia': 'boot_tho',
  'gi_thuan_thien': 'boot_tu', 'gi_luu_tinh': 'boot_tu',
  // đan tăng tốc (hồ lô)
  'dd_tu_khi': 'gourd_bich', 'dd_ngung_khi': 'gourd_tho', 'dd_linh_luc': 'gourd_bang',
  'dd_thanh_tam': 'gourd_bach', 'dd_tinh_nguyen': 'gourd_kim', 'dd_dao_nguyen': 'gourd_huyen',
  'dd_long_ho': 'gourd_xich', 'dd_tu_phu': 'gourd_tu', 'dd_cuu_duong': 'void_pill_xich',
  'dd_thai_at': 'void_pill_kim', 'dd_tien_nguyen': 'void_pill_bach', 'pb_ho_lo': 'gourd_kim',
  'dd_phan_thien': 'void_pill_tu',
  // đan luyện căn / chuyển hệ
  'dd_ngung_linh': 'pill_bang', 'dd_chuyen_linh': 'pill_tu', 'dd_ngoc_dich': 'pill_bach',
  'dd_thien_linh': 'pill_kim', 'dd_cuu_tay_linh': 'pill_xich', 'dd_tao_hoa': 'orb_tu',
  'dd_long_tuy': 'pill_huyen',
  // đan hộ thân
  'dd_ho_tam': 'shield_pill_xich', 'dd_dinh_than': 'shield_pill_bang',
  'dd_co_ban': 'shield_pill_tho', 'dd_pha_canh': 'shield_pill_tu', 'dd_do_ach': 'shield_pill_kim',
  'dd_tien_van': 'shield_pill_bach', 'dd_bo_de': 'shield_pill_huyen',
  // linh thạch
  'lt_ha_pham': 'stone_tho', 'lt_linh_tinh': 'stone_kim', 'lt_trung_pham': 'stone_bang',
  'lt_thuong_pham': 'stone_tu', 'lt_cuc_pham': 'stone_xich', 'lt_tien_thach': 'stone_bach',
  'lt_thuy_linh': 'stone_lam', 'lt_loi_linh': 'stone_huyen',
  // công pháp
  'cp_tho_nap': 'book_tho', 'cp_huyen_thien': 'book_bang', 'cp_kim_cang_co': 'book_kim',
  'cp_thanh_moc': 'book_bich', 'cp_thai_co': 'book_huyen', 'cp_loi_dinh': 'book_tu',
  'cp_hoa_chung': 'scroll_xich', 'cp_luyen_the': 'scroll_tho', 'cp_liet_hoa': 'scroll_kim',
  'cp_dia_sat': 'scroll_huyen', 'cp_thuong_hai': 'scroll_bang', 'cp_xich_diem': 'scroll_xich',
  'cp_hon_don': 'scroll_tu', 'cp_van_moc': 'scroll_bich', 'cp_hau_tho': 'scroll_tho',
  'cp_huyen_bang': 'slip_bang', 'cp_cuu_chuyen': 'slip_kim', 'cp_dai_dien': 'slip_tu',
  'cp_thanh_van_moc': 'slip_bich', 'cp_bang_tam': 'slip_bach',
  'cp_ngu_phong': 'fan_bich',
  // pháp chú
  'pc_kim_cang': 'seal_kim', 'pc_tran_hon': 'seal_huyen', 'pc_thai_thuong': 'seal_lam',
  'pc_thien_loi': 'seal_tu', 'pc_tien_van': 'seal_bach', 'pc_thanh_moc': 'seal_bich',
  'pc_han_nguyet': 'seal_bang',
  'pc_tinh_tam': 'talisman_bang', 'pc_ngu_loi': 'talisman_tu', 'pc_pha_gioi': 'talisman_xich',
  'pc_cuu_thien': 'talisman_bach', 'pc_hoi_xuan': 'talisman_bich', 'pc_am_sat': 'talisman_huyen',
  // vũ khí
  'vk_han_bang': 'sword_bang', 'vk_thanh_phong': 'sword_bich', 'vk_long_tuyen': 'sword_kim',
  'vk_thien_tinh': 'sword_tu', 'vk_tien_thien': 'sword_bach', 'vk_huyen_thiet': 'sword_huyen',
  'vk_xich_tieu': 'sword_xich',
  'vk_tu_kim': 'spear_tu', 'vk_pha_quan': 'spear_xich', 'vk_thi_than': 'spear_huyen',
  'vk_kim_o': 'spear_kim',
  'vk_dong_dao': 'saber_tho', 'vk_lieu_diep': 'saber_bich', 'vk_huyet_mang': 'saber_xich',
  'vk_thanh_long': 'saber_bang',
  'vk_chu_tuoc': 'bow_xich', 'vk_cuu_u': 'bow_huyen', 'vk_bang_phach': 'bow_bang',
  'vk_lac_nhat': 'bow_kim', 'vk_tu_ma': 'demonic_saber_tu',
  // pháp bảo
  'pb_vong_nguyet': 'halo_bach', 'pb_vong_tinh': 'halo_bang', 'pb_vong_loi': 'halo_tu',
  'pb_tu_kim_bat': 'cauldron_tu', 'pb_kim_quang': 'mirror_kim', 'pb_tinh_than_do': 'array_tu',
  'pb_bang_tam_kinh': 'mirror_bang', 'pb_huyet_ngoc': 'jade_xich', 'pb_ngu_loi_thap': 'pagoda_tu',
  'pb_dinh_hai_chau': 'orb_bang', 'pb_am_duong_ban': 'compass_huyen',
  'pb_hac_sat_phien': 'fan_huyen', 'pb_van_bao_nang': 'pouch_xich',
  'pb_cuu_long_hoa': 'dragon_cauldron_xich', 'pb_chu_thien_ban': 'array_kim',
};

/// Ảnh hiển thị cho vật phẩm: bản phối theo [code] nếu có, không thì hình gốc [pixel].
String itemArtKey(String? code, String pixel) =>
    itemArt[code] ?? (pixel == 'gourd_big' ? 'gourd' : pixel);

/// Icon vật phẩm minh hoạ riêng; fallback pixel giữ được catalog cũ nếu server trả key lạ.
class PixelIcon extends StatelessWidget {
  final String sprite;
  final String? code; // mã vật phẩm → bản phối màu riêng ([itemArt])
  final int grade; // 1..5, đổi tông A/B/C
  final double size;
  const PixelIcon(this.sprite,
      {super.key, this.code, this.grade = 1, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final key = itemArtKey(code, sprite);
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
