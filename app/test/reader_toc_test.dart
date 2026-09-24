// Mục lục trong màn đọc (GĐ1 kế hoạch 2.0): mở ra là thấy chương đang đọc,
// chạm chương khác thì gọi onPick đúng số chương.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/reader/reader_dialogs.dart';

void main() {
  testWidgets('mục lục cuộn sẵn tới chương đang đọc và chọn được chương', (tester) async {
    final list = [
      for (var i = 1; i <= 300; i++)
        <String, dynamic>{'chapter_index': i, 'title_vi': 'Chương $i thử', 'translation_status': 'done'},
    ];
    int? picked;
    await tester.pumpWidget(ProviderScope(
      overrides: [chapterListProvider(7).overrideWith((ref) async => list)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showChapterTocSheet(context,
                  novelId: 7, current: 200, onPick: (i) => picked = i),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Chương 200 thử'), findsOneWidget);
    expect(find.text('Chương 1 thử'), findsNothing);
    await tester.tap(find.text('Chương 201 thử'));
    await tester.pumpAndSettle();
    expect(picked, 201);
  });
}
