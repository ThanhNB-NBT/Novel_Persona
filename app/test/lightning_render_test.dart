// Soi lôi kiếp thủ tục (painters_lightning.dart):
//   flutter test test/lightning_render_test.dart → build/lightning_preview.png
// Mỗi ô một mốc quanh đạo lôi thứ 3: tia dẫn → cú đánh → chớp lại → tàn sáng.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/painters_lightning.dart';

void main() {
  testWidgets('render lôi kiếp ra PNG', (tester) async {
    const hit = 0.74;
    const frames = [-0.016, -0.006, 0.0, 0.004, 0.009, 0.02, 0.045, 0.49];
    await tester.binding.setSurfaceSize(const Size(4 * 200, 2 * 360));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: GridView.count(
          crossAxisCount: 4,
          childAspectRatio: 200 / 360,
          children: [
            for (final d in frames)
              Container(
                color: const Color(0xFF060911),
                child: CustomPaint(
                  painter: LightningStormPainter(
                    d == 0.49 ? d : hit + d, // ô cuối: chớp ẩn trong mây
                    from: 0.18,
                    to: 0.86,
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/lightning_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File('build/lightning_preview.png').lengthSync(), greaterThan(10000));
  });
}
