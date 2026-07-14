// Phân đoạn chương dùng CHUNG cho màn đọc và máy đọc TTS — phải giống hệt nhau thì
// highlight "đoạn đang đọc" mới khớp đúng đoạn trên màn hình.

// Ngắt sau dấu kết câu (. ! ? … và bản full-width) khi theo sau là khoảng trắng —
// không ngắt giữa "?"/"!" trong ngoặc kép (sau đó là " chứ không phải trắng).
final _sentenceEnd = RegExp(r'(?<=[.!?…。！？])\s+');

/// Tách mỗi đoạn dài thành từng câu (1 câu/đoạn) cho dễ đọc; câu quá ngắn (<40 ký tự)
/// gộp với câu sau tới khi đủ dài hoặc gom 3 câu — tránh đoạn quá dài lẫn vụn vặt.
List<String> splitBySentence(List<String> paras) {
  const minLen = 40;
  final out = <String>[];
  for (final p in paras) {
    final sentences =
        p.split(_sentenceEnd).where((s) => s.trim().isNotEmpty).toList();
    if (sentences.length <= 1) {
      out.add(p.trim());
      continue;
    }
    var buf = '';
    var count = 0;
    for (final s in sentences) {
      buf = buf.isEmpty ? s.trim() : '$buf ${s.trim()}';
      count++;
      if (buf.length >= minLen || count >= 3) {
        out.add(buf);
        buf = '';
        count = 0;
      }
    }
    if (buf.isNotEmpty) {
      // câu lẻ cuối quá ngắn → nối vào đoạn trước cho gọn, không để mẩu cụt
      if (buf.length < minLen && out.isNotEmpty) {
        out[out.length - 1] = '${out.last} $buf';
      } else {
        out.add(buf);
      }
    }
  }
  return out;
}

/// Danh sách đoạn NỘI DUNG như màn đọc hiển thị (KHÔNG gồm tiêu đề).
List<String> contentParagraphs(String content) => splitBySentence(
    content.split('\n').where((p) => p.trim().isNotEmpty).toList());
