import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';

void main() {
  test('giftAt khớp SQL cult_gift_at (ngưỡng 50% từ migration 049)', () {
    // Công thức: int(md5('uid:7:i')[0..6], 16) % 100 < 50 — giống hệt SQL 049.
    // Kỳ vọng suy ra trực tiếp từ công thức đó (test cũ là dữ liệu thời ngưỡng 30%).
    const uid = '11111111-2222-3333-4444-555555555555';
    const expected = [true, false, true, true, true, false, false, true, false, true];
    for (var i = 1; i <= 10; i++) {
      expect(giftAt(uid, 7, i), expected[i - 1], reason: 'chương $i');
    }
  });
}
