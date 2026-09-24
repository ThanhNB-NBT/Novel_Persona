// Bìa bay (Hero) sang trang truyện: trang đích phải có Hero đúng tag NGAY khung
// đầu, khi dữ liệu truyện còn đang tải — không thì Hero không có chỗ đáp.
//   flutter test test/cover_hero_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/novel/novel_detail.dart';
import 'package:novel_reader/widgets.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('đang tải vẫn dựng Hero bìa theo tag danh sách', (tester) async {
    final pending = Completer<Rec>(); // không bao giờ xong → giữ trạng thái loading
    const n = {'id': 7, 'title_vi': 'Thử', 'cover_url': null};
    await tester.pumpWidget(ProviderScope(
      overrides: [novelProvider(7).overrideWith((ref) => pending.future)],
      child: const MaterialApp(
        home: NovelDetailScreen(novelId: 7, hero: ('cover-lib-7', n)),
      ),
    ));
    await tester.pump();
    expect(coverTag('lib', 7), 'cover-lib-7');
    expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'cover-lib-7'), findsOneWidget);
  });
}
