import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';

// Giá trị chép từ SQL ở repo Novel_Backend (SQL là chuẩn). Test đỏ = một đầu đã đổi
// công thức mà đầu kia chưa theo → sửa CẢ HAI (xem docs/tu-tien.md §cặp MIRROR).
void main() {
  test('cultRecycleGain khớp SQL cult_recycle_gain (migration 103)', () {
    const sql = {1: 50, 2: 300, 3: 2000, 4: 12000, 5: 80000, 6: 500000};
    for (final e in sql.entries) {
      expect(cultRecycleGain(e.key), e.value, reason: 'phẩm ${e.key}');
    }
    // SQL kẹp greatest(least(p_grade, 6), 1)
    expect(cultRecycleGain(0), 50);
    expect(cultRecycleGain(9), 500000);
  });

  test('tienHalos khớp allowlist SQL cult_halo_codes() (migration 068) và có ảnh', () {
    const sql = ['thai_duong', 'luc_du', 'huyen_tuyet', 'bach_ngan', 'hoang_kim', 'huyet_long'];
    expect(tienHalos.keys.toList(), sql);
    for (final code in sql) {
      expect(File('assets/cult_halo/$code.webp').existsSync(), isTrue, reason: code);
    }
  });

  test('định dạng số tu vi dùng chung một kiểu dấu phẩy', () {
    expect(gonSo(431580831), '431,6M');
    expect(gonSo(25300), '25,3K');
    expect(gonSo(940.7), '940');
    expect(gonTocDo(3800.2), '3800,2');
    expect(gonTocDo(1.5), '1,5');
    expect(gonTocDo(25300), '25,3K');
  });
}
