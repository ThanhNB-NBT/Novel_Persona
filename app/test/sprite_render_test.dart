// Render các sprite pixel ra PNG để soi bằng mắt khi thêm/sửa hình.
// Chạy: flutter test test/sprite_render_test.dart → build/sprite_preview.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/pixel.dart';

void main() {
  testWidgets('render sprite mới ra PNG', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF101826),
        body: Center(
          child: RepaintBoundary(
            key: const Key('shot'),
            child: Container(
              color: const Color(0xFF101826),
              padding: const EdgeInsets.all(12),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                PixelIcon('scroll', grade: 3, size: 56),
                PixelIcon('slip', grade: 2, size: 56),
                PixelIcon('seal', grade: 4, size: 56),
                PixelIcon('fan', grade: 2, size: 56),
                PixelIcon('gift', grade: 5, size: 56),
              ]),
            ),
          ),
        ),
      ),
    ));
    final ro = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('shot')));
    final bytes = await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 2);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    File('build/sprite_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
