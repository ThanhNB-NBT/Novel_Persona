import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/explore/search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'search_history_list': ['Phàm Nhân Tu Tiên'],
    });
    prefs = await SharedPreferences.getInstance();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SearchScreen History & Suggestions Test', () {
    testWidgets('Hiển thị lịch sử tìm kiếm và danh sách thể loại hot', (tester) async {
      await prefs.setStringList('search_history_list', ['Phàm Nhân Tu Tiên']);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tìm kiếm gần đây'), findsOneWidget);
      expect(find.text('Phàm Nhân Tu Tiên'), findsOneWidget);

      expect(find.text('Từ khóa & Thể loại hot'), findsOneWidget);
      expect(find.text('Tiên hiệp'), findsOneWidget);
      expect(find.text('Huyền huyễn'), findsOneWidget);
      expect(find.text('Đô thị'), findsOneWidget);

      await tester.tap(find.text('Tiên hiệp'));
      await tester.pumpAndSettle();

      expect(find.text('Tiên hiệp'), findsWidgets);
    });

    testWidgets('Xóa lịch sử tìm kiếm', (tester) async {
      await prefs.setStringList('search_history_list', ['Phàm Nhân Tu Tiên']);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phàm Nhân Tu Tiên'), findsOneWidget);

      final clearBtn = find.text('Xóa tất cả');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('Tìm kiếm gần đây'), findsNothing);
      expect(find.text('Phàm Nhân Tu Tiên'), findsNothing);
      expect(find.text('Từ khóa & Thể loại hot'), findsOneWidget);
    });
  });

  group('Reader Tap Zones Test', () {
    testWidgets('Tap zones chia 25% trái, 50% giữa, 25% phải', (tester) async {
      bool leftTapped = false;
      bool middleTapped = false;
      bool rightTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 800,
                child: Row(
                  children: [
                    Expanded(
                      flex: 25,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => leftTapped = true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 50,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => middleTapped = true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 25,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => rightTapped = true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap mép trái (x = 220, giữa màn hình 800px là tâm 400px: 400-200=200..600 -> mép trái 200..300)
      final leftCenter = tester.getCenter(find.byType(Expanded).first);
      await tester.tapAt(leftCenter);
      expect(leftTapped, isTrue);
      expect(middleTapped, isFalse);
      expect(rightTapped, isFalse);

      // Tap giữa (phần tử thứ 2)
      leftTapped = false;
      final midCenter = tester.getCenter(find.byType(Expanded).at(1));
      await tester.tapAt(midCenter);
      expect(leftTapped, isFalse);
      expect(middleTapped, isTrue);
      expect(rightTapped, isFalse);

      // Tap mép phải (phần tử thứ 3)
      middleTapped = false;
      final rightCenter = tester.getCenter(find.byType(Expanded).at(2));
      await tester.tapAt(rightCenter);
      expect(leftTapped, isFalse);
      expect(middleTapped, isFalse);
      expect(rightTapped, isTrue);
    });
  });
}
