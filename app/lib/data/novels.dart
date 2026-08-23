import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';

/// Cột SELECT chung cho mọi query truyện (Khám phá, Tủ sách, Tìm kiếm…).
/// Kèm source_id + sources(name) để hiện badge nguồn và trộn nguồn (round-robin).
const novelCols =
    'id, title_vi, title_zh, author_vi, author_zh, cover_url, status, '
    'chapter_count_source, chapter_count_translated, genres, description_vi, '
    'last_chapter_at, source_rank, source_id, sources(name)';

/// Danh sách truyện cho tab Khám phá (mới cập nhật trước).
final novelsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  return List<Rec>.from(
    await sb
        .from('novels')
        .select(
          'id, title_vi, title_zh, author_vi, author_zh, cover_url, status, '
          'chapter_count_source, chapter_count_translated, genres, description_vi, '
          'source_id, sources(name)',
        )
        .eq('hidden', false)
        .eq(
          'is_canonical',
          true,
        ) // ẩn bản trùng từ nguồn khác (Phase 2 multi-source)
        .order('updated_at', ascending: false)
        .limit(50),
  );
});

final novelProvider = FutureProvider.autoDispose.family<Rec, int>((
  ref,
  id,
) async {
  return await sb.from('novels').select('*, sources(name)').eq('id', id).single();
});

/// Nhãn tiếng Việt cho trạng thái truyện; trạng thái lạ (crawl mới) hiện nguyên văn.
const _statusLabels = {
  'ongoing': 'Đang ra',
  'completed': 'Hoàn thành',
  'hiatus': 'Tạm ngưng',
};
String statusLabel(String s) => _statusLabels[s] ?? s;

/// Tên nguồn crawl (slug) để hiện badge; rỗng nếu chưa join sources.
String sourceName(Rec n) =>
    ((n['sources'] as Map?)?['name'] as String?)?.trim() ?? '';

/// Các mốc "số chương tối thiểu" ≤ số chương lớn nhất trong kho (sinh động theo dữ liệu).
List<int> minChapterThresholds(int maxChapters) => [
  0,
  ...[100, 500, 1000, 2000, 3000, 5000, 10000].where((t) => t <= maxChapters),
];

// ---------- Tìm kiếm + lọc ----------

/// Bộ lọc tìm truyện (dùng làm key cho family provider).
class SearchFilter {
  final String query;
  final int minChapters;
  final String? genre;
  final String? status; // 'ongoing' | 'completed' | null
  final List<int>? sources; // source_id chọn lọc; null/empty = mọi nguồn
  const SearchFilter({
    this.query = '',
    this.minChapters = 0,
    this.genre,
    this.status,
    this.sources,
  });

  bool get isEmpty =>
      query.isEmpty && minChapters == 0 && genre == null && status == null &&
      (sources == null || sources!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is SearchFilter &&
      other.query == query &&
      other.minChapters == minChapters &&
      other.genre == genre &&
      other.status == status &&
      _listEq(other.sources, sources);
  @override
  int get hashCode => Object.hash(query, minChapters, genre, status,
      Object.hashAll(sources ?? const []));
}

bool _listEq(List<int>? a, List<int>? b) {
  if (a == null || a.isEmpty) return b == null || b.isEmpty;
  if (b == null || b.isEmpty) return false;
  return a.length == b.length && {...a}.containsAll(b);
}

final searchProvider = FutureProvider.autoDispose.family<List<Rec>, SearchFilter>((
  ref,
  f,
) async {
  var q = sb
      .from('novels')
      .select(novelCols)
      .eq('hidden', false)
      .eq('is_canonical', true);
  if (f.query.isNotEmpty) {
    // Tìm cả tên/tác giả tiếng Việt LẪN tiếng Trung (truyện chưa dịch metadata, hoặc
    // user gõ tên gốc). Bỏ dấu phẩy trong query để không phá cú pháp or() của PostgREST.
    final s = f.query.replaceAll(',', ' ');
    q = q.or(
      'title_vi.ilike.%$s%,title_zh.ilike.%$s%,'
      'author_vi.ilike.%$s%,author_zh.ilike.%$s%',
    );
  }
  if (f.minChapters > 0) q = q.gte('chapter_count_source', f.minChapters);
  if (f.status != null) q = q.eq('status', f.status!);
  if (f.genre != null) q = q.contains('genres', [f.genre!]);
  if (f.sources != null && f.sources!.isNotEmpty) {
    q = q.inFilter('source_id', f.sources!);
  }
  // Sắp theo độ MỚI (chương mới nhất) chứ không theo số chương — lọc "tối thiểu N chương"
  // chỉ là điều kiện, không phải tiêu chí sắp xếp.
  return List<Rec>.from(
    await q
        .order('last_chapter_at', ascending: false, nullsFirst: false)
        .limit(60),
  );
});

/// Danh sách thể loại có trong DB (cho bộ lọc).
final genresProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final rows = List<Rec>.from(
    await sb
        .from('novels')
        .select('genres')
        .not('genres', 'is', null)
        .limit(300),
  );
  final set = <String>{};
  for (final r in rows) {
    for (final g in (r['genres'] as List? ?? const [])) {
      final s = g.toString().trim();
      if (s.isNotEmpty) set.add(s);
    }
  }
  final list = set.toList()..sort();
  return list;
});

