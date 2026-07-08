// Render thử _HumanPainter + _AuraPainter ra PNG để soi bằng mắt (không assert gì
// ngoài "vẽ không nổ"). Chạy: flutter test test/human_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/cultivation.dart';

void main() {
  testWidgets('render nhân vật vector ra PNG', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF101826),
        body: Center(
          child: RepaintBoundary(
            key: const Key('shot'),
            child: Container(
              color: const Color(0xFF101826),
              padding: const EdgeInsets.all(12),
              // 3 mốc cảnh giới = 3 kiểu chỗ ngồi: đá / đài sen / kiếm bay
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                CultivatorPreview(realm: 2, cpCode: null),
                CultivatorPreview(realm: 5, cpCode: 'cp_huyen_bang'),
                CultivatorPreview(realm: 9, cpCode: 'cp_thien_cang'),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700)); // giữa vòng animation
    final el = find.byKey(const Key('shot'));
    final ro = tester.renderObject<RenderRepaintBoundary>(el);
    // toImage cần event loop THẬT — await trong fake-async zone là treo tới timeout
    final bytes = await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 2);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    File('build/human_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    // gỡ widget để dispose AnimationController lặp vô hạn — không thì test kẹt/đỏ
    await tester.pumpWidget(const SizedBox());
  });
}
