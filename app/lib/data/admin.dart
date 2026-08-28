import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';
import 'queue.dart';

// ---------- Quản trị (chỉ admin — RLS chặn user thường) ----------

/// User hiện tại có phải admin (cờ profiles.is_admin, chỉ đổi được qua SQL/service_role).
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return false;
  final r = await sb
      .from('profiles')
      .select('is_admin')
      .eq('id', uid)
      .maybeSingle();
  return r?['is_admin'] == true;
});

/// Danh sách truyện cho màn quản trị — GỒM cả truyện đã ẩn.
/// Cột tab Truyện THẬT SỰ đọc. Bỏ source_rank/meta_translated/is_canonical/updated_at:
/// kéo về mà không ai dùng (updated_at chỉ để sắp xếp — máy chủ tự lo, khỏi tải).
const _kAdminNovelCols =
    'id, title_vi, title_zh, author_vi, status, hidden, source_id, genres, '
    'last_chapter_at, chapter_count_source, chapter_count_translated, cover_url, sources(name)';

final adminNovelsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  // Tải ĐỦ mọi truyện: chip đếm + ô tìm kiếm của tab Truyện lọc phía client nên cần cả
  // danh sách (limit(200) cũ làm số đếm lệch với thống kê).
  // PostgREST trần 1000 dòng/query → 21k truyện = 22 lượt. Trước gọi NỐI TIẾP nên phải
  // chờ đủ 22 lần đi-về, đó là lý do tab này ì. Giờ hỏi tổng trước rồi bắn SONG SONG.
  // Sắp thêm theo id để phân trang ổn định: crawler sửa updated_at liên tục, chỉ xếp theo
  // mỗi cột đó thì dòng trôi giữa các trang gây trùng/sót.
  // ponytail: trần của cách này là bộ nhớ + băng thông (21k dòng mỗi lần mở tab). Khi nào
  //   thấy nặng thì chuyển lọc/tìm kiếm sang máy chủ và chỉ tải một trang.
  const page = 1000;
  const wave = 6; // số query song song mỗi đợt — nhanh mà không dội DB
  final total = await sb.from('novels').count();
  final out = <Rec>[];
  for (var start = 0; start < total; start += page * wave) {
    final batches = await Future.wait([
      for (var from = start; from < start + page * wave && from < total; from += page)
        sb
            .from('novels')
            .select(_kAdminNovelCols)
            .order('updated_at', ascending: false)
            .order('id', ascending: false)
            .range(from, from + page - 1),
    ]);
    for (final rows in batches) {
      out.addAll(List<Rec>.from(rows));
    }
  }
  return out;
});

/// Thống kê toàn app cho tab Truyện (admin): đếm bằng count head — không kéo dữ liệu.
final appStatsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final dayStart = DateTime.now().toUtc();
  final day0 = DateTime.utc(dayStart.year, dayStart.month, dayStart.day).toIso8601String();
  final results = await Future.wait([
    sb.from('novels').count(), // tổng bản ghi truyện (mọi nguồn)
    sb.from('novels').count().eq('is_canonical', true).eq('hidden', false),
    sb.from('novels').count().eq('meta_translated', false),
    sb.from('novels').count().eq('status', 'completed').eq('is_canonical', true),
    sb.from('chapters').count(), // tổng dòng mục lục đang lưu (stub + chương đã làm)
    sb.from('chapters').count().eq('translation_status', 'done'),
    sb.from('chapters').count().eq('translation_status', 'done').gte('translated_at', day0),
    sb.from('chapters').count().eq('translation_status', 'failed'),
  ]);
  return {
    'novels': results[0],
    'visible': results[1],
    'metaPending': results[2],
    'completed': results[3],
    'chapters': results[4],
    'done': results[5],
    'doneToday': results[6],
    'failed': results[7],
  };
});

/// Số job tối đa tab Worker kéo về. Danh sách là CỬA SỔ đầu hàng đợi, không phải toàn bộ —
/// ô đếm phải lấy từ [pendingJobCountProvider], đừng đếm độ dài danh sách này.
const kAdminJobsWindow = 120;

/// Tổng job pending THẬT (hàng đợi thường vài nghìn, danh sách hiển thị chỉ vài trăm).
final pendingJobCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final res = await sb
      .from('translation_jobs')
      .select('id')
      .eq('status', 'pending')
      .neq('type', 'audit')
      .count(CountOption.exact);
  return res.count;
});

