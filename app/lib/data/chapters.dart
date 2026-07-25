import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline.dart';
import 'core.dart';

// ---------- Mục lục + chương ----------

/// Mục lục: chỉ cột nhẹ, không kéo content.
final chapterListProvider = FutureProvider.autoDispose.family<List<Rec>, int>((
  ref,
  novelId,
) async {
  // supabase-dart .order() mặc định DESCENDING → phải chỉ rõ ascending để "1 → hết".
  // Kéo THEO TRANG qua trần 1000 dòng/query của PostgREST — phải đủ hết, vì
  // list.length < chapter_count_source là tín hiệu "mục lục lười đang tải":
  // truyện >1000 chương mà kéo thiếu thì banner tải mục lục hiện vĩnh viễn.
  final all = <Rec>[];
  for (var from = 0;; from += 1000) {
    final page = await sb
        .from('chapters')
        .select('chapter_index, title_vi, title_zh, translation_status')
        .eq('novel_id', novelId)
        .order('chapter_index', ascending: true)
        .range(from, from + 999);
    all.addAll(List<Rec>.from(page));
    if (page.length < 1000) break;
  }
  return all;
});

class ChapterKey {
  final int novelId, index;
  const ChapterKey(this.novelId, this.index);
  @override
  bool operator ==(Object other) =>
      other is ChapterKey && other.novelId == novelId && other.index == index;
  @override
  int get hashCode => Object.hash(novelId, index);
}

final chapterProvider = FutureProvider.autoDispose.family<Rec?, ChapterKey>((
  ref,
  key,
) async {
  // Offline-first: chương đã tải về máy → đọc local (chạy cả khi mất mạng), khỏi
  // subscribe realtime. Chương chưa tải → rơi xuống nhánh online bên dưới.
  final local = await offlineStore.getChapter(key.novelId, key.index);
  if (local != null) return local;
  // Realtime: chương này được worker UPDATE (dịch xong/đổi trạng thái) → tự refetch
  final channel = sb
      .channel('chapter:${key.novelId}:${key.index}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chapters',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'novel_id',
          value: key.novelId,
        ),
        callback: (payload) {
          // filter realtime chỉ lọc được 1 cột (novel_id) ở server → lọc thêm
          // chapter_index phía client: dịch hàng loạt bắn update mọi chương của
          // truyện, không lọc thì chương đang đọc refetch liên tục dù không đổi.
          if (payload.newRecord['chapter_index'] == key.index) {
            ref.invalidateSelf();
          }
        },
      )
      .subscribe();
  ref.onDispose(() => sb.removeChannel(channel));
  return await sb
      .from('chapters')
      .select(
        'chapter_index, title_vi, title_zh, content_vi, translation_status',
      )
      .eq('novel_id', key.novelId)
      .eq('chapter_index', key.index)
      .maybeSingle();
});

// ---------- Sửa / góp ý bản dịch ----------

/// Sửa TRỰC TIẾP bản dịch 1 chương (string-replace, không LLM, không hàng đợi) → hiện ngay
/// sau khi invalidate chapterProvider. RPC SECURITY DEFINER (migration 021).
Future<void> editChapterText(int novelId, int index, String wrong, String correct) =>
    sb.rpc('edit_chapter_vi', params: {
      'p_novel_id': novelId,
      'p_index': index,
      'p_wrong': wrong,
      'p_correct': correct,
    });

