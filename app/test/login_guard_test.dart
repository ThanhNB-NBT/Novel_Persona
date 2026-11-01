// Khoá đăng nhập tạm theo máy: ngưỡng, nhân đôi, trần, chống đồng hồ lệch, lưu qua prefs.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/login_guard.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() => prefs.clear());

  test('lockMs: 0 dưới ngưỡng, 30s từ lần 5, nhân đôi, trần 15 phút', () {
    expect(LoginGuard.lockMs(4), 0);
    expect(LoginGuard.lockMs(5), 30000);
    expect(LoginGuard.lockMs(6), 60000);
    expect(LoginGuard.lockMs(50), 900000);
  });

  test('sai 5 lần liên tiếp thì khoá 30s rồi mở', () {
    var g = LoginGuard.empty;
    for (var i = 0; i < 4; i++) {
      g = g.failed(1000);
    }
    expect(g.wait(1000), Duration.zero);
    g = g.failed(1000);
    expect(g.wait(1000), const Duration(seconds: 30));
    expect(g.wait(31000), Duration.zero);
  });

  test('until bị chỉnh xa vẫn tối đa 15 phút; lưu rồi đọc lại đúng; rác thì về rỗng', () async {
    expect(const LoginGuard(5, 1 << 50).wait(0), const Duration(minutes: 15));
    await const LoginGuard(7, 12345).save();
    final g = LoginGuard.read();
    expect([g.fails, g.untilMs], [7, 12345]);
    await prefs.setString('login_guard', 'abc');
    expect(LoginGuard.read().fails, 0);
  });
}