/// Job đáng chú ý: đang chạy / lỗi / chờ (bỏ done). Kèm tên truyện + số chương.
final adminJobsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  final jobs = List<Rec>.from(
    await sb
        .from('translation_jobs')
        .select(
          'id, type, status, priority, attempts, error, created_at, started_at, '
          'novel_id, chapter_id, novels(title_vi, title_zh, sources(name, enabled)), '
          'chapters(chapter_index)',
        )
        .inFilter('status', ['running', 'failed', 'pending'])
        .neq('type', 'audit') // audit là job toàn cục (novel_id null) → không gộp theo truyện
        // PHẢI khớp thứ tự claim của worker (`order by priority, created_at` trong
        // claim_next_job) — trước đây created_at DESC nên tab này hiện 120 job chạy SAU
        // CÙNG mà trình bày như đầu hàng đợi, lệch hẳn với màn Hàng đợi.
        .order('priority', ascending: true) // ưu tiên cao (pri nhỏ, truyện đang đọc) lên đầu
        .order('created_at', ascending: true)
        .limit(kAdminJobsWindow),
  );
  // Job pending mà chương CHƯA có content_zh = crawler đang tải nguồn → gắn cờ
  // 'downloading' để tab Worker hiện "đang crawl" thay vì "chờ" chung chung.
  final pendingIds = [
    for (final j in jobs)
      if (j['status'] == 'pending' && j['chapter_id'] != null) j['chapter_id'] as int
  ];
  if (pendingIds.isNotEmpty) {
    final rows = List<Rec>.from(await sb
        .from('chapters')
        .select('id')
        .inFilter('id', pendingIds)
        .isFilter('content_zh', null));
    final downloading = {for (final r in rows) r['id'] as int};
    for (final j in jobs) {
      j['downloading'] = downloading.contains(j['chapter_id']);
      j['source_unavailable'] =
          j['downloading'] == true && jobSourceUnavailable(j);
    }
  }
  return jobs;
});

/// Chương của 1 truyện kèm thông tin SAU DỊCH (model, token, thời điểm) — cho màn quản trị.
final adminChaptersProvider = FutureProvider.autoDispose.family<List<Rec>, int>(
  (ref, novelId) async {
    return List<Rec>.from(
      await sb
          .from('chapters')
          .select(
            'chapter_index, title_vi, translation_status, model_used, '
            'prompt_tokens, completion_tokens, translated_at',
          )
          .eq('novel_id', novelId)
          .order('chapter_index', ascending: true)
          .limit(2000),
    );
  },
);

/// Dữ liệu động cho bộ lọc: số chương lớn nhất (để sinh mốc "N+") + các trạng thái đang có.
/// Trạng thái lấy thẳng từ DB → sau này crawl thêm trạng thái mới là tự hiện.
final filterFacetsProvider =
    FutureProvider.autoDispose<({int maxChapters, List<String> statuses})>((
      ref,
    ) async {
      final top = await sb
          .from('novels')
          .select('chapter_count_source')
          .eq('hidden', false)
          .order('chapter_count_source', ascending: false)
          .limit(1)
          .maybeSingle();
      final rows = List<Rec>.from(
        await sb
            .from('novels')
            .select('status')
            .eq('hidden', false)
            .limit(1000),
      );
      final statuses = <String>{
        for (final r in rows) r['status'] as String,
      }.toList()..sort();
      return (
        maxChapters: (top?['chapter_count_source'] ?? 0) as int,
        statuses: statuses,
      );
    });

/// Token đã dùng theo model (RPC gộp ở DB). Trả rỗng nếu không phải admin.
final tokenUsageProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  return List<Rec>.from(await sb.rpc('admin_token_usage'));
});

/// Sức khỏe model dịch (latency + ok/fail) — cho tab Token. RLS chỉ admin đọc.
final modelHealthProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  return List<Rec>.from(await sb
      .from('model_health')
      .select('model, ok_count, fail_count, total_latency_ms, last_ok_at, last_error, last_error_at')
      .order('updated_at', ascending: false));
});

/// Báo cáo term dịch sai chưa xử lý (góp ý auto-duyệt, chỉ soi khi bị báo cáo).
final reportsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  return List<Rec>.from(
    await sb
        .from('glossary_reports')
        .select(
          'id, reason, created_at, term_id, novel_id, '
          'glossary_terms(term_zh, wrong_vi, correct_vi), novels(title_vi, title_zh)',
        )
        .eq('resolved', false)
        .order('created_at', ascending: false)
        .limit(100),
  );
});

