import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';

void main() {
  test('giftAt khớp SQL cult_gift_at (10 mẫu đối chiếu từ DB thật)', () {
    // psql: select i, cult_gift_at('11111111-...-555555555555', 7, i)
    //       from generate_series(1,10) i;  → t,f,f,f,t,f,f,t,f,f
    const uid = '11111111-2222-3333-4444-555555555555';
    const expected = [true, false, false, false, true, false, false, true, false, false];
    for (var i = 1; i <= 10; i++) {
      expect(giftAt(uid, 7, i), expected[i - 1], reason: 'chương $i');
    }
  });
}
