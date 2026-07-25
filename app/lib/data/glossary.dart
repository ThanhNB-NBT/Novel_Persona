import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';

// ---------- Glossary ----------

/// Term của truyện + term global; gồm cả gợi ý chưa duyệt (cần login mới thấy).
final glossaryProvider = FutureProvider.autoDispose.family<List<Rec>, int>((
  ref,
  novelId,
) async {
  return List<Rec>.from(
    await sb
        .from('glossary_terms')
        .select('id, term_zh, wrong_vi, correct_vi, term_type, scope, approved, narrator_term')
        .or('novel_id.eq.$novelId,novel_id.is.null')
        .order('approved')
        .order('created_at', ascending: false),
  );
});

Future<void> updateTerm(int id, Map<String, dynamic> fields) =>
    sb.from('glossary_terms').update(fields).eq('id', id);

Future<void> deleteTerm(int id) =>
    sb.from('glossary_terms').delete().eq('id', id);

/// Xoá nhiều term một lượt (chọn hàng loạt trong màn Thuật ngữ).
Future<void> deleteTerms(List<int> ids) =>
    sb.from('glossary_terms').delete().inFilter('id', ids);

Future<void> addTerm(int novelId, String zh, String vi, {String? wrongVi}) =>
    sb.from('glossary_terms').insert({
      'novel_id': novelId,
      'term_zh': zh,
      'correct_vi': vi,
      if (wrongVi != null && wrongVi.isNotEmpty) 'wrong_vi': wrongVi,
      'approved': true,
      'created_by': sb.auth.currentUser!.id,
    });

/// Xếp job vá các chương đã dịch bằng glossary mới (string-replace phía worker).
Future<void> requestPatch(int novelId) =>
    sb.rpc('request_patch', params: {'p_novel_id': novelId});

/// Trạng thái job vá gần nhất của truyện (pending/running/done/failed + result
/// "N/M chương" + done_at) — để màn Thuật ngữ hiện tiến trình. null = chưa vá lần nào.
final latestPatchProvider =
    FutureProvider.autoDispose.family<Rec?, int>((ref, novelId) async {
  final rows = List<Rec>.from(
      await sb.rpc('latest_patch_status', params: {'p_novel_id': novelId}));
  return rows.isEmpty ? null : rows.first;
});

// ---------- Yêu cầu truyện ----------

/// Yêu cầu của TÔI, mới nhất trước. Worker xử lý trong ~10-30s (nguồn chặn search
/// thì lâu hơn, tối đa 10 phút sẽ chốt kết quả).
final myNovelRequestsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return [];
  return List<Rec>.from(
    await sb
        .from('novel_requests')
        .select('id, query, status, note, novel_id, created_at, novels(title_vi, title_zh)')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(20),
  );
});

Future<void> addNovelRequest(String query) async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return;
  await sb.from('novel_requests').insert({'user_id': uid, 'query': query.trim()});
}

Future<void> deleteNovelRequest(int id) =>
    sb.from('novel_requests').delete().eq('id', id);

// ---------- Báo cáo term ----------

/// Người đọc báo cáo 1 term dịch sai → admin soi (không tự xoá để tránh phá glossary).
Future<void> reportTerm(int termId, int novelId, String reason) =>
    sb.from('glossary_reports').insert({
      'term_id': termId,
      'novel_id': novelId,
      'reason': reason,
      'reported_by': sb.auth.currentUser!.id,
    });
