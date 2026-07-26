import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';

/// Số job pending tối đa kéo về. `active` là CỬA SỔ đầu hàng đợi, không phải toàn bộ:
/// hàng đợi thật thường vài nghìn job, nên ô đếm phải dùng [QueueState.pendingTotal].
const kQueueWindow = 200;

class QueueState {
  final List<Rec> active; // translating / queued / downloading / source_unavailable
  final List<Rec> recentDone; // chương vừa dịch xong (để không "mất tích")
  final int doneLastHour; // thông lượng ~1h gần đây
  final int pendingTotal; // tổng job chờ THẬT trong DB (≥ số dòng trong `active`)
  QueueState(this.active, this.recentDone, this.doneLastHour, this.pendingTotal);
}

/// Nguồn crawl của job đã tắt? (dùng cho cả queue lẫn admin).
bool jobSourceUnavailable(Rec job) {
  final novel = job['novels'] as Map?;
  final source = novel?['sources'] as Map?;
  return source?['enabled'] == false;
}

/// Chương đang dịch/chờ + tốc độ (số chương xong trong ~1h). Đồng bộ chung mọi user.
final translateQueueProvider = FutureProvider.autoDispose<QueueState>((
  ref,
) async {
  // Đọc từ `translation_jobs` (nguồn sự thật của hàng đợi, CÓ priority) chứ không từ
  // chapters.status → (1) ưu tiên cao (truyện đang đọc, pri nhỏ) nổi lên đầu, (2) không
  // dính "chương mồ côi" (status kẹt nhưng job đã xoá).
  const jobCols = 'priority, status, novel_id, chapter_id, '
      'chapters(chapter_index, title_vi, title_zh), '
      'novels(title_vi, title_zh, cover_url, chapter_count_translated, '
      'chapter_count_source, sources(name, enabled))';
  // Job RUNNING lấy riêng (chỉ vài dòng): worker chọn job theo lane riêng nên job
  // đang chạy có thể priority CAO HƠN 200 job pending đầu → dính limit là "mất tích".
  final running = List<Rec>.from(
    await sb
        .from('translation_jobs')
        .select(jobCols)
        .eq('type', 'chapter')
        .eq('status', 'running'),
  );
  final pending = List<Rec>.from(
    await sb
        .from('translation_jobs')
        .select(jobCols)
        .eq('type', 'chapter')
        .eq('status', 'pending')
        // Khớp thứ tự claim của worker (`order by priority, created_at`).
        .order('priority', ascending: true) // nhỏ = ưu tiên cao → lên đầu
        .order('created_at', ascending: true)
        .limit(kQueueWindow),
  );
  final pendingTotal = (await sb
          .from('translation_jobs')
          .select('id')
          .eq('type', 'chapter')
          .eq('status', 'pending')
          .count(CountOption.exact))
      .count;
  final jobs = [...running, ...pending];
  // Chương pending mà content_zh CHƯA tải về = crawler đang lấy nguồn → "đang tải".
  // Truy vấn nhẹ (chỉ id, content_zh null) trên đúng các chapter_id đang chờ.
  final pendingIds = [
    for (final j in jobs)
      if (j['status'] == 'pending' && j['chapter_id'] != null) j['chapter_id'] as int
  ];
  final downloading = <int>{};
  if (pendingIds.isNotEmpty) {
    final rows = List<Rec>.from(await sb
        .from('chapters')
        .select('id')
        .inFilter('id', pendingIds)
        .isFilter('content_zh', null));
    downloading.addAll(rows.map((r) => r['id'] as int));
  }
  // Thiếu content chỉ là "đang tải" khi nguồn còn bật; nguồn tắt là blocked.
  final active = <Rec>[
    for (final j in jobs)
      if (j['chapters'] != null)
        {
          'novel_id': j['novel_id'],
          'chapter_index': (j['chapters'] as Map)['chapter_index'],
          'title_vi': (j['chapters'] as Map)['title_vi'],
          'title_zh': (j['chapters'] as Map)['title_zh'],
          'translation_status': j['status'] == 'running'
              ? 'translating'
              : downloading.contains(j['chapter_id'])
                  ? (jobSourceUnavailable(j) ? 'source_unavailable' : 'downloading')
                  : 'queued',
          'novels': j['novels'],
        },
  ];
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 1))
      .toIso8601String();
  // "Xoá lịch sử vừa dịch xong": mốc user bấm xoá (local) — chỉ hiện chương xong SAU mốc đó.
  final cleared = prefs.getString('queue_done_cleared_at');
  final lower = (cleared != null && cleared.compareTo(since) > 0) ? cleared : since;
  // Chương vừa dịch xong (mới → cũ) — hiện ở mục "Vừa dịch xong" thay vì biến mất.
  final recentDone = List<Rec>.from(
    await sb
        .from('chapters')
        .select('chapter_index, title_vi, novel_id, translated_at, '
            'novels(title_vi, title_zh, cover_url)')
        .eq('translation_status', 'done')
        .gte('translated_at', lower)
        .order('translated_at', ascending: false)
        .limit(60),
  );
  return QueueState(active, recentDone, recentDone.length, pendingTotal);
});

/// Xoá "lịch sử vừa dịch xong" trên máy (chỉ ẩn hiển thị, không đụng dữ liệu dịch).
Future<void> clearQueueDone() =>
    prefs.setString('queue_done_cleared_at', DateTime.now().toUtc().toIso8601String());
