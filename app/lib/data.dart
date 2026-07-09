import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline.dart';

final sb = Supabase.instance.client;

/// Gán trong main() trước runApp.
late final SharedPreferences prefs;

/// Phát mỗi lần đăng nhập/đăng xuất → mọi provider phụ thuộc auth watch cái này
/// để tự nạp lại (nếu không, đăng nhập xong UI vẫn kẹt ở trạng thái cũ).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => sb.auth.onAuthStateChange,
);

/// Tiến độ đọc trong 1 chương (0..1) — lưu local theo máy để khôi phục vị trí cuộn + hiện %.
Future<void> saveChapterPercent(int novelId, int idx, double pct) =>
    prefs.setDouble('rp_${novelId}_$idx', pct.clamp(0, 1));
double chapterPercent(int novelId, int idx) =>
    prefs.getDouble('rp_${novelId}_$idx') ?? 0;

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
const tabEmblems = ['taiji', 'compass', 'array', 'orb', 'mirror', 'jade'];

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

/// Avatar preset (emoji) — không cần upload ảnh; lưu thẳng ký tự vào profiles.avatar_url.
const avatarPresets = [
  '📖', '🐉', '⚔️', '🦊', '🌙', '🔥', '🗡️', '🏯', '🐼', '🎭', '🌸', '👑',
  // bổ sung: linh thú, ngũ hành, tiên gia
  '☯️', '🐯', '🦅', '🐍', '🐢', '🦋', '🪷', '🏮', '🧧', '🌊', '⛰️', '🍃',
  '❄️', '⚡', '💎', '🌟', '🗿', '🎋', '🦉', '🌺',
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

// ponytail: model = Map từ PostgREST, chưa cần freezed — thêm khi model phình/nhiều màn dùng chung
typedef Rec = Map<String, dynamic>;

/// Danh sách truyện cho tab Khám phá (mới cập nhật trước).
final novelsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  return List<Rec>.from(
    await sb
        .from('novels')
        .select(
          'id, title_vi, title_zh, author_vi, author_zh, cover_url, status, '
          'chapter_count_source, chapter_count_translated, genres, description_vi',
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
  return await sb.from('novels').select().eq('id', id).single();
});

/// Nhãn tiếng Việt cho trạng thái truyện; trạng thái lạ (crawl mới) hiện nguyên văn.
const _statusLabels = {
  'ongoing': 'Đang ra',
  'completed': 'Hoàn thành',
  'hiatus': 'Tạm ngưng',
};
String statusLabel(String s) => _statusLabels[s] ?? s;

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
  const SearchFilter({
    this.query = '',
    this.minChapters = 0,
    this.genre,
    this.status,
  });

  bool get isEmpty =>
      query.isEmpty && minChapters == 0 && genre == null && status == null;

  @override
  bool operator ==(Object other) =>
      other is SearchFilter &&
      other.query == query &&
      other.minChapters == minChapters &&
      other.genre == genre &&
      other.status == status;
  @override
  int get hashCode => Object.hash(query, minChapters, genre, status);
}

