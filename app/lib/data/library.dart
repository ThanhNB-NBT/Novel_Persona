import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';
import 'novels.dart';

/// Tủ truyện: truyện user đang đọc (có tiến độ), kèm chương đang đọc + tổng chương.
final readingProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider); // đăng nhập/xuất → nạp lại tủ truyện
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = List<Rec>.from(
    await sb
        .from('reading_progress')
        .select('chapter_index, updated_at, novels($novelCols)')
        // Lọc CHÍNH user: admin có policy đọc reading_progress của mọi người (cho tab
        // Quản trị) → không lọc thì Tủ truyện admin hiện cả tiến độ người khác (và không
        // xoá được vì không phải row của mình).
        .eq('user_id', uid)
        .order('updated_at', ascending: false),
  );
  // gộp phẳng: {novel..., cur_chapter}
  return rows.map((r) {
    final n = Map<String, dynamic>.from(r['novels'] as Map);
    n['cur_chapter'] = r['chapter_index'];
    n['read_at'] = r['updated_at'];
    return n;
  }).toList();
});

/// Tủ sách của user (RLS tự lọc theo auth.uid).
final libraryProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return [];
  return List<Rec>.from(
    await sb
        .from('library')
        .select(
          'added_at, novels(id, title_vi, title_zh, author_vi, author_zh, '
          'cover_url, chapter_count_translated, chapter_count_source)',
        )
        .order('added_at', ascending: false),
  );
});

final inLibraryProvider = FutureProvider.autoDispose.family<bool, int>((
  ref,
  novelId,
) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return false;
  return await sb
          .from('library')
          .select('novel_id')
          .eq('novel_id', novelId)
          .maybeSingle() !=
      null;
});

Future<void> setInLibrary(int novelId, bool add) async {
  final uid = sb.auth.currentUser!.id;
  if (add) {
    await sb.from('library').upsert({'user_id': uid, 'novel_id': novelId});
  } else {
    await sb
        .from('library')
        .delete()
        .eq('user_id', uid)
        .eq('novel_id', novelId);
  }
}

/// Xóa truyện khỏi Tủ truyện = xóa lịch sử đọc (reading_progress) của truyện đó.
Future<void> removeReading(int novelId) async {
  // Xoá luôn vị trí cuộn trong từng chương lưu local (rp_<novelId>_<idx>),
  // nếu không thì mở lại chương vẫn nhảy về chỗ đọc dở dù đã xoá khỏi tủ.
  for (final k in prefs.getKeys().where((k) => k.startsWith('rp_${novelId}_'))) {
    await prefs.remove(k);
  }
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return;
  await sb
      .from('reading_progress')
      .delete()
      .eq('user_id', uid)
      .eq('novel_id', novelId);
}

/// Chương đang đọc dở (null = chưa đọc / chưa đăng nhập).
final progressProvider = FutureProvider.autoDispose.family<int?, int>((
  ref,
  novelId,
) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  final r = await sb
      .from('reading_progress')
      .select('chapter_index')
      .eq('novel_id', novelId)
      // PHẢI lọc user: admin có policy đọc tiến độ mọi người → không lọc thì
      // maybeSingle dính nhiều dòng → nổ → nút "Đọc tiếp" tụt về chương 1
      .eq('user_id', uid)
      .maybeSingle();
  return r?['chapter_index'] as int?;
});

