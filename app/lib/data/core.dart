import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Các file data khác chỉ import `core.dart`; re-export để chúng dùng được
/// `.count(CountOption.exact)` mà không phải kéo thêm supabase_flutter.
export 'package:supabase_flutter/supabase_flutter.dart'
    show CountOption, PostgrestFilterBuilder;

final sb = Supabase.instance.client;

/// Gán trong main() trước runApp.
late final SharedPreferences prefs;

/// Phát mỗi lần đăng nhập/đăng xuất → mọi provider phụ thuộc auth watch cái này
/// để tự nạp lại (nếu không, đăng nhập xong UI vẫn kẹt ở trạng thái cũ).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => sb.auth.onAuthStateChange,
);

// ponytail: model = Map từ PostgREST, chưa cần freezed — thêm khi model phình/nhiều màn dùng chung
typedef Rec = Map<String, dynamic>;

/// Tiến độ đọc trong 1 chương (0..1) — lưu local theo máy để khôi phục vị trí cuộn + hiện %.
Future<void> saveChapterPercent(int novelId, int idx, double pct) =>
    prefs.setDouble('rp_${novelId}_$idx', pct.clamp(0, 1));
double chapterPercent(int novelId, int idx) =>
    prefs.getDouble('rp_${novelId}_$idx') ?? 0;

/// Bỏ dấu tiếng Việt + hạ chữ thường, khớp với `public.vn_norm()` trong DB
/// (migration 111). Người dùng gõ "Toan Dan" phải tìm ra "Toàn Dân…".
///
/// Tự viết bảng thay vì kéo thêm gói: chỉ là một phép ánh xạ ký tự, và bộ chữ
/// tiếng Việt là đóng — thêm dependency cho việc này là thừa.
const _dauVn = {
  'a': 'àáảãạăằắẳẵặâầấẩẫậ',
  'e': 'èéẻẽẹêềếểễệ',
  'i': 'ìíỉĩị',
  'o': 'òóỏõọôồốổỗộơờớởỡợ',
  'u': 'ùúủũụưừứửữự',
  'y': 'ỳýỷỹỵ',
  'd': 'đ',
};
final Map<int, String> _bangBoDau = {
  for (final e in _dauVn.entries)
    for (final ch in e.value.split(''))
      ...{
        ch.codeUnitAt(0): e.key,
        ch.toUpperCase().codeUnitAt(0): e.key,
      },
};

String boDau(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    b.write(_bangBoDau[r] ?? String.fromCharCode(r).toLowerCase());
  }
  return b.toString();
}
