// Soi hình cảnh Tu Tiên khi sửa painter (docs/tu-tien.md §3):
//   flutter test test/scene_render_test.dart
// → build/scene_preview.png — MỞ RA NHÌN trước khi commit.
// Lưới 2×2 phủ: 4 tộc × 2 giới, 4 kiểu halo, vũ khí bay quanh, aura fire/leaf.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/cultivation/cultivation.dart';

void main() {
  testWidgets('render cảnh tu luyện ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 700));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFF10141F), // nền tối "Dạ Lam" ước lệ
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 320 / 170,
            children: const [
              // realm thấp, chưa đeo gì — vòng trơn
              CultivatorPreview(realm: 2, race: 'nhan', gender: 'nam'),
              // yêu nữ + halo tinh + kiếm bay + gương pháp bảo bay + hỏa
              CultivatorPreview(
                  realm: 5, race: 'yeu', gender: 'nu', cpCode: 'cp_liet_hoa',
                  halo: 'tinh', weaponSprite: 'sword', phapbaoSprite: 'mirror'),
              // ma nam + halo kim + đao bay + công pháp mộc (lá cuốn)
              CultivatorPreview(
                  realm: 8, race: 'ma', gender: 'nam', cpCode: 'cp_thanh_moc',
                  halo: 'kim', weaponSprite: 'saber'),
              // linh nữ + halo nguyệt + thương bay
              CultivatorPreview(
                  realm: 4, race: 'linh', gender: 'nu', cpCode: 'cp_huyen_bang',
                  halo: 'nguyet', weaponSprite: 'spear'),
            ],
          ),
        ),
      ),
    ));
    // đợi ảnh nhân vật decode thật (I/O nằm ngoài fake async của tester)
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 1400)); // giữa vòng loop 4s

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/scene_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File('build/scene_preview.png').lengthSync(), greaterThan(10000));
  });
}
