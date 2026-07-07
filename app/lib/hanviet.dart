import 'package:flutter/services.dart' show rootBundle;

/// Tra âm Hán-Việt bằng bảng (assets/hanviet.tsv — cùng bản với worker,
/// worker/novelworker/data/hanviet.tsv; sửa bảng thì chép lại sang đây).
/// Dùng trong form sửa bản dịch: cho người không biết tiếng Trung đối chiếu
/// phiên âm chuẩn thay vì tin gợi ý của LLM.
Map<String, String>? _hv; // chữ Hán → âm mặc định (âm đầu trong bảng)

/// Gọi 1 lần lúc khởi động (fire-and-forget). Chưa nạp xong thì hanVietOf trả null.
Future<void> loadHanViet() async {
  final raw = await rootBundle.loadString('assets/hanviet.tsv');
  final m = <String, String>{};
  for (final line in raw.split('\n')) {
    if (line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    if (tab <= 0) continue;
    final readings = line.substring(tab + 1).trim();
    final first = readings.split('|').first;
    if (first.isNotEmpty) m[line.substring(0, tab)] = first;
  }
  _hv = m;
}

/// Phiên âm Hán-Việt Title Case của [zh] ("罗森" → "La Sâm").
/// null nếu bảng chưa nạp / có chữ ngoài bảng — không đoán bừa.
String? hanVietOf(String zh) {
  final t = _hv;
  if (t == null || zh.isEmpty) return null;
  final parts = <String>[];
  for (final ch in zh.runes) {
    final r = t[String.fromCharCode(ch)];
    if (r == null) return null;
    parts.add('${r[0].toUpperCase()}${r.substring(1)}');
  }
  return parts.join(' ');
}
