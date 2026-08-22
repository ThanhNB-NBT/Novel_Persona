import 'package:flutter/painting.dart';

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

/// Cắt văn bản thành các trang vừa 1 màn (tìm nhị phân số ký tự vừa chiều cao).
List<String> paginateText(
    String text, TextStyle style, double maxWidth, double pageH, double firstH) {
  final pages = <String>[];
  final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: null);
  final n = text.length;
  int start = 0;
  while (start < n) {
    final limit = pages.isEmpty ? firstH : pageH;
    int lo = start + 1, hi = n, best = start + 1;
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
