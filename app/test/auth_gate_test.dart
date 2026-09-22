// Hàng rào đăng nhập ở router (main.dart). Chỉ test phần thuần logic — dựng
// phiên Supabase giả để test cả GoRouter thì tốn hơn thứ nó bảo vệ.
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/main.dart';

void main() {
  group('chưa đăng nhập', () {
    test('Khám phá và màn đăng nhập thì cho qua', () {
      expect(authGateFor('/', signedIn: false), isNull);
      // /login KHÔNG được tự đẩy về /login, nếu không router lặp vô hạn.
      expect(authGateFor('/login', signedIn: false), isNull);
    });

    test('mọi màn còn lại đẩy về đăng nhập', () {
      for (final p in [
        '/novel/5',
        '/novel/5/read/2', // deep link từ thông báo
        '/novel/5/glossary',
        '/search',
        '/cultivation',
        '/offline',
        '/notifications',
        '/profile/edit',
        '/admin',
        '/admin/novel/5',
      ]) {
        expect(authGateFor(p, signedIn: false), '/login', reason: p);
      }
    });
  });

  test('đã đăng nhập thì không chặn gì', () {
    for (final p in ['/', '/login', '/novel/5/read/2', '/admin']) {
      expect(authGateFor(p, signedIn: true), isNull, reason: p);
    }
  });
}
