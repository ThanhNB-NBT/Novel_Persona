import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data.dart';

/// Data layer hệ thống Tu Luyện (migration 039). Mọi ghi qua RPC SECURITY DEFINER;
/// client chỉ SELECT được dòng của mình. Hằng cân bằng nằm đầu file migration.

const realmNames = [
  'Luyện Khí', 'Trúc Cơ', 'Kim Đan', 'Nguyên Anh', 'Hóa Thần',
  'Luyện Hư', 'Hợp Thể', 'Đại Thừa', 'Độ Kiếp',
]; // realm 1..9

const gradeNames = ['Hoàng', 'Huyền', 'Địa', 'Thiên', 'Tiên']; // grade 1..5

/// Đạo hiệu theo cảnh giới — cách giang hồ xưng hô tu sĩ (lore Phàm Nhân Tu Tiên).
const daoTitles = [
  'Luyện Khí tu sĩ', 'Trúc Cơ tu sĩ', 'Kim Đan chân nhân', 'Nguyên Anh lão tổ',
  'Hóa Thần đại năng', 'Luyện Hư đạo quân', 'Hợp Thể đại tôn', 'Đại Thừa thánh nhân',
  'Độ Kiếp bán tiên',
]; // realm 1..9

/// Ngũ hành — thuộc tính linh căn (trời định lúc khởi tạo, Chuyển Linh Đan đổi được).
/// Công pháp hợp hệ (trùng thuộc tính hoặc hệ 'all') → tốc độ ×1.3 (migration 043).
const elementNames = {
  'kim': 'Kim', 'moc': 'Mộc', 'thuy': 'Thủy', 'hoa': 'Hỏa', 'tho': 'Thổ',
  'all': 'Vạn Pháp',
};

/// Tên phẩm linh căn theo giá trị — càng "thuần" tu càng nhanh (lore ngũ hành:
/// tạp căn 5 hệ kém nhất, đơn linh căn/thiên linh căn hiếm nhất). Chỉ hiển thị.
String linhCanTier(int lc) => switch (lc) {
      < 5 => 'Ngũ Hành Tạp Căn',
      < 10 => 'Tứ Linh Căn',
      < 20 => 'Tam Linh Căn',
      < 40 => 'Song Linh Căn',
      < 80 => 'Đơn Linh Căn',
      < 160 => 'Biến Dị Linh Căn',
      _ => 'Thiên Linh Căn',
    };

const cultTypeNames = {
  'congphap': 'Công pháp', 'danduoc': 'Đan dược', 'linhthach': 'Linh thạch',
  'vukhi': 'Vũ khí', 'yphuc': 'Y phục', 'giay': 'Hài',
  'phapbao': 'Pháp bảo', 'phapchu': 'Pháp chú',
};

/// Chủng tộc — chọn MỘT lần khi bắt đầu tu (migration 044).
/// (tên, thiên hướng hiển thị trong sheet chọn tộc)
const raceNames = {'nhan': 'Nhân tộc', 'yeu': 'Yêu tộc', 'ma': 'Ma tộc', 'linh': 'Linh tộc'};
const genderNames = {'nam': 'Nam', 'nu': 'Nữ'};
const raceDescs = {
  'nhan': 'Đạo tâm kiên định — tỷ lệ đột phá +5%.',
  'yeu': 'Thể phách cường hãn — công kích & khí huyết ×1.3.',
  'ma': 'Tu luyện tà tốc — tốc độ ×1.10, đột phá −5%.',
  'linh': 'Linh hồn thanh tịnh — thần thức ×1.3, thất bại đột phá chỉ mất nửa tu vi.',
};

/// Tên chỉ số (khớp key trong cult_stats).
const statNames = {
  'atk': 'Công Kích', 'def': 'Phòng Ngự', 'hp': 'Khí Huyết',
  'agi': 'Thân Pháp', 'than_thuc': 'Thần Thức',
};

/// Lời dẫn cơ duyên khi nhận quà — chọn tất định theo giftHash, mỗi chương một câu.
const giftFlavors = [
  'Khe đá ven đường lóe hào quang, bên trong giấu một vật…',
  'Một tiền bối ẩn cư để lại cơ duyên cho kẻ hữu duyên…',
  'Đọc tới đây tâm cảnh chợt thông suốt, trời giáng linh vật…',
  'Con cá chép trong hồ nhả ra một vật lấp lánh…',
  'Sương tan, dưới gốc tùng cổ lộ ra bảo vật…',
  'Tiếng chuông xa vọng, trước mặt hiện ra chiếc rương nhỏ…',
  'Lật tảng đá phủ rêu, hiện ra di vật của tán tu vô danh…',
  'Linh khí quanh thân ngưng tụ, hóa thành vật thực…',
];

