import 'package:flutter/painting.dart';

import '../../data/core.dart' show boDau;
import '../../tts.dart';

/// Vùng chữ đang chọn để sửa: khối chứa + vị trí đầu/cuối trong khối.
typedef Sel = ({String block, int start, int end});

// ---------------- Ranh giới từ (chạm-sửa) — thuần Dart, unit-test được ----------------

/// Ranh giới từ để chạm-sửa: dấu ngoặc, nháy, phẩy, hai chấm… không thuộc từ.
bool isWordChar(String s, int i) {
  final c = s.codeUnitAt(i);
  return (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5a) || // A-Z
      (c >= 0x61 && c <= 0x7a) || // a-z
      (c >= 0x00c0 && c <= 0x024f) || // Latin có dấu
      (c >= 0x1e00 && c <= 0x1eff) || // tiếng Việt có dấu
      (c >= 0x3400 && c <= 0x9fff) || // chữ Hán còn sót
      c == 0x5f; // _
}

int _wordIndex(String s, int offset) {
  var i = offset.clamp(0, s.length).toInt();
  if (i < s.length && isWordChar(s, i)) return i;
  if (i > 0 && isWordChar(s, i - 1)) return i - 1;
  while (i < s.length && !isWordChar(s, i)) { i++; }
  return i == s.length ? -1 : i;
}

int wordLeft(String s, int offset) {
  var i = _wordIndex(s, offset);
  if (i < 0) return s.length;
  while (i > 0 && isWordChar(s, i - 1)) { i--; }
  return i;
}

int wordRight(String s, int offset) {
  var i = _wordIndex(s, offset);
  if (i < 0) return s.length;
  while (i < s.length && isWordChar(s, i)) { i++; }
  return i;
}

int previousWordStart(String s, int before) {
  final clamped = before.clamp(0, s.length).toInt();
  var i = clamped - 1;
  while (i >= 0 && !isWordChar(s, i)) { i--; }
  return i < 0 ? clamped : wordLeft(s, i);
}

bool _isGapSpace(String s, int i) {
  final c = s.codeUnitAt(i);
  return c == 0x20 || c == 0x09; // chỉ space/tab là "khoảng trắng nối từ"
}

/// Mở rộng vùng chọn sang PHẢI một từ — nhưng CHỈ khi cách bởi khoảng trắng, gặp dấu
/// câu (", : ; . …) thì dừng, không nuốt dấu vào vùng sửa (sửa thường 1-2 từ sạch).
int extendRightWord(String s, int end) {
  var j = end;
  while (j < s.length && _isGapSpace(s, j)) { j++; }
  if (j >= s.length || !isWordChar(s, j)) return end; // sau khoảng trắng là dấu/hết → giữ nguyên
  while (j < s.length && isWordChar(s, j)) { j++; }
  return j;
}

/// Mở rộng sang TRÁI một từ, cùng luật: chỉ vượt khoảng trắng, không nuốt dấu câu.
int extendLeftWord(String s, int start) {
  var j = start;
  while (j > 0 && _isGapSpace(s, j - 1)) { j--; }
  if (j <= 0 || !isWordChar(s, j - 1)) return start;
  while (j > 0 && isWordChar(s, j - 1)) { j--; }
  return j;
}

int nextWordEnd(String s, int from) {
  final clamped = from.clamp(0, s.length).toInt();
  var i = clamped;
  while (i < s.length && !isWordChar(s, i)) { i++; }
  return i == s.length ? clamped : wordRight(s, i);
}

