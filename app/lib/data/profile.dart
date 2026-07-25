import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';

/// Chế độ sáng/tối toàn app: 0=hệ thống, 1=sáng, 2=tối.
class AppThemeMode extends Notifier<int> {
  @override
  int build() => prefs.getInt('app_theme_mode') ?? 0;
  void set(int i) {
    state = i;
    prefs.setInt('app_theme_mode', i);
  }
}

final appThemeModeProvider = NotifierProvider<AppThemeMode, int>(
  AppThemeMode.new,
);

/// Emblem xoay giữa dock (tab Tu Tiên) — key sprite trong pixel.dart. Chọn tại
/// màn Sửa hồ sơ, lưu cục bộ (thuần trang trí, không cần server). Chỉ nhận các
/// emblem đối xứng radial cho xoay đẹp.
// đĩa giữa dock — dùng lại sprite pixel của kho đồ, chọn các hình "ra dáng pháp bảo"
const tabEmblems = [
  'taiji', 'cauldron', 'pagoda', 'gourd', 'sword', 'fan',
  'talisman', 'seal', 'compass', 'array', 'orb', 'mirror', 'jade', 'pouch',
];

class TabEmblem extends Notifier<String> {
  @override
  String build() {
    final e = prefs.getString('tab_emblem');
    return (e != null && tabEmblems.contains(e)) ? e : 'taiji';
  }

  void set(String e) {
    state = e;
    prefs.setString('tab_emblem', e);
  }
}

final tabEmblemProvider = NotifierProvider<TabEmblem, String>(TabEmblem.new);

/// Avatar preset (emoji) — không cần upload ảnh; lưu thẳng ký tự vào profiles.avatar_url.
const avatarPresets = [
  // tiên hiệp có cá tính (đã lọc mấy cái nhạt: sách, trăng, hoa lá cành…)
  '🐉', '⚔️', '🦊', '🔥', '🏯', '🐼', '🎭', '👑', '☯️', '🐯', '🦅', '🐍',
  '🪷', '🏮', '🧧', '⚡', '💎', '🦉',
  // meme — trấn phái chi bảo
  '🗿', '🐸', '💀', '🤡', '👽', '🤖', '🦆', '🐧', '😼', '🍄', '🫠', '😴',
];

/// Hồ sơ user (tên hiển thị, avatar preset, streak đọc).
final profileProvider = FutureProvider.autoDispose<Rec?>((ref) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  return await sb
      .from('profiles')
      .select('display_name, avatar_url, streak, last_read_date')
      .eq('id', uid)
      .maybeSingle();
});

/// Cập nhật tên hiển thị + avatar preset của user hiện tại (RLS own_profile cho phép;
/// is_admin bị trigger guard chặn nên gửi cột này cũng vô hại).
Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return;
  await sb
      .from('profiles')
      .update({'display_name': ?displayName, 'avatar_url': ?avatarUrl})
      .eq('id', uid);
}

/// Streak "còn sống" = ngày đọc gần nhất là hôm nay/hôm qua; đứt thì hiện 0.
int liveStreak(Rec? profile) {
  if (profile == null) return 0;
  final s = (profile['streak'] ?? 0) as int;
  final last = profile['last_read_date'] as String?;
  if (s == 0 || last == null) return 0;
  final d = DateTime.tryParse(last);
  if (d == null) return 0;
  final today = DateTime.now();
  final diff = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  return diff <= 1 ? s : 0; // đọc hôm nay/hôm qua → còn chuỗi; cũ hơn → đứt
}

/// Thống kê đọc của user hiện tại (số truyện đang đọc, tổng chương đã tiến).
final readStatsProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  ref.watch(authStateProvider); // nạp lại khi đăng nhập/xuất
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return {'novels': 0, 'chapters': 0};
  final rows = List<Rec>.from(
    await sb.from('reading_progress').select('chapter_index').eq('user_id', uid),
  );
  final chapters = rows.fold<int>(
    0,
    (s, r) => s + ((r['chapter_index'] ?? 0) as int),
  );
  return {'novels': rows.length, 'chapters': chapters};
});