/// Góp ý sửa bản dịch: lưu như term glossary (dùng cho chương/truyện dịch SAU). Theo plan §5.2.
Future<void> submitCorrection(int novelId, String wrong, String correct) async {
  final uid = sb.auth.currentUser!.id;
  // Term đang mang ĐÚNG bản sai này (thường là gợi ý LLM có kèm chữ Trung, vd
  // 幻妖→"Hoan Yêu") → sửa TẠI CHỖ thay vì thêm term mới: giữ liên kết term_zh nên
  // chương dịch SAU được prompt ép đúng tên, không chỉ vá chương cũ bằng patch.
  final hits = List<Map<String, dynamic>>.from(await sb
      .from('glossary_terms')
      .select('id')
      .eq('novel_id', novelId)
      .eq('correct_vi', wrong));
  if (hits.isNotEmpty) {
    for (final h in hits) {
      await sb.from('glossary_terms').update({
        'correct_vi': correct,
        'wrong_vi': wrong,
        'approved': true,
      }).eq('id', h['id']);
    }
    return;
  }
  await sb.from('glossary_terms').insert({
    'novel_id': novelId,
    'wrong_vi': wrong,
    'correct_vi': correct,
    'term_type': 'other',
    'approved': true,
    'created_by': uid,
  });
}

// ---------- Yêu cầu dịch ----------

/// App bấm "Đọc"/prefetch — server tự chống trùng job nên gọi thoải mái.
/// Trả số chương vừa được xếp vào hàng đợi (RPC trả v_count).
Future<int> requestTranslation(
  int novelId,
  int upTo, {
  int priority = 50,
}) async {
  final r = await sb.rpc(
    'request_translation',
    params: {'p_novel_id': novelId, 'p_up_to': upTo, 'p_priority': priority},
  );
  return (r as int?) ?? 0;
}

/// Dịch lại 1 chương (kể cả chương đã dịch xong).
Future<void> retranslateChapter(int novelId, int chapterIndex) => sb.rpc(
  'retranslate_chapter',
  params: {'p_novel_id': novelId, 'p_index': chapterIndex},
);

/// Dịch lại TẤT CẢ chương đã dịch (done/failed) của truyện bằng prompt + glossary
/// hiện tại. Bản dịch cũ giữ nguyên cho tới khi bản mới đè lên. Trả số chương xếp lại.
Future<int> retranslateAll(int novelId) async =>
    (await sb.rpc('retranslate_all', params: {'p_novel_id': novelId}) as int?) ?? 0;

/// Mục lục lười: truyện chưa ai đọc chỉ có vài stub chương mẫu — reader gọi cái này
/// lúc MỞ ĐỌC để crawler tải mục lục đầy đủ (~10-20s). No-op nếu đã có mục lục.
/// Truyện bỏ đọc lâu ngày bị janitor (migration 035) trả về dạng lười.
Future<void> requestToc(int novelId) =>
    sb.rpc('request_toc', params: {'p_novel_id': novelId});

// ---------- Bình luận chương ----------

/// Bình luận của 1 chương, cũ → mới (đọc như hội thoại).
final chapterCommentsProvider =
    FutureProvider.autoDispose.family<List<Rec>, ChapterKey>((ref, k) async {
  return List<Rec>.from(
    await sb
        .from('chapter_comments')
        .select('id, user_id, display_name, content, created_at')
        .eq('novel_id', k.novelId)
        .eq('chapter_index', k.index)
        .order('created_at', ascending: true),
  );
});

Future<void> addChapterComment(int novelId, int index, String content) async {
  final u = sb.auth.currentUser;
  if (u == null) return;
  // snapshot tên hiển thị — RLS profiles không cho người khác đọc tên mình sau này
  final prof =
      await sb.from('profiles').select('display_name').eq('id', u.id).maybeSingle();
  await sb.from('chapter_comments').insert({
    'novel_id': novelId,
    'chapter_index': index,
    'user_id': u.id,
    'display_name': prof?['display_name'] ?? u.email,
    'content': content,
  });
}

Future<void> deleteChapterComment(int id) =>
    sb.from('chapter_comments').delete().eq('id', id);

/// Báo cáo CHƯƠNG dịch lỗi (nút Báo cáo cuối chương) — dùng chung hộp glossary_reports
/// (term_id null), admin xem ở màn Quản trị.
Future<void> reportChapter(int novelId, int chapterIndex, String reason) =>
    sb.from('glossary_reports').insert({
      'novel_id': novelId,
      'reason': 'Chương $chapterIndex: $reason',
      'reported_by': sb.auth.currentUser!.id,
    });
