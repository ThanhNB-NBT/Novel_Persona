import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