// ponytail: chỉ lưu tới cấp chương; scroll_offset thêm sau nếu cần resume giữa chương
Future<void> saveProgress(int novelId, int chapterIndex) async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return;
  await sb.from('reading_progress').upsert({
    'user_id': uid,
    'novel_id': novelId,
    'chapter_index': chapterIndex,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
  // Cập nhật streak (RPC no-op nếu đã tính hôm nay) — fire-and-forget, không chặn đọc.
  try {
    await sb.rpc('touch_reading_streak');
  } catch (_) {}
}

// ---------- Thông báo ----------
// Pull-based (dựng từ bảng chapters) + trạng thái đọc/xoá lưu LOCAL trên máy
// (per-device, không backend). 3 mốc trong prefs:
//   notify_seen_at   — mốc "đã đọc" (đặt khi mở màn) → đếm số chưa đọc.
//   notify_dismissed — khoá 'nid:idx' đã xoá khỏi danh sách.
//   notify_mine      — khoá 'nid:idx' chương MÌNH chủ động dịch lại → báo dù ngoài tủ.

String _notifKey(int novelId, int index) => '$novelId:$index';
Set<String> _notifDismissed() => prefs.getStringList('notify_dismissed')?.toSet() ?? {};
Set<String> notifyMine() => prefs.getStringList('notify_mine')?.toSet() ?? {};

/// Ghi 1 chương mình vừa bấm dịch lại → được báo khi worker xong (kể cả ngoài tủ).
Future<void> addMyRetranslation(int novelId, int index) async {
  final s = notifyMine()..add(_notifKey(novelId, index));
  await prefs.setStringList('notify_mine', s.toList());
}

/// Xoá 1 thông báo (theo truyện+chương) khỏi danh sách.
Future<void> dismissNotification(int novelId, int index) async {
  final s = _notifDismissed()..add(_notifKey(novelId, index));
  await prefs.setStringList('notify_dismissed', s.toList());
}

/// Xoá hết: nhét mọi khoá đang hiện vào tập đã-xoá. ponytail: tập chỉ phình bằng
/// số thông báo từng thấy (chuỗi nhỏ), 7 ngày sau nguồn tự rụng nên không dọn.
Future<void> dismissAllNotifications(Iterable<String> keys) async {
  final s = _notifDismissed()..addAll(keys);
  await prefs.setStringList('notify_dismissed', s.toList());
}

/// Khoá 'nid:idx' của 1 dòng thông báo — UI dùng để xoá.
String notifKeyOf(Rec c) => _notifKey(c['novel_id'] as int, c['chapter_index'] as int);

/// Novel_id user "theo dõi" = trong Tủ sách (library) HOẶC đang đọc dở
/// (reading_progress). Chương mới dịch xong của các truyện này thì được báo.
Future<Set<int>> followedNovelIds() async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return {};
  final lib = await sb.from('library').select('novel_id');
  final rp = await sb.from('reading_progress').select('novel_id').eq('user_id', uid);
  return {
    for (final r in lib) r['novel_id'] as int,
    for (final r in rp) r['novel_id'] as int,
  };
}

/// Thông báo: chương dịch xong 7 ngày của (truyện đang theo dõi) HOẶC (chương mình
/// dịch lại), trừ những cái đã xoá. Pull-based nên luôn xem lại được.
final notificationsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return [];
  final followed = await followedNovelIds();
  final mine = notifyMine();
  final mineNovelIds = {for (final k in mine) int.parse(k.split(':').first)};
  final allIds = {...followed, ...mineNovelIds}.toList();
  if (allIds.isEmpty) return [];
  final since =
      DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
  final rows = List<Rec>.from(await sb
      .from('chapters')
      .select('chapter_index, translated_at, novel_id, '
          'novels(title_vi, title_zh, cover_url)')
      .inFilter('novel_id', allIds)
      .eq('translation_status', 'done')
      .gte('translated_at', since)
      .order('translated_at', ascending: false)
      .limit(200));
  final dismissed = _notifDismissed();
  return rows.where((c) {
    final key = notifKeyOf(c);
    if (dismissed.contains(key)) return false;
    // truyện đang theo dõi → mọi chương; ngoài diện đó → chỉ đúng chương mình dịch lại
    return followed.contains(c['novel_id']) || mine.contains(key);
  }).toList();
});

/// Số thông báo chưa đọc (mới hơn mốc "đã xem") — hiện lên badge chuông.
final unreadNotifCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return 0;
  final seen = prefs.getString('notify_seen_at');
  if (seen == null) {
    // lần đầu: đặt mốc, khỏi dội cả loạt thông báo cũ thành "chưa đọc"
    await prefs.setString('notify_seen_at', DateTime.now().toUtc().toIso8601String());
    return 0;
  }
  final list = await ref.watch(notificationsProvider.future);
  return list
      .where((c) => (c['translated_at'] as String).compareTo(seen) > 0)
      .length;
});

/// Gọi khi mở màn Thông báo — đánh dấu đã đọc (badge về 0).
Future<void> markNotificationsSeen() =>
    prefs.setString('notify_seen_at', DateTime.now().toUtc().toIso8601String());