// Từ nối/đại từ hay đứng ĐẦU CÂU nên viết hoa — không phải âm tiết của tên. Thiếu luật
// này thì chạm "Thôn Thiên Nga" ở câu "Nếu Thôn Thiên Nga ở đây" gom luôn "Nếu", lưu bản
// sửa là mất chữ "Nếu" khỏi câu (thấy trên máy thật 23/09, chương 229 truyện 34700).
const _dauCau = {
  'nếu', 'nhưng', 'khi', 'thì', 'và', 'còn', 'lúc', 'sau', 'trước', 'tại', 'ở', 'chỉ',
  'đến', 'từ', 'vì', 'bởi', 'tuy', 'dù', 'mà', 'rồi', 'để', 'với', 'cho', 'có', 'không',
  'đây', 'đó', 'này', 'hắn', 'nàng', 'ta', 'ngươi', 'họ', 'chúng', 'các', 'những',
  'một', 'cả', 'ngay', 'đã', 'đang', 'sẽ', 'cũng', 'đúng', 'vậy', 'giờ',
  'nhìn', 'thấy', 'nói', 'là', 'bị', 'được', 'trong', 'ngoài', 'trên', 'dưới',
};

/// Chạm trúng 1 âm tiết VIẾT HOA (tên riêng Hán-Việt nhiều âm tiết: "Trần Đại Chinh")
/// → nuốt TRỌN cụm âm tiết viết hoa liền nhau, dừng ở từ thường/dấu câu. Từ thường
/// ("hệ thống") → giữ nguyên 1 từ (khỏi quơ trúng từ bên cạnh làm hỏng gợi ý theo tên).
(int, int) nameRunBounds(String s, int a, int b) {
  bool capAt(int i) {
    if (i < 0 || i >= s.length) return false;
    final ch = s[i];
    return ch.toUpperCase() == ch && ch.toLowerCase() != ch; // chữ CÁI viết hoa
  }
  if (!capAt(a)) return (a, b);
  var start = a, end = b;
  while (true) {
    final na = extendLeftWord(s, start);
    if (na == start || !capAt(na)) break;
    start = na;
  }
  while (true) {
    final nb = extendRightWord(s, end);
    if (nb == end) break;
    var w = end; // đầu âm tiết vừa với tới
    while (w < nb && !isWordChar(s, w)) { w++; }
    if (!capAt(w)) break; // âm tiết kế viết thường → không nuốt
    end = nb;
  }
  // bỏ từ nối đầu câu khỏi tên (còn ít nhất một từ viết hoa phía sau)
  while (true) {
    final w0 = wordRight(s, start);
    final next = extendRightWord(s, w0);
    if (w0 >= end || next > end || !_dauCau.contains(s.substring(start, w0).toLowerCase())) break;
    var w = w0;
    while (w < end && !isWordChar(s, w)) { w++; }
    start = w;
  }
  return (start, end);
}

/// Bản dịch cũ có thể đã chép đuôi chương trước do model nhìn thấy context.
/// Chỉ ẩn các đoạn đầu khớp nguyên văn đuôi trước; dữ liệu DB không bị sửa khi đọc.
String withoutLeadingPreviousEcho(String current, String? previous) {
  if (previous == null || previous.trim().isEmpty) return current;
  final tail = previous.trim();
  final lines = current.split('\n');
  while (lines.isNotEmpty) {
    final lead = lines.first.trim();
    if (lead.length < 20 || !tail.contains(lead)) break;
    lines.removeAt(0);
  }
  return lines.join('\n').trimLeft();
}

// ---------------- Phân trang chế độ lật trang (thuần TextPainter) ----------------

