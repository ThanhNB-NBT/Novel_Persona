import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/reader/reader_settings.dart';
import 'package:novel_reader/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('notTranslated: bộ đếm 0 mới gắn nhãn, thiếu cột thì không', () {
    expect(notTranslated({'chapter_count_translated': 0}), isTrue);
    expect(notTranslated({'chapter_count_translated': 3}), isFalse);
    expect(notTranslated({'id': 1}), isFalse);
  });

  test('Cài đặt đọc 2.1: phím âm lượng + tốc độ tự cuộn lưu qua lần mở sau', () {
    final a = ProviderContainer();
    expect(a.read(readerSettingsProvider).volumeKeys, isFalse);
    expect(a.read(readerSettingsProvider).autoScrollSpeed, 40);
    a
        .read(readerSettingsProvider.notifier)
        .update(a.read(readerSettingsProvider).copyWith(volumeKeys: true, autoScrollSpeed: 75));
    a.dispose();

    final b = ProviderContainer();
    expect(b.read(readerSettingsProvider).volumeKeys, isTrue);
    expect(b.read(readerSettingsProvider).autoScrollSpeed, 75);
    // copyWith không đụng 2 trường mới thì giữ nguyên
    expect(b.read(readerSettingsProvider).copyWith(fontSize: 20).volumeKeys, isTrue);
    b.dispose();
  });
}
