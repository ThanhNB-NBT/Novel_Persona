// Chrome dùng chung phải sống được ở cỡ chữ hệ thống 150-200% (Android cho chỉnh
// tới 200%, nhóm đọc truyện lớn tuổi hay bật). Đo được: NovelListRow ghim chiều cao
// theo bìa nên tràn đáy 24px ở 1.5x — sửa ở lib/widgets/novel.dart (textH).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/theme.dart';
import 'package:novel_reader/widgets.dart';

Widget at(double scale, Widget child) => MaterialApp(
      theme: lightTheme,
      builder: (ctx, c) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!),
      home: Scaffold(body: child),
    );

void main() {
  final cases = <String, Widget>{
    'NovelListRow': NovelListRow(n: const {
      'title_vi': 'Đấu Phá Thương Khung Chi Dược Lão Truyền Kỳ Ngoại Truyện',
      'title_zh': '斗破苍穹',
      'genres': ['Huyền Huyễn', 'Tiên Hiệp', 'Đô Thị'],
    }, onTap: () {}),
    'SectionHeader': SectionHeader('Truyện đang đọc dở dang', onMore: () {}),
    'TagChip': const TagChip('Đang ra'),
    'ProgressRibbon': const ProgressRibbon(0.42),
    'AppError': AppError('Mất kết nối tới máy chủ', onRetry: () {}),
    'AppLoading': const AppLoading(),
  };

  for (final scale in [1.0, 1.5, 2.0]) {
    for (final e in cases.entries) {
      testWidgets('${e.key} @${scale}x', (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(at(scale, e.value));
        final ex = tester.takeException();
        expect(ex, isNull, reason: '${e.key} vỡ ở ${scale}x: $ex');
      });
    }
  }
}