/// Nguồn crawl đang bật (cho bộ lọc theo nguồn). Đọc thẳng bảng sources — bảng này
/// có policy đọc công khai nên user thường xem được; suy từ novels thì sót nguồn
/// chưa có/khó có truyện hiển thị.
final filterSourcesProvider = FutureProvider.autoDispose<List<(int, String)>>((ref) async {
  final rows = List<Rec>.from(await sb
      .from('sources')
      .select('id, name')
      .eq('enabled', true)
      .order('name'));
  return [for (final r in rows) (r['id'] as int, '${r['name']}')];
});

// ---------- Trang chủ ----------

/// Các mục trang chủ. Hiện suy từ dữ liệu sẵn có; khi có crawl "trang chủ nguồn"
/// thì thay bằng bảng phân mục thật.
/// ponytail: 1 query rồi chia nhóm phía client — hợp quy mô nhỏ, tránh 4 round-trip.
class HomeSections {
  final List<Rec> latest, featured, recommended, completed;
  HomeSections(this.latest, this.featured, this.recommended, this.completed);
}

final homeSectionsProvider = FutureProvider.autoDispose<HomeSections>((
  ref,
) async {
  // Dùng CHUNG fetchNovelPage với màn "Xem tất cả" — trang chủ = trang 1 của từng
  // mục, bấm vào xem tất cả thấy đúng danh sách nối dài, không lệch nhau nữa.
  // (Trước đây trang chủ sort cục bộ trên 60 truyện mới nhất → khác hẳn xem-tất-cả.)
  final r = await Future.wait([
    fetchNovelPage(SectionKind.latest, 0, 15),
    fetchNovelPage(SectionKind.featured, 0, 15),
    fetchNovelPage(SectionKind.recommended, 0, 15),
    fetchNovelPage(SectionKind.completed, 0, 15),
  ]);
  return HomeSections(r[0], r[1], r[2], r[3]);
});

/// Các mục Khám phá có màn "Xem tất cả" (cuộn tải dần). Mỗi mục 1 kiểu sort riêng.
enum SectionKind { latest, featured, recommended, completed }

const sectionTitles = {
  SectionKind.latest: 'Mới cập nhật',
  SectionKind.featured: 'Nổi bật',
  SectionKind.recommended: 'Đề cử',
  SectionKind.completed: 'Đã hoàn thành',
};

/// Kích thước "hồ" truyện lấy về để trộn nguồn cho Nổi bật/Đề cử — đủ lớn để mọi
/// nguồn góp mặt, đủ nhỏ để trộn phía client 1 lần (hợp quy mô kho hiện tại).
const _mixPoolSize = 240;

