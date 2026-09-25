// Âm lịch Việt Nam (múi giờ +7): đối chiếu các mốc đã biết.
//   flutter test test/lunar_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/lunar.dart';

void main() {
  (int, int, int, bool) l(int y, int m, int d) {
    final x = toLunar(DateTime(y, m, d));
    return (x.day, x.month, x.year, x.leap);
  }

  test('mùng 1 Tết các năm', () {
    expect(l(2023, 1, 22), (1, 1, 2023, false));
    expect(l(2024, 2, 10), (1, 1, 2024, false));
    expect(l(2025, 1, 29), (1, 1, 2025, false));
    expect(l(2026, 2, 17), (1, 1, 2026, false));
    // ngày trước Tết vẫn thuộc năm âm cũ, tháng Chạp
    expect(l(2026, 2, 16).$2, 12);
    expect(l(2026, 2, 16).$3, 2025);
  });

  test('Trung thu 2026 = rằm tháng Tám', () {
    expect(l(2026, 9, 25), (15, 8, 2026, false));
  });

  test('năm Ất Tỵ 2025 nhuận tháng Sáu', () {
    expect(l(2025, 6, 25), (1, 6, 2025, false));
    expect(l(2025, 7, 25), (1, 6, 2025, true));
    expect(toLunar(DateTime(2025, 7, 25)).monthName, 'Tháng Sáu nhuận');
  });

  test('can chi năm / ngày', () {
    expect(toLunar(DateTime(2026, 2, 17)).yearName, 'Bính Ngọ');
    expect(toLunar(DateTime(2025, 1, 29)).yearName, 'Ất Tỵ');
    expect(toLunar(DateTime(2000, 1, 1)).dayCanChi, 'Mậu Ngọ');
  });
}
