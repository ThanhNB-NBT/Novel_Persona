import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';

// Mirror toán bậc linh căn (migration 078) — đổi SQL phải đổi cả đây.
void main() {
  const nguHanh = ['kim', 'moc', 'thuy', 'hoa', 'tho'];

  test('bậc gốc theo số hệ, chưa có điểm', () {
    expect(rootName(5, null), 'Ngũ Hành Tạp Căn');
    expect(linhCanMult(nguHanh, null), 1.0);
    expect(rootName(1, null), 'Đơn Linh Căn');
    expect(linhCanMult(['hoa'], null), 16.0);
  });

  test('ví dụ của user: tạp +5 điểm → Tứ Linh Căn, hệ giữ nguyên 5', () {
    expect(rootName(5, null, 6), 'Tứ Linh Căn');
    expect(linhCanMult(nguHanh, null, 6), 2.0);
  });

  test('điểm lẻ nội suy trong bậc, càng cao càng tốn', () {
    expect(linhCanMult(nguHanh, null, 3), closeTo(1.4, 1e-9)); // 2/5 đường tới Tứ
    // Đơn (bậc 5) cần 80 điểm mới lên Dị: 5 điểm chỉ nhích 16×(1+5/80)
    expect(linhCanMult(['hoa'], null, 6), closeTo(17.0, 1e-9));
    expect(rootName(1, null, 81), 'Dị Linh Căn');
    expect(linhCanMult(['hoa'], null, 81), 32.0);
  });

  test('dị căn bẩm sinh vào thẳng Dị, thiên/hỗn độn vào Tiên', () {
    expect(rootName(1, 'loi'), 'Lôi Linh Căn');
    expect(linhCanMult(['hoa'], 'loi'), 32.0); // đơn ngoài ngũ hành > đơn trong (16)
    expect(rootName(1, 'loi', 161), 'Tiên Linh Căn'); // +160 điểm thăng vượt bậc bẩm sinh
    expect(linhCanMult(['hoa'], 'loi', 161), 64.0);
    expect(rootName(1, 'thien'), 'Thiên Linh Căn');
    expect(linhCanMult(['hoa'], 'thien'), 64.0);
    expect(rootName(5, 'hon'), 'Hỗn Độn Linh Căn');
    expect(linhCanMult(nguHanh, 'hon'), 64.0);
  });

  test('quá trần Tiên: +10%/điểm dư', () {
    expect(linhCanMult(['hoa'], 'thien', 11), closeTo(128.0, 1e-9));
  });
}