/// Hash tất định theo (user, truyện, chương) — nguồn chung cho "có quà không"
/// (% 100 < 50) và "quà nằm sau đoạn nào" (% số đoạn).
int giftHash(String uid, int novelId, int index) => int.parse(
      md5.convert(utf8.encode('$uid:$novelId:$index')).toString().substring(0, 6),
      radix: 16,
    );

/// Chương này có quà cho user này không — mirror y hệt SQL cult_gift_at():
/// 6 hex đầu của md5('uid:novel:index') % 100 < 50 (~50% chương, tất định —
/// migration 049 "Thiên Đạo sủng nhi", đổi ở đây phải đổi cả SQL).
bool giftAt(String uid, int novelId, int index) =>
    giftHash(uid, novelId, index) % 100 < 50;

/// State tu luyện (đã tick exp phía server): realm/stage/exp/req/rate/equipped...
final cultStateProvider = FutureProvider.autoDispose<Rec?>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return null;
  return Map<String, dynamic>.from(await sb.rpc('cult_state') as Map);
});

/// Toàn bộ catalog vật phẩm (đọc công khai) — cho mục sưu tầm + tab admin.
final cultCatalogProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb
        .from('cult_items')
        .select()
        .order('type', ascending: true)
        .order('grade', ascending: true)
        .order('id', ascending: true)));

/// Kho đồ: [{qty, cult_items:{...}}] — chỉ món còn qty > 0.
final cultInventoryProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return [];
  return List<Rec>.from(await sb
      .from('user_cult_items')
      .select('qty, cult_items(*)')
      .eq('user_id', uid)
      .gt('qty', 0));
});

/// Diễn giải effect jsonb của vật phẩm thành chữ (sheet chi tiết + tab admin).
String cultEffectText(Rec it) {
  final e = (it['effect'] as Map?) ?? const {};
  if (e['rate_pct'] != null) return '+${e['rate_pct']}% tốc độ tu luyện';
  if (e['bt_pct'] != null) return '+${e['bt_pct']}% tỷ lệ đột phá';
  if (e['atk'] != null) return 'công kích +${e['atk']}';
  if (e['def'] != null) {
    return 'phòng ngự +${e['def']}'
        '${e['hp'] != null ? ' · khí huyết +${e['hp']}' : ''}';
  }
  if (e['agi'] != null) return 'thân pháp +${e['agi']}';
  return switch (e['kind']) {
    'linhcan' => 'linh căn +${e['add']} vĩnh viễn',
    'buff' => '+${e['pct']}% tốc độ trong ${e['hours']} giờ',
    'stone' => '+${e['pct']}% tốc độ trong ${e['hours']} giờ (cộng dồn với đan)',
    'hothan' => '+${e['pct']}% đột phá cho lần kế tiếp',
    'element' => 'đổi thuộc tính linh căn sang hệ khác (ngẫu nhiên)',
    // công pháp: hệ số theo phẩm + hệ ngũ hành nếu có
    _ => 'hệ số tu luyện theo phẩm (×1.5 → ×24)'
        '${e['element'] != null ? ' · hệ ${elementNames[e['element']] ?? e['element']}'
            ' (hợp linh căn ×1.3)' : ''}',
  };
}

/// Các chương đã nhận quà trong 1 truyện — để ẩn nút quà chương đã nhận.
final cultClaimedProvider =
    FutureProvider.autoDispose.family<Set<int>, int>((ref, novelId) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return {};
  final rows = List<Rec>.from(await sb
      .from('cult_claims')
      .select('chapter_index')
      .eq('user_id', uid)
      .eq('novel_id', novelId));
  return {for (final r in rows) r['chapter_index'] as int};
});

/// Nhận quà trong chương → vật phẩm vừa rơi. Server verify công thức + chặn trùng.
Future<Rec> cultClaimGift(int novelId, int index) async =>
    Map<String, dynamic>.from(await sb.rpc('cult_claim_gift',
        params: {'p_novel_id': novelId, 'p_index': index}) as Map);

/// Uống đan dược / trang bị / lên tầng-đột phá — đều trả state hoặc kết quả json.
Future<Rec> cultUseItem(int itemId) async =>
    Map<String, dynamic>.from(
        await sb.rpc('cult_use_item', params: {'p_item_id': itemId}) as Map);

Future<Rec> cultEquip(int itemId) async =>
    Map<String, dynamic>.from(
        await sb.rpc('cult_equip', params: {'p_item_id': itemId}) as Map);

Future<Rec> cultAdvance() async =>
    Map<String, dynamic>.from(await sb.rpc('cult_advance') as Map);

/// Chọn dung mạo (tộc + giới tính) — user thường chỉ MỘT lần, admin đổi tự do.
Future<Rec> cultSetAvatar(String race, String gender) async =>
    Map<String, dynamic>.from(await sb.rpc('cult_set_avatar',
        params: {'p_race': race, 'p_gender': gender}) as Map);
