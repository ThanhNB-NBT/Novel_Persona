// Soi filmstrip hiệu ứng đột phá/lên tầng khi sửa _BurstPainter (docs/tu-tien.md §3):
//   flutter test test/burst_render_test.dart
// → build/burst_preview.png — MỞ RA NHÌN trước khi commit.
// 3 hàng: Độ Kiếp (major+lôi) · Đại cảnh giới thường (major) · Lên tầng (minor),
// mỗi hàng vài mốc t để thấy hội tụ → va chạm → trụ sáng/xung kích → tàn.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/cultivation.dart';

void main() {
  testWidgets('render filmstrip hiệu ứng đột phá ra PNG', (tester) async {
    const gold = Color(0xFFFFC53D); // phẩm Tiên ~ đại cảnh giới thành công
    const jade = Color(0xFF37B24D); // lên tầng thường
    const red = Color(0xFFE03131); // thất bại

    Widget cell(String label, Widget child) => Container(
          margin: const EdgeInsets.all(2),
          color: const Color(0xFF10141F),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Positioned(
                left: 4,
                top: 2,
                child: Text(label,
                    style: const TextStyle(color: Colors.white38, fontSize: 9)),
              ),
            ],
          ),
        );

    Widget row(String tag, List<double> ts,
            {required bool major, bool ok = true, bool loi = false, Color? color}) =>
        Expanded(
          child: Row(
            children: [
              for (final t in ts)
                Expanded(
                  child: cell(
                    '$tag ${t.toStringAsFixed(2)}',
                    BurstPreview(
                      t: t,
                      color: color ?? (ok ? gold : red),
                      ok: ok,
                      loi: loi,
                      major: major,
                    ),
                  ),
                ),
            ],
          ),
        );

    await tester.binding.setSurfaceSize(const Size(1000, 640));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Column(
          children: [
            row('Độ Kiếp', const [0.12, 0.30, 0.40, 0.55, 0.78],
                major: true, loi: true),
            row('Đại c.giới', const [0.12, 0.30, 0.42, 0.60, 0.85], major: true),
            row('Lên tầng', const [0.05, 0.18, 0.45, 0.80], major: false, color: jade),
            row('Thất bại', const [0.15, 0.45, 0.80],
                major: true, ok: false, color: red),
          ],
        ),
      ),
    ));
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/burst_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File('build/burst_preview.png').lengthSync(), greaterThan(10000));
  });
}
