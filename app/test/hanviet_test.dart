import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/hanviet.dart';

void main() {
  testWidgets('nhận chữ CJK mở rộng có trong bảng tra', (tester) async {
    // runAsync: loadHanViet đọc asset thật, future I/O không hoàn tất trong vùng
    // FakeAsync của testWidgets (test treo tới timeout 10 phút).
    await tester.runAsync(loadHanViet);
    expect(hanVietOnly.hasMatch('𱌮'), isTrue);
    expect(hanVietOf('𱌮'), 'Xuất');
  });

  testWidgets('zhSpanFor: tìm lại chữ Hán gốc từ phiên âm Hán-Việt', (tester) async {
    await tester.runAsync(loadHanViet);
    expect(zhSpanFor('Liệp Nhân', '一个猎人走了过来。'), '猎人');
    // bỏ dấu + chữ đa âm: 宁 có âm "ninh" ưu tiên, vẫn khớp
    expect(zhSpanFor('Ninh Thành', '他回到了宁城。'), '宁城');
    // từ thuần Việt không có trong câu theo âm Hán-Việt → null
    expect(zhSpanFor('thợ săn', '一个猎人走了过来。'), isNull);
  });
}
