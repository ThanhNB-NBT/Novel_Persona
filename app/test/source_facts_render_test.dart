// Soi hàng số liệu nguồn ở màn chi tiết truyện (chips số chữ / lượt đọc / cập nhật):
//   flutter test test/source_facts_render_test.dart
// → build/source_facts_preview.png — MỞ RA NHÌN trước khi commit.
// Không dùng theme app ở đây: theme dựng chữ qua google_fonts, mà test không có font trong
// assets nên mỗi lần dựng style là một exception. Chỉ cần soi BỐ CỤC nên ColorScheme là đủ.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/novel/novel_detail.dart';

void main() {
  testWidgets('render chips số liệu nguồn ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 320));
    final key = GlobalKey();
    final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF3576F5));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: cs, useMaterial3: true),
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              // faloo: số chữ + lượt đọc + hoa
              SourceFacts({
                'word_count': 4170000,
                'source_stats': {'reads': 25930710, 'flowers': 32685},
              }),
              // ptwxz: số chữ chính xác + lưu + đề cử + ngày cập nhật
              SourceFacts({
                'word_count': 1741012,
                'source_stats': {
                  'favorites': 215, 'recommends': 534, 'updated_at': '2023-09-02',
                },
              }),
              // ddxs/quanben5: nguồn không khai gì → KHÔNG được chừa chỗ trống
              SourceFacts({'word_count': null, 'source_stats': null}),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // toImage cần event loop THẬT — await thẳng trong fake-async zone là treo tới timeout
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    Directory('build').createSync(recursive: true);
    File('build/source_facts_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  test('rút gọn số theo cách người Việt đọc', () {
    expect(SourceFacts.short(25930710), '25,9 triệu');
    expect(SourceFacts.short(4170000), '4,2 triệu');
    expect(SourceFacts.short(215), '215');
    expect(SourceFacts.short(32685), '33 nghìn');
  });
}
