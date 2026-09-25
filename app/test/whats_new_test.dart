// "Có gì mới ở 2.0": chỉ hiện cho máy từng chạy 1.x, đúng một lần.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/whats_new.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => maybeShowWhatsNew(context), child: const Text('mở')),
      ),
    ),
  ));
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
}

void main() {
  // prefs là late final → gán một lần, mỗi test tự dọn rồi đặt cờ riêng
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() => prefs.clear());

  testWidgets('người nâng cấp thấy 1 lần, lần sau không', (tester) async {
    await prefs.setBool('guide_offered', true);
    await _pump(tester);
    expect(find.text('Gác Truyện 2.0.2'), findsOneWidget);
    await tester.tap(find.text('Vào đọc thôi'));
    await tester.pumpAndSettle();
    await _pump(tester);
    expect(find.text('Gác Truyện 2.0.2'), findsNothing);
  });

  testWidgets('người cài mới không thấy', (tester) async {
    await _pump(tester);
    expect(find.text('Gác Truyện 2.0.2'), findsNothing);
  });

  testWidgets('đã xem 2.0 → chỉ thấy mục của bản sau, không lặp lại 2.0', (tester) async {
    await prefs.setString('whats_new_seen', '2.0');
    await _pump(tester);
    expect(find.text('Gác Truyện 2.0.2'), findsOneWidget);
    expect(find.text('Chọn nền cho cả app'), findsOneWidget);
    expect(find.text('Tu Tiên thật'), findsNothing);
  });

  test('unseenReleases: lên thẳng từ 1.x thấy tất cả, bản lạ cũng coi như chưa xem', () {
    expect(unseenReleases(null).length, releases.length);
    expect(unseenReleases('1.9').length, releases.length);
    expect(unseenReleases(releases.last.$1), isEmpty);
  });
}
