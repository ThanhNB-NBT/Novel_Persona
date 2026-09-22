// loiDeHieu(): đổi ngoại lệ thành câu người đọc hiểu (widgets/common.dart).
// Ca quan trọng nhất là ca CUỐI nhóm Postgrest: lỗi lạ vẫn phải giữ được
// message để còn tra, chỉ bỏ phần code/details/hint.
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Postgrest', () {
    test('trùng job metadata → nói rõ phải làm gì', () {
      // Nguyên văn lỗi hiện trên máy người dùng 22/09/2026.
      final e = PostgrestException(
        message: 'duplicate key value violates unique constraint "uq_job_meta_active"',
        code: '23505',
        details: 'Key (novel_id, type)=(35833, metadata) already exists.',
      );
      final s = loiDeHieu(e);
      expect(s, contains('đang chờ trong hàng đợi'));
      // Không được lộ lại mấy thứ người dùng không hiểu.
      expect(s, isNot(contains('23505')));
      expect(s, isNot(contains('uq_job_meta_active')));
      expect(s, isNot(contains('PostgrestException')));
    });

    test('trùng khoá khác → câu chung', () {
      expect(
        loiDeHieu(PostgrestException(
            message: 'duplicate key value violates unique constraint "uq_abc"',
            code: '23505')),
        'Dữ liệu này đã có rồi.',
      );
    });

    test('RLS chặn → nói thiếu quyền', () {
      expect(loiDeHieu(PostgrestException(message: 'new row violates row-level security policy', code: '42501')),
          contains('Không có quyền'));
    });

    test('admin only → nói cần quyền quản trị', () {
      expect(loiDeHieu(PostgrestException(message: 'admin only', code: 'P0001')),
          contains('quyền quản trị'));
    });

    test('mã lạ → giữ message, bỏ code/details/hint', () {
      final e = PostgrestException(
          message: 'function xyz does not exist', code: '42883', details: 'chi tiet dai');
      expect(loiDeHieu(e), 'function xyz does not exist');
    });
  });

  test('mất mạng xét trước mọi thứ', () {
    expect(loiDeHieu(Exception('SocketException: Failed host lookup')),
        contains('Mất kết nối'));
  });

  group('đăng nhập', () {
    test('sai mật khẩu', () {
      expect(loiDeHieu(const AuthException('Invalid login credentials')),
          'Sai email hoặc mật khẩu.');
    });
    test('đăng ký đã khoá → chỉ đường nhờ quản trị', () {
      expect(loiDeHieu(const AuthException('Signups not allowed, signup is disabled')),
          contains('nhờ quản trị'));
    });
  });

  test('lỗi lạ: cắt ngắn, không phủ kín màn hình', () {
    final s = loiDeHieu(Exception('X' * 400));
    expect(s.length, lessThanOrEqualTo(120));
    expect(s, endsWith('…'));
  });
}
