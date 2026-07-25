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

/// Thông báo: chương của truyện trong TỦ SÁCH vừa dịch xong (7 ngày gần đây).
/// Pull-based — luôn xem lại được, không phụ thuộc app có đang mở lúc dịch xong.
final notificationsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return [];
  final lib = await sb.from('library').select('novel_id');
  final ids = [for (final r in lib) r['novel_id'] as int];
  if (ids.isEmpty) return [];
  final since =
      DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
  return List<Rec>.from(
    await sb
        .from('chapters')
        .select('chapter_index, translated_at, novel_id, '
            'novels(title_vi, title_zh, cover_url)')
        .inFilter('novel_id', ids)
        .eq('translation_status', 'done')
        .gte('translated_at', since)
        .order('translated_at', ascending: false)
        .limit(100),
  );
});

/// Có chương mới dịch xong SAU lần mở màn Thông báo gần nhất? — chấm đỏ trên
/// chuông. Mốc "đã xem" lưu local (prefs), set khi mở màn Thông báo.
final unseenNotifProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(authStateProvider);
  if (sb.auth.currentUser == null) return false;
  final seen = prefs.getString('notify_seen_at');
  if (seen == null) {
    // lần đầu: đặt mốc, khỏi chấm đỏ dội chuyện cũ
    await prefs.setString('notify_seen_at', DateTime.now().toUtc().toIso8601String());
    return false;
  }
  final lib = await sb.from('library').select('novel_id');
  final ids = [for (final r in lib) r['novel_id'] as int];
  if (ids.isEmpty) return false;
  final rows = await sb
      .from('chapters')
      .select('id')
      .inFilter('novel_id', ids)
      .eq('translation_status', 'done')
      .gt('translated_at', seen)
      .limit(1);
  return rows.isNotEmpty;
});

/// Gọi khi mở màn Thông báo — dập chấm đỏ.
Future<void> markNotificationsSeen() =>
    prefs.setString('notify_seen_at', DateTime.now().toUtc().toIso8601String());
