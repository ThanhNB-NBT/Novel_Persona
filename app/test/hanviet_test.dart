import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/hanviet.dart';

void main() {
  testWidgets('nhận chữ CJK mở rộng có trong bảng tra', (_) async {
    await loadHanViet();
    expect(hanVietOnly.hasMatch('𱌮'), isTrue);
    expect(hanVietOf('𱌮'), 'Xuất');
  });
}