final searchProvider = FutureProvider.autoDispose.family<List<Rec>, SearchFilter>((
  ref,
  f,
) async {
  var q = sb
      .from('novels')
      .select(_novelCols)
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

// ---------- Hàng đợi dịch ----------

class QueueState {
  final List<Rec> active; // chương translating / queued / downloading (kèm tên truyện)
  final List<Rec> recentDone; // chương vừa dịch xong (để không "mất tích")
  final int doneLastHour; // thông lượng ~1h gần đây
  QueueState(this.active, this.recentDone, this.doneLastHour);
}

/// Chương đang dịch/chờ + tốc độ (số chương xong trong ~1h). Đồng bộ chung mọi user.
final translateQueueProvider = FutureProvider.autoDispose<QueueState>((
  ref,
) async {
  // Đọc từ `translation_jobs` (nguồn sự thật của hàng đợi, CÓ priority) chứ không từ
  // chapters.status → (1) ưu tiên cao (truyện đang đọc, pri nhỏ) nổi lên đầu, (2) không
  // dính "chương mồ côi" (status kẹt nhưng job đã xoá).
  final jobs = List<Rec>.from(
    await sb
        .from('translation_jobs')
        .select(
          'priority, status, novel_id, chapter_id, '
          'chapters(chapter_index, title_vi, title_zh), '
          'novels(title_vi, title_zh, cover_url, chapter_count_translated, chapter_count_source)',
        )
        .eq('type', 'chapter')
        .inFilter('status', ['pending', 'running'])
        .order('priority', ascending: true) // nhỏ = ưu tiên cao → lên đầu
        .order('created_at', ascending: true)
        .limit(200),
  );
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
  // Chuẩn hoá về shape UI hàng đợi dùng (running→translating; pending→queued/downloading).
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
              : (downloading.contains(j['chapter_id']) ? 'downloading' : 'queued'),
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
  return QueueState(active, recentDone, recentDone.length);
});

/// Xoá "lịch sử vừa dịch xong" trên máy (chỉ ẩn hiển thị, không đụng dữ liệu dịch).
Future<void> clearQueueDone() =>
    prefs.setString('queue_done_cleared_at', DateTime.now().toUtc().toIso8601String());

const _novelCols =
    'id, title_vi, title_zh, author_vi, author_zh, cover_url, status, '
    'chapter_count_source, chapter_count_translated, genres, description_vi, last_chapter_at, source_rank';

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

/// 1 lô truyện của 1 mục (cho màn "Xem tất cả" phân trang). offset = số đã có.
Future<List<Rec>> fetchNovelPage(SectionKind kind, int offset, int limit) async {
  var f = sb
      .from('novels')
      .select(_novelCols)
      .eq('hidden', false)
      .eq('meta_translated', true) // đồng bộ với homeSectionsProvider — ẩn tên tiếng Trung
      .eq('is_canonical', true);
  if (kind == SectionKind.completed) f = f.eq('status', 'completed');
  if (kind == SectionKind.latest) f = f.neq('status', 'completed'); // Mới cập nhật: chỉ đang ra
  // Cả Nổi bật lẫn Đề cử đều theo BẢNG XẾP HẠNG NGUỒN (rank nhỏ = hot, số chương
  // dịch không dùng để xếp hạng). Khác phạm vi: Nổi bật = toàn kho (đỉnh bảng đa số
  // là truyện hoàn thành kinh điển); Đề cử = CHỈ truyện đang ra (hot còn ra chương).
  // Lưu ý: đừng lọc theo last_chapter_at — crawler refresh bump mốc đó liên tục
  // nên lọc "14 ngày" trúng cả kho, hai mục thành một.
  if (kind == SectionKind.recommended) f = f.neq('status', 'completed');
  // sort đúng ngữ nghĩa từng mục (khớp cách chia ở homeSectionsProvider)
  final ordered = switch (kind) {
    SectionKind.featured ||
    SectionKind.recommended => f.order('source_rank', ascending: true, nullsFirst: false),
    SectionKind.latest ||
    SectionKind.completed => f.order('last_chapter_at',
        ascending: false, nullsFirst: false),
  };
  // tie-break id: nhiều truyện cùng giá trị sort (vd last_chapter_at null) → phân trang
  // ổn định, không lặp/sót truyện ở ranh giới trang.
  return List<Rec>.from(
      await ordered.order('id', ascending: false).range(offset, offset + limit - 1));
}

/// Tủ truyện: truyện user đang đọc (có tiến độ), kèm chương đang đọc + tổng chương.
final readingProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  ref.watch(authStateProvider); // đăng nhập/xuất → nạp lại tủ truyện
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = List<Rec>.from(
    await sb
        .from('reading_progress')
        .select('chapter_index, updated_at, novels($_novelCols)')
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
        callback: (_) => ref.invalidateSelf(),
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

// ---------- Yêu cầu truyện (nhập tên tiếng Trung → worker tìm nguồn crawl về) ----------

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

// ---------- Glossary ----------

/// Term của truyện + term global; gồm cả gợi ý chưa duyệt (cần login mới thấy).
final glossaryProvider = FutureProvider.autoDispose.family<List<Rec>, int>((
  ref,
  novelId,
) async {
  return List<Rec>.from(
    await sb
        .from('glossary_terms')
        .select('id, term_zh, wrong_vi, correct_vi, term_type, scope, approved')
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
final adminNovelsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  // tải ĐỦ mọi truyện, page qua trần 1000 dòng/query của PostgREST — limit(200) cũ
  // làm số đếm chip Tất cả/Hiển thị/Ẩn lệch với thống kê (đếm count toàn DB)
  final out = <Rec>[];
  for (var from = 0;; from += 1000) {
    final batch = List<Rec>.from(
      await sb
          .from('novels')
          .select(
            'id, title_vi, title_zh, author_vi, status, hidden, source_id, is_canonical, '
            'meta_translated, source_rank, last_chapter_at, updated_at, '
            'chapter_count_source, chapter_count_translated, cover_url, sources(name)',
          )
          .order('updated_at', ascending: false)
          .range(from, from + 999),
    );
    out.addAll(batch);
    if (batch.length < 1000) return out;
  }
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
    sb.from('chapters').count(), // tổng chương đã sync mục lục
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

/// Job đáng chú ý: đang chạy / lỗi / chờ (bỏ done). Kèm tên truyện + số chương.
final adminJobsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  final jobs = List<Rec>.from(
    await sb
        .from('translation_jobs')
        .select(
          'id, type, status, priority, attempts, error, created_at, started_at, '
          'novel_id, chapter_id, novels(title_vi, title_zh), chapters(chapter_index)',
        )
        .inFilter('status', ['running', 'failed', 'pending'])
        .neq('type', 'audit') // audit là job toàn cục (novel_id null) → không gộp theo truyện
        .order('priority', ascending: true) // ưu tiên cao (pri nhỏ, truyện đang đọc) lên đầu
        .order('created_at', ascending: false)
        .limit(120),
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

/// Báo cáo CHƯƠNG dịch lỗi (nút Báo cáo cuối chương) — dùng chung hộp glossary_reports
/// (term_id null), admin xem ở màn Quản trị.
Future<void> reportChapter(int novelId, int chapterIndex, String reason) =>
    sb.from('glossary_reports').insert({
      'novel_id': novelId,
      'reason': 'Chương $chapterIndex: $reason',
      'reported_by': sb.auth.currentUser!.id,
    });

/// Người đọc báo cáo 1 term dịch sai → admin soi (không tự xoá để tránh phá glossary).
Future<void> reportTerm(int termId, int novelId, String reason) =>
    sb.from('glossary_reports').insert({
      'term_id': termId,
      'novel_id': novelId,
      'reason': reason,
      'reported_by': sb.auth.currentUser!.id,
    });
