// Test các hàm tiện ích thuần (không cần Supabase/network).
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/widgets.dart';

void main() {
  group('statusLabel — nhãn trạng thái truyện', () {
    test('trạng thái quen → tiếng Việt', () {
      expect(statusLabel('ongoing'), 'Đang ra');
      expect(statusLabel('completed'), 'Hoàn thành');
      expect(statusLabel('hiatus'), 'Tạm ngưng');
    });

    test('trạng thái lạ → giữ nguyên văn', () {
      expect(statusLabel('serializing'), 'serializing');
      expect(statusLabel(''), '');
    });
  });

  group('minChapterThresholds — mốc lọc số chương', () {
    test('kho nhỏ (max=300) → chỉ mốc 0, 100', () {
      expect(minChapterThresholds(300), [0, 100]);
    });

    test('kho lớn (max=12000) → đủ mốc tới 10000', () {
      final t = minChapterThresholds(12000);
      expect(t, [0, 100, 500, 1000, 2000, 3000, 5000, 10000]);
    });

    test('max=0 → chỉ [0]', () {
      expect(minChapterThresholds(0), [0]);
    });
  });

  group('liveStreak — chuỗi ngày đọc liên tiếp', () {
    test('profile null → 0', () {
      expect(liveStreak(null), 0);
    });

    test('streak=0 → 0', () {
      expect(liveStreak({'streak': 0, 'last_read_date': '2026-07-20'}), 0);
    });

    test('đọc hôm nay → còn chuỗi', () {
      final today = DateTime.now().toIso8601String();
      expect(liveStreak({'streak': 5, 'last_read_date': today}), 5);
    });

    test('đọc hôm qua → còn chuỗi', () {
      final yesterday =
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      expect(liveStreak({'streak': 3, 'last_read_date': yesterday}), 3);
    });

    test('đọc 2 ngày trước → đứt chuỗi', () {
      final old =
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      expect(liveStreak({'streak': 10, 'last_read_date': old}), 0);
    });

    test('last_read_date null → 0', () {
      expect(liveStreak({'streak': 7, 'last_read_date': null}), 0);
    });
  });

  group('timeAgo — thời gian tương đối', () {
    test('null → rỗng', () {
      expect(timeAgo(null), '');
    });

    test('vừa xong (< 1 phút)', () {
      expect(timeAgo(DateTime.now().toUtc().toIso8601String()), 'vừa xong');
    });

    test('phút trước', () {
      final t = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      expect(timeAgo(t), '5 phút trước');
    });

    test('giờ trước', () {
      final t = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 3))
          .toIso8601String();
      expect(timeAgo(t), '3 giờ trước');
    });

    test('ngày trước', () {
      final t = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 2))
          .toIso8601String();
      expect(timeAgo(t), '2 ngày trước');
    });
  });

  group('SearchFilter — equality + hashCode', () {
    test('cùng giá trị → bằng nhau', () {
      const a = SearchFilter(query: 'phàm nhân', minChapters: 100);
      const b = SearchFilter(query: 'phàm nhân', minChapters: 100);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('khác query → khác nhau', () {
      const a = SearchFilter(query: 'a');
      const b = SearchFilter(query: 'b');
      expect(a, isNot(b));
    });

    test('isEmpty đúng khi mọi field mặc định', () {
      expect(const SearchFilter().isEmpty, isTrue);
      expect(const SearchFilter(query: 'x').isEmpty, isFalse);
      expect(const SearchFilter(minChapters: 1).isEmpty, isFalse);
      expect(const SearchFilter(genre: 'Huyền Huyễn').isEmpty, isFalse);
      expect(const SearchFilter(status: 'ongoing').isEmpty, isFalse);
    });
  });
}
