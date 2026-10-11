// Phân đoạn chương dùng CHUNG cho màn đọc và máy đọc TTS — phải giống hệt nhau thì
// highlight "đoạn đang đọc" mới khớp đúng đoạn trên màn hình.

// Ngắt sau dấu kết câu (. ! ? … và bản full-width) khi theo sau là khoảng trắng —
// không ngắt giữa "?"/"!" trong ngoặc kép (sau đó là " chứ không phải trắng).
final _sentenceEnd = RegExp(r'(?<=[.!?…。！？])\s+');

/// Tách mỗi đoạn dài thành từng câu (1 câu/đoạn) cho dễ đọc; câu quá ngắn (<40 ký tự)
/// gộp với câu sau tới khi đủ dài hoặc gom 3 câu — tránh đoạn quá dài lẫn vụn vặt.
/// Mỗi khối là LÁT CẮT NGUYÊN VĂN của một đoạn (không ghép lại bằng ' ', không vắt sang
/// đoạn khác) → luôn là chuỗi con của content_vi, gửi làm p_para/p_old cho RPC sửa chữ.
List<String> splitBySentence(List<String> paras) {
  const minLen = 40;
  final out = <String>[];
  for (final raw in paras) {
    final p = raw.trim();
    final cuts = _sentenceEnd.allMatches(p).toList();
    if (cuts.isEmpty) {
      out.add(p);
      continue;
    }
    // câu k = p[starts[k], ends[k])
    final starts = [0, for (final m in cuts) m.end];
    final ends = [for (final m in cuts) m.start, p.length];
    final first = out.length; // khối đầu tiên của CHÍNH đoạn này
    var lastFrom = 0, from = 0, count = 0;
    for (var k = 0; k < ends.length; k++) {
      count++;
      if (ends[k] - from >= minLen || count >= 3) {
        out.add(p.substring(from, ends[k]));
        lastFrom = from;
        from = k + 1 < starts.length ? starts[k + 1] : p.length;
        count = 0;
      }
    }
    if (count == 0) continue;
    // câu lẻ cuối quá ngắn → nối vào khối trước CỦA ĐOẠN NÀY, không để mẩu cụt
    if (p.length - from < minLen && out.length > first) {
      out[out.length - 1] = p.substring(lastFrom);
    } else {
      out.add(p.substring(from));
    }
  }
  return out;
}

/// Khối (phần tử của [paras]) chứa vị trí [at] của [shown]. [shown] là chính một khối
/// (chế độ cuộn) hoặc một trang lật — lát cắt đã trim của `paras.join('\n\n')`.
/// null = không định vị được (hoặc [at] rơi vào khoảng ngắt giữa hai khối).
String? blockAt(List<String> paras, String shown, int at) {
  if (paras.contains(shown)) return shown;
  final page = paras.join('\n\n').indexOf(shown);
  if (page < 0) return null;
  var pos = page + at;
  for (final p in paras) {
    if (pos < p.length) return p;
    pos -= p.length + 2;
    if (pos < 0) return null;
  }
  return null;
}

/// 【】 (lời hệ thống truyện game) → [ ]: ngoặc toàn khổ có sẵn khoảng trắng hai bên
/// glyph → đoạn mở bằng 【 bị thụt nửa ô, giữa câu thì hở. CHỈ áp lúc VẼ (và lúc máy đọc
/// phát) — khối giữ nguyên văn gốc. Đổi 1 ký tự lấy 1 ký tự nên offset gạch chân thuật
/// ngữ / vùng chọn tính trên khối gốc vẫn dùng thẳng cho chữ đã đổi ngoặc.
String halfWidthBrackets(String s) => s.replaceAll('【', '[').replaceAll('】', ']');

/// Danh sách khối NỘI DUNG như màn đọc chia (KHÔNG gồm tiêu đề), văn bản GỐC chưa đổi
/// ngoặc — vẽ thì bọc [halfWidthBrackets].
List<String> contentParagraphs(String content) => splitBySentence(
    content.split('\n').where((p) => p.trim().isNotEmpty).toList());