/// Truyện đang được đọc (có reader trong 8h qua) — tab quản trị "Đang đọc".
/// Cần quyền admin (RLS admin_read_progress) mới thấy của mọi user.
final readingNowProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 8))
      .toIso8601String();
  return List<Rec>.from(
    await sb
        .from('reading_progress')
        .select(
          'novel_id, chapter_index, updated_at, novels(title_vi, title_zh)',
        )
        .gte('updated_at', since)
        .order('updated_at', ascending: false)
        .limit(100),
  );
});

// ---------- Tác vụ admin ----------

Future<void> setNovelHidden(int id, bool hidden) =>
    sb.from('novels').update({'hidden': hidden}).eq('id', id);

Future<void> updateNovelFields(int id, Map<String, dynamic> fields) =>
    sb.from('novels').update(fields).eq('id', id);

Future<void> retryJob(int id) =>
    sb.rpc('admin_retry_job', params: {'p_job_id': id});

/// Config crawler (bảng worker_settings) — worker đọc lại mỗi chu kỳ discovery,
/// sửa ở tab Crawl là ăn ngay không cần restart.
final crawlSettingsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(
        await sb.from('worker_settings').select('key, value, note').order('key')));

Future<void> updateCrawlSetting(String key, String value) => sb
    .from('worker_settings')
    .update({'value': value, 'updated_at': DateTime.now().toUtc().toIso8601String()})
    .eq('key', key);

/// Nguồn crawl (bật/tắt + sức khỏe) cho tab Crawl.
final crawlSourcesProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb
        .from('sources')
        .select('id, name, base_url, enabled, fail_count, last_ok_at')
        .order('enabled', ascending: false)
        .order('name')));

Future<void> setSourceEnabled(int id, bool enabled) =>
    sb.from('sources').update({'enabled': enabled}).eq('id', id);

// ---------- Theo dõi VPS ----------

/// Số liệu máy chủ chạy worker (crawler đẩy mỗi phút). Nhiều host cùng lúc cũng được:
/// đổi VPS = máy mới tự xuất hiện, dòng cũ đứng yên cho tới khi admin xoá.
final hostMetricsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb
        .from('host_metrics')
        .select('*')
        .order('updated_at', ascending: false)));

Future<void> deleteHostMetrics(String host) =>
    sb.from('host_metrics').delete().eq('host', host);

/// Lệnh quản lí gần đây (mọi host) — tab Theo dõi VPS hiển thị lịch sử.
final hostCommandsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb
        .from('host_commands')
        .select('id, host, command, status, output, created_at')
        .order('created_at', ascending: false)
        .limit(10)));

/// Chèn lệnh vào hàng đợi — worker trên host tương ứng nhận thực thi trong ~10s.
/// Whitelist phía worker: restart | restart_crawler | restart_translator.
Future<void> sendHostCommand(String host, String command, {String? by}) =>
    sb.from('host_commands')
        .insert({'host': host, 'command': command, 'created_by': by});

/// Nhãn/địa chỉ hiển thị của 1 host — lưu worker_settings để chỉnh từ app mà không
/// đụng DB schema (key có gắn hostname nên nhiều host không giẫm nhau).
String _vpsKey(String host, String field) => 'vps_${field}_$host';

Future<Map<String, String>> loadVpsLabels(String host) async {
  final rows = List<Rec>.from(await sb
      .from('worker_settings')
      .select('key, value')
      .inFilter('key', [_vpsKey(host, 'label'), _vpsKey(host, 'address')]));
  return {
    for (final r in rows)
      if ((r['value'] as String? ?? '').isNotEmpty)
        r['key'].toString().split('_')[1]: r['value'] as String,
  };
}

Future<void> saveVpsLabels(String host,
    {required String label, required String address}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await Future.wait([
    sb.from('worker_settings').upsert({
      'key': _vpsKey(host, 'label'),
      'value': label,
      'note': 'Nhãn hiển thị VPS ($host)',
      'updated_at': now
    }),
    sb.from('worker_settings').upsert({
      'key': _vpsKey(host, 'address'),
      'value': address,
      'note': 'Địa chỉ/IP hiển thị VPS ($host)',
      'updated_at': now
    }),
  ]);
}

/// Truyện crawler mới đem về trong 24 giờ — tab Crawl (soi discovery có chạy không).
final newNovels24hProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  final since =
      DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
  return List<Rec>.from(await sb
      .from('novels')
      .select('id, title_vi, title_zh, cover_url, created_at, source_rank, '
          'chapter_count_source, status, sources(name)')
      .gte('created_at', since)
      .order('created_at', ascending: false));
});

