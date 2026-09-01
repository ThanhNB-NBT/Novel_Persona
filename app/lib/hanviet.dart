import 'package:flutter/services.dart' show rootBundle;

/// Tra âm Hán-Việt bằng bảng (assets/hanviet.tsv — cùng bản với worker,
/// worker/novelworker/data/hanviet.tsv; sửa bảng thì chép lại sang đây).
/// Dùng trong form sửa bản dịch: cho người không biết tiếng Trung đối chiếu
/// phiên âm chuẩn thay vì tin gợi ý của LLM.
Map<String, List<String>>? _hv; // chữ Hán → các âm (âm đầu = mặc định)

// TSV có cả CJK Extension; form sửa phải nhận cùng dải ký tự với bảng tra.
// Trần U+323AF = hết Extension H — bảng đang dùng tới U+31339 (Extension G).
final hanVietRun = RegExp(
  r'[\u3400-\u4DBF\u4E00-\u9FFF\u{20000}-\u{323AF}]+',
  unicode: true,
);
final hanVietOnly = RegExp(
  r'^[\u3400-\u4DBF\u4E00-\u9FFF\u{20000}-\u{323AF}]+$',
  unicode: true,
);

// chữ đa âm mà âm ưu tiên trong TÊN RIÊNG khác âm đầu bảng — khớp worker
// hanviet._PREFERRED để mặc định app trùng mặc định worker auto-điền glossary.
const _preferred = {
  '宁': 'ninh',
  '曾': 'tăng',
  '任': 'nhâm', // bảng xếp mặc định theo văn xuôi (nhiệm); trong tên là họ Nhâm
  '燕': 'yên',  // 燕京 Yên Kinh; văn xuôi 燕子 = yến
  '仇': 'cừu',  // họ Cừu; văn xuôi 仇恨 = thù hận
  '区': 'âu',   // họ Âu; văn xuôi 地区 = địa khu
  // chữ phiên âm tên Tây — mặc định theo văn xuôi sẽ lệch khi ghép tên
  '菲': 'phi', // 菲尔德 Phi Nhĩ Đức; văn xuôi 芳菲 = phỉ
  '丽': 'ly',  // 玛丽 Mã Ly; văn xuôi 美丽 = mỹ lệ
};

/// Gọi 1 lần lúc khởi động (fire-and-forget). Chưa nạp xong thì hanVietOf trả null.
Future<void> loadHanViet() async {
  final raw = await rootBundle.loadString('assets/hanviet.tsv');
  final m = <String, List<String>>{};
  for (final line in raw.split('\n')) {
    if (line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    if (tab <= 0) continue;
    final ch = line.substring(0, tab);
    final rs = line
        .substring(tab + 1)
        .trim()
        .split('|')
        .where((s) => s.isNotEmpty)
        .toList();
    if (rs.isEmpty) continue;
    final pref = _preferred[ch];
    if (pref != null) {
      rs.remove(pref);
      rs.insert(0, pref); // âm ưu tiên cho tên lên đầu
    }
    m[ch] = rs;
  }
  _hv = m;
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Phiên âm Hán-Việt mặc định (âm đầu từng chữ) Title Case ("罗森" → "La Sâm").
/// null nếu bảng chưa nạp / có chữ ngoài bảng — không đoán bừa.
String? hanVietOf(String zh) {
  final t = _hv;
  if (t == null || zh.isEmpty) return null;
  final parts = <String>[];
  for (final ch in zh.runes) {
    final r = t[String.fromCharCode(ch)];
    if (r == null) return null;
    parts.add(_cap(r.first));
  }
  return parts.join(' ');
}

/// Các cách đọc Hán-Việt ỨNG VIÊN cho [zh] (tích Descartes các âm từng chữ, âm
/// mặc định trước), Title Case, tối đa [cap], khử trùng. Rỗng nếu có chữ ngoài bảng.
/// Dùng cho form sửa dịch: chữ đa âm (vd 曾 tằng/tăng) hiện nhiều cách đọc để người
/// đọc BẤM chọn thay vì gõ (không cần biết chữ Trung) — G7a.
List<String> hanVietCandidates(String zh, {int cap = 4}) {
  final t = _hv;
  if (t == null || zh.isEmpty) return const [];
  var combos = <List<String>>[<String>[]];
  for (final ch in zh.runes) {
    final rs = t[String.fromCharCode(ch)];
    if (rs == null) return const []; // chữ ngoài bảng → không đoán
    final next = <List<String>>[];
    for (final combo in combos) {
      for (final r in rs) {
        next.add([...combo, _cap(r)]);
        if (next.length >= cap * 6) break; // chặn bùng nổ tổ hợp chữ nhiều âm
      }
      if (next.length >= cap * 6) break;
    }
    combos = next;
  }
  final seen = <String>{};
  final out = <String>[];
  for (final c in combos) {
    final s = c.join(' ');
    if (seen.add(s)) out.add(s);
    if (out.length >= cap) break;
  }
  return out;
}