/// Cắt văn bản thành các trang vừa 1 màn (Exponential search + nhị phân có chặn trên).
List<String> paginateText(
    String text, TextStyle style, double maxWidth, double pageH, double firstH) {
  final pages = <String>[];
  final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: null);
  final n = text.length;
  final fontSize = style.fontSize ?? 16.0;
  final lineHeight = fontSize * (style.height ?? 1.3);
  int start = 0;

  try {
    while (start < n) {
      final limit = pages.isEmpty ? firstH : pageH;

      // Ước lượng bước nhảy ban đầu dựa trên kích thước font và khung hình
      final linesEst = (limit / lineHeight).ceil().clamp(1, 200);
      final charsPerLineEst = (maxWidth / (fontSize * 0.55)).ceil().clamp(10, 150);
      int step = (linesEst * charsPerLineEst).clamp(60, 3000);

      int lo = start + 1;
      int hi = n;

      // Exponential search: Tìm khoảng chặn trên [lo, hi] hẹp trước khi nhị phân,
      // tránh gọi layout trên toàn bộ chuỗi khổng lồ (n hàng chục nghìn ký tự).
      int probe = start + step;
      while (probe < n) {
        tp.text = TextSpan(text: text.substring(start, probe), style: style);
        tp.layout(maxWidth: maxWidth);
        if (tp.height <= limit) {
          lo = probe;
          step *= 2;
          probe = (start + step).clamp(start + 1, n);
        } else {
          hi = probe;
          break;
        }
      }

      int best = lo;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        tp.text = TextSpan(text: text.substring(start, mid), style: style);
        tp.layout(maxWidth: maxWidth);
        if (tp.height <= limit) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }

      int end = best;
      if (end < n) {
        // lùi về khoảng trắng gần nhất để không cắt giữa từ
        final ws = text.lastIndexOf(RegExp(r'\s'), end - 1);
        if (ws > start) end = ws + 1;
      }
      if (end <= start) end = (start + 1).clamp(0, n); // an toàn, tránh lặp vô hạn
      pages.add(text.substring(start, end).trim());
      start = end;
    }
  } finally {
    tp.dispose();
  }

  if (pages.isEmpty) pages.add('');
  return pages;
}

// ---------------- Logic highlight TTS (thuần, so khớp trạng thái máy đọc) ----------------

/// Đoạn nội dung máy đọc đang đọc TRÊN chương này (-1 = không phải chương đang nghe /
/// đang tạm dừng / đang đọc tiêu đề). Reader mirror giá trị này để highlight + cuộn theo.
/// [paraAt] truyền từ TtsPlayer.i.paraAt.value (nằm trên player, không trên state).
int ttsLocalPara(TtsState st,
        {required int novelId, required int chapterIndex, required int paraAt}) =>
    (st.active &&
            st.novelId == novelId &&
            st.chapterIndex == chapterIndex &&
            !st.paused)
        ? paraAt
        : -1;

/// Máy đọc đã tự sang CHƯƠNG KHÁC (cùng truyện) và đang phát → reader nên chuyển màn
/// theo cho khớp (không thì tiếng đọc chương sau mà màn hình kẹt chương cũ).
bool ttsMovedAway(TtsState st, {required int novelId, required int chapterIndex}) =>
    st.active &&
    st.playing &&
    st.novelId == novelId &&
    st.chapterIndex != chapterIndex;

// ---------------- Dò vùng thuật ngữ để tô dấu (thuần Dart, unit-test được) ----------------