/// Nhịp 24 giờ của crawler + translator cho tab Crawl: đủ để nhìn phát biết hệ thống
/// còn "thở" hay đứng, mà không phải mở log VPS. Toàn count() nên rẻ, không kéo bản ghi.
final crawlPulseProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final now = DateTime.now().toUtc();
  final since = now.subtract(const Duration(hours: 24)).toIso8601String();
  final hour = now.subtract(const Duration(hours: 1)).toIso8601String();
  final r = await Future.wait([
    sb.from('novels').count().gte('created_at', since),
    sb.from('chapters').count().gte('created_at', since), // dòng mục lục mới về
    sb.from('chapters').count().eq('translation_status', 'done').gte('translated_at', since),
    sb.from('chapters').count().eq('translation_status', 'queued'),
    sb.from('chapters').count().eq('translation_status', 'failed'),
    sb.from('novels').count().eq('meta_translated', false),
    sb.from('novels').count().eq('is_canonical', true).eq('hidden', false),
    sb.from('translation_jobs').count().eq('status', 'failed'),
    // nhịp thật của translator: 2 vCPU nên một chương dài có thể ngốn cả chục phút,
    // con số này cho biết ngay hệ thống đang bò hay đang chạy
    sb.from('chapters').count().eq('translation_status', 'done').gte('translated_at', hour),
  ]);
  return {
    'novels24h': r[0], 'chapters24h': r[1], 'done24h': r[2], 'queued': r[3],
    'failedChapters': r[4], 'metaPending': r[5], 'tracked': r[6], 'failedJobs': r[7],
    'done1h': r[8],
  };
});

/// Nhịp tim worker (crawler/translator điểm danh định kỳ) — tab Worker hiện sống/chết.
final workerHeartbeatProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb.from('worker_heartbeat').select('name, at, note')));

/// Chạy lại TẤT CẢ job lỗi + trả chương crawl-lỗi về hàng tải (migration 026).
/// Trả về số job được reset.
Future<int> retryAllFailed() async =>
    (await sb.rpc('admin_retry_all_failed')) as int? ?? 0;

/// Quét lỗi (admin): xếp 1 job 'audit' → worker quét chương done hỏng (còn tiếng Trung/
/// cụt/mất đoạn) và tự xếp lại dịch. Chống trùng ở RPC (chỉ 1 audit chạy 1 lúc).
Future<void> requestAudit() => sb.rpc('request_audit');

/// Quét lỗi dịch của một truyện; worker chỉ xét chương done của truyện này.
Future<void> requestNovelAudit(int novelId) =>
    sb.rpc('request_novel_audit', params: {'p_novel_id': novelId});

/// Dịch lại metadata (tên/mô tả/thể loại) 1 truyện — xếp job 'metadata', worker dịch lại
/// đè lên tên cũ theo prompt hiện tại. Dùng sau khi sửa prompt tên. RPC chống trùng.
Future<void> requestMetaRetranslate(int novelId) =>
    sb.rpc('request_meta', params: {'p_novel_id': novelId});

/// Huỷ 1 job: xoá job VÀ trả chương về 'none'. Không reset chương thì hàng đợi
/// (đọc từ chapters.translation_status) vẫn thấy chương đó → lệch như bug đã gặp.
Future<void> cancelJob(int jobId, int? chapterId) async {
  await sb.from('translation_jobs').delete().eq('id', jobId);
  if (chapterId != null) {
    await sb
        .from('chapters')
        .update({'translation_status': 'none'})
        .eq('id', chapterId)
        .neq('translation_status', 'done'); // đã dịch xong thì để yên
  }
}

/// Huỷ toàn bộ chương ĐANG CHỜ của 1 truyện (chương đang dịch để worker chạy nốt).
Future<void> cancelNovelQueue(int novelId) async {
  await sb
      .from('translation_jobs')
      .delete()
      .eq('novel_id', novelId)
      .eq('status', 'pending');
  await sb
      .from('chapters')
      .update({'translation_status': 'none'})
      .eq('novel_id', novelId)
      .eq('translation_status', 'queued');
}

Future<void> reprioritizeJob(int id, int priority) =>
    sb.from('translation_jobs').update({'priority': priority}).eq('id', id);

/// Xoá VĨNH VIỄN 1 truyện — FK cascade dọn sạch chapters/glossary/tiến độ/tủ sách/job.
Future<void> deleteNovel(int id) => sb.from('novels').delete().eq('id', id);

Future<void> resolveReport(int id) =>
    sb.from('glossary_reports').update({'resolved': true}).eq('id', id);
