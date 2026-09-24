// Soi token GĐ7 (triện, thẻ lụa Tu Tiên, thẻ Đọc tiếp) ở cả sáng/tối:
//   flutter test test/gd7_render_test.dart
// → build/gd7_preview.png — MỞ RA NHÌN trước khi commit.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/silk.dart';
import 'package:novel_reader/screens/library/library.dart';
import 'package:novel_reader/widgets.dart';

Future<void> _font() async {
  final l = FontLoader('Jak');
  for (final w in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    final b = File('assets/google_fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    l.addFont(Future.value(ByteData.sublistView(b)));
  }
  await l.load();
}

Widget _panel(Brightness b) => Theme(
      data: ThemeData(
          fontFamily: 'Jak',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF296EF4), brightness: b)),
      child: Builder(
        builder: (context) => Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(children: [
            const PageHeader('THEO DÕI · ĐANG ĐỌC', 'Tủ truyện', seal: '藏'),
            const SectionHeader('Mới cập nhật'),
            const ContinueCard({
              'id': 1, 'title_vi': 'Già Thiên', 'cur_chapter': 312,
              'chapter_count_source': 1822, 'cover_url': null,
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final (i, t, s) in [
                  (Icons.temple_buddhist_rounded, 'Động Phủ', 'Tụ linh khí'),
                  (Icons.explore_rounded, 'Bí Cảnh', 'Thám hiểm'),
                  (Icons.military_tech_rounded, 'Thành Tựu', 'Thiên đạo'),
                ]) ...[
                  Expanded(
                    child: SilkCard(
                      child: Column(children: [
                        SealIcon(i),
                        const SizedBox(height: 8),
                        Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: Silk.of(context).ink)),
                        Text(s, style: TextStyle(fontSize: 10, color: Silk.of(context).inkSoft)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );

void main() {
  testWidgets('render token GĐ7 ra PNG', (tester) async {
    await tester.runAsync(_font);
    await tester.binding.setSurfaceSize(const Size(820, 520));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Row(children: [
          Expanded(child: _panel(Brightness.light)),
          Expanded(child: _panel(Brightness.dark)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    Directory('build').createSync(recursive: true);
    File('build/gd7_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
