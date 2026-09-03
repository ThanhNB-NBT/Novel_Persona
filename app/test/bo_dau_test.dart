import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data/core.dart';

void main() {
  test('bỏ dấu tiếng Việt khớp với vn_norm() của DB (migration 111)', () {
    // Ca thật đã vấp: gõ không dấu ra 0 kết quả dù truyện có trong kho.
    expect(boDau('Toàn Dân Chuyển Dịch'), 'toan dan chuyen dich');
    // đ/Đ là chỗ dễ sót nhất — unaccent của Postgres đưa về 'd'
    expect(boDau('Đẩu Phá Thương Khung'), 'dau pha thuong khung');
    expect(boDau('ĐỖ ĐỨC'), 'do duc');
    // đủ 6 nguyên âm có dấu
    expect(boDau('ăâêôơư ằầềồờừ ạậệộợự'), 'aaeoou aaeoou aaeoou');
    expect(boDau('ỳýỷỹỵ'), 'yyyyy');
    // chữ Trung không có dấu → giữ nguyên, tìm tên gốc vẫn chạy
    expect(boDau('十日终焉'), '十日终焉');
    expect(boDau(''), '');
  });
}
