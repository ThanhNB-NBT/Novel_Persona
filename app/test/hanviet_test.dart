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
}