/// 1 lô truyện của 1 mục (cho màn "Xem tất cả" phân trang). offset = số đã có.
Future<List<Rec>> fetchNovelPage(SectionKind kind, int offset, int limit) async {
  var f = sb
      .from('novels')
      .select(novelCols)
      .eq('hidden', false)
      .eq('meta_translated', true) // đồng bộ với homeSectionsProvider — ẩn tên tiếng Trung
      .eq('is_canonical', true);
  if (kind == SectionKind.completed) f = f.eq('status', 'completed');
  if (kind == SectionKind.latest) f = f.neq('status', 'completed'); // Mới cập nhật: chỉ đang ra
  if (kind == SectionKind.recommended) f = f.neq('status', 'completed');

  // Mới cập nhật / Đã hoàn thành: sort thẳng theo độ mới rồi phân trang bằng range.
  // tie-break id: nhiều truyện cùng last_chapter_at → phân trang ổn định, không lặp/sót.
  if (kind == SectionKind.latest || kind == SectionKind.completed) {
    return List<Rec>.from(await f
        .order('last_chapter_at', ascending: false, nullsFirst: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1));
  }

  // Nổi bật / Đề cử: chỉ shuhaige có source_rank, 3/4 nguồn còn lại NULL. Nếu sort
  // thẳng source_rank thì 1 nguồn đè hết + đứng yên (rank là tổng lượt đọc TOÀN THỜI
  // GIAN). Nên lấy 1 "hồ" rồi TRỘN NGUỒN (round-robin) phía client: nguồn có rank dẫn
  // đầu, nguồn NULL xếp theo độ mới nên mục tự đổi khi có chương mới. Phạm vi khác
  // nhau: Nổi bật = toàn kho; Đề cử = chỉ truyện đang ra. Phân trang = cắt trên hồ đã trộn.
  final pool = List<Rec>.from(await f
      .order('source_rank', ascending: true, nullsFirst: false)
      .order('last_chapter_at', ascending: false, nullsFirst: false)
      .order('id', ascending: false)
      .limit(_mixPoolSize));
  var mixed = _roundRobinBySource(pool);
  // Xoay vòng theo NGÀY: rank là số tĩnh nên trộn xong thứ tự vẫn đứng yên nhiều ngày
  // ("Nổi bật" nhìn như đóng băng). Chạy đầu danh sách đi một bước mỗi ngày — cùng ngày
  // thì home và xem-tất-cả thấy cùng danh sách (phân trang không nhảy), hôm sau đổi mới.
  if (mixed.length > 6) {
    final day = DateTime.now().toUtc().difference(DateTime.utc(2024)).inDays;
    final off = day % mixed.length;
    mixed = [...mixed.sublist(off), ...mixed.sublist(0, off)];
  }
  if (offset >= mixed.length) return const [];
  return mixed.sublist(offset, (offset + limit).clamp(0, mixed.length));
}

/// Trộn truyện theo nguồn (round-robin) để Nổi bật/Đề cử không bị 1 nguồn đè.
/// Giữ nguyên thứ tự trong từng nhóm (query đã sort sẵn); nhóm có source_rank đứng
/// trước, các nhóm NULL còn lại xếp theo chương mới nhất.
List<Rec> _roundRobinBySource(List<Rec> pool) {
  final groups = <Object, List<Rec>>{};
  for (final n in pool) {
    (groups[n['source_id'] ?? 0] ??= <Rec>[]).add(n);
  }
  int rankOf(List<Rec> g) => (g.first['source_rank'] as int?) ?? (1 << 30);
  String recOf(List<Rec> g) => (g.first['last_chapter_at'] as String?) ?? '';
  final order = groups.values.toList()
    ..sort((a, b) {
      final r = rankOf(a).compareTo(rankOf(b));
      return r != 0 ? r : recOf(b).compareTo(recOf(a)); // mới hơn trước
    });
  final out = <Rec>[];
  for (var i = 0;; i++) {
    var added = false;
    for (final g in order) {
      if (i < g.length) {
        out.add(g[i]);
        added = true;
      }
    }
    if (!added) break;
  }
  return out;
}