/// Các đoạn trong [text] trùng một thuật ngữ của truyện → [(đầu, cuối)], không chồng nhau.
///
/// Dùng để tô dấu chỗ bản dịch đã được glossary áp vào ("Áp cả truyện" chạy thay chuỗi,
/// xong rồi trang đọc không còn dấu vết gì — người đọc không biết chỗ nào do máy chỉnh,
/// mà chính mình cũng không soi được glossary có vá bậy không).
///
/// Khớp theo RANH GIỚI TỪ y như chạm-sửa: `replace_word` phía worker cũng thay theo ranh
/// giới từ, nên tô dấu phải cùng luật, kẻo hiện một đằng vá một nẻo. Phân biệt hoa/thường
/// vì thuật ngữ là tên riêng — khớp lỏng sẽ dính "hiên" trong "hiên nhà".
///
/// Term dài khớp trước để "Lâm Hiên Nhi" thắng "Lâm Hiên". [maxMarks] chặn trần cho đoạn
/// dày đặc tên; [terms] nên đã lọc sẵn ở chỗ gọi.
List<(int, int)> glossaryRanges(
  String text,
  Iterable<String> terms, {
  int maxMarks = 60,
}) {
  if (text.isEmpty) return const [];
  final sorted = terms
      .map((t) => t.trim())
      .where((t) => t.length >= 2)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final out = <(int, int)>[];
  for (final term in sorted) {
    if (out.length >= maxMarks) break;
    var from = 0;
    while (true) {
      final i = text.indexOf(term, from);
      if (i < 0) break;
      final end = i + term.length;
      from = i + 1;
      // Ranh giới từ hai đầu: "Lâm" không được khớp bên trong "Lâmm"
      if (i > 0 && isWordChar(text, i - 1)) continue;
      if (end < text.length && isWordChar(text, end)) continue;
      // Đã nằm trong một vùng dài hơn đã nhận → bỏ
      if (out.any((r) => i < r.$2 && end > r.$1)) continue;
      out.add((i, end));
      if (out.length >= maxMarks) break;
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Gợi ý sửa TÊN theo bản gốc: term glossary có chữ Hán nằm trong [zh] (nguyên văn
/// chương) và giống [sel] theo âm tiết đã bỏ dấu. Tên dịch lệch thường chỉ khác dấu
/// hoặc cụt âm ("Ba La" ↔ "Ba Lạp Ba Lạp") nên so nguyên chuỗi có dấu không bao giờ
/// trúng — đây là lý do form sửa từng trơ đúng lúc cần gợi ý nhất.
/// Term mà bản đúng ĐÃ có trong [block] xếp sau: đoạn này đọc đúng tên đó rồi.
List<Map<String, dynamic>> termsFromSource(
  String sel,
  String block,
  String zh,
  List<Map<String, dynamic>> terms, {
  int max = 6,
}) {
  List<String> syl(String s) =>
      boDau(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  final want = syl(sel);
  if (want.isEmpty || zh.isEmpty) return [];
  // "la" ~ "lap": âm cụt/ thừa phụ âm cuối vẫn tính trúng, nhưng chữ 1 ký tự thì phải khớp đủ
  // lệch ĐÚNG một ký tự cuối ("la" ~ "lap"); lỏng hơn thì "thi" khớp cả "thien"
  bool same(String a, String b) =>
      a == b ||
      (a.length >= 2 && b.length >= 2 && (a.length - b.length).abs() == 1 &&
          (a.startsWith(b) || b.startsWith(a)));
  final scored = <(Map<String, dynamic>, int, bool)>[];
  final seen = <String>{};
  for (final t in terms) {
    final tz = (t['term_zh'] ?? '').toString();
    final vi = (t['correct_vi'] ?? '').toString().trim();
    if (tz.length < 2 || vi.isEmpty || !zh.contains(tz) || !seen.add(vi)) continue;
    final have = syl('$vi ${t['wrong_vi'] ?? ''}');
    final score = want.where((w) => have.any((h) => same(w, h))).length;
    // phải phủ ≥ nửa tên dài hơn: chung một âm "Thiên" không đủ gợi "Thương Thiên Tử"
    final len = [want.length, syl(vi).length].reduce((x, y) => x > y ? x : y);
    if (score * 2 < len) continue;
    scored.add((t, score, block.contains(vi)));
  }
  scored.sort((a, b) => a.$3 != b.$3 ? (a.$3 ? 1 : -1) : b.$2.compareTo(a.$2));
  return [for (final e in scored.take(max)) e.$1];
}

/// Dòng NGUỒN chữ Trung của khối đang chạm: bản dịch giữ dòng 1-1 với nguồn (đo trên
/// truyện 34700: 237/244 chương), nên tìm dòng vi chứa khối rồi lấy dòng zh cùng chỉ số.
/// Khối hiển thị là câu đã tách/gộp (splitBySentence) nên dò theo đầu khối. Lệch số dòng
/// → null: thà không hiện còn hơn hiện nhầm câu.
String? sourceLineFor(String block, String vi, String zh) {
  List<String> lines(String s) =>
      s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final vl = lines(vi);
  var zl = lines(zh);
  if (zl.length == vl.length + 1) zl = zl.sublist(1); // nguồn còn dòng tiêu đề
  final key = block.trim();
  if (zl.length != vl.length || key.isEmpty) return null;
  final probe = key.length > 40 ? key.substring(0, 40) : key;
  final i = vl.indexWhere((l) => l.contains(probe));
  return i < 0 ? null : zl[i];
}
