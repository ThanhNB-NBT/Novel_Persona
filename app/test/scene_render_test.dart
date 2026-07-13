// Soi hình cảnh Tu Tiên khi sửa painter (docs/tu-tien.md §3):
//   flutter test test/scene_render_test.dart
// → build/scene_preview.png — MỞ RA NHÌN trước khi commit.
// Lưới 2×2 phủ: 4 tộc × 2 giới, 4 kiểu halo, vũ khí bay quanh, aura fire/leaf.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';
import 'package:novel_reader/screens/cultivation/cultivation.dart';

void main() {
  test('nền Tu Tiên đổi đúng theo sáng/tối', () {
    expect(cultivationBackgroundAsset(Brightness.light),
        'assets/bg/cultivation_bg.webp');
    expect(cultivationBackgroundAsset(Brightness.dark),
        'assets/bg/cultivation_bg_night.webp');
  });

  // Mirror SQL↔Dart: cult_tien_max()=6 → 7 tên bậc + 7 đạo hiệu, tránh index-out-of-range.
  test('bảng bậc tiên khớp cult_tien_max (064)', () {
    expect(tienTierNames.length, 7);
    expect(tienDaoTitles.length, 7);
    expect(tienTierMax, 6);
  });

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
              // Ngũ Hành Tạp Căn: 5 hệ → 5 dải sương ngũ sắc quấn quýt
              CultivatorPreview(
                  realm: 2, race: 'nhan', gender: 'nam',
                  elements: ['kim', 'moc', 'thuy', 'hoa', 'tho']),
              // yêu nữ Song Linh Căn (thủy·hỏa) + halo tinh + kiếm bay + gương + hỏa hợp hệ
              CultivatorPreview(
                  realm: 5, race: 'yeu', gender: 'nu', cpCode: 'cp_liet_hoa',
                  elements: ['thuy', 'hoa'],
                  halo: 'tinh', weaponSprite: 'sword', phapbaoSprite: 'mirror'),
              // ma nam Đơn Linh Căn (mộc) + halo kim + đao bay + công pháp mộc
              CultivatorPreview(
                  realm: 8, race: 'ma', gender: 'nam', cpCode: 'cp_thanh_moc',
                  elements: ['moc'], halo: 'kim', weaponSprite: 'saber'),
              // hậu Phi Thăng: Đại La Kim Tiên (tier 5) đội Hoàng Kim Vương Miện, đơn hệ kim
              CultivatorPreview(
                  realm: 9, race: 'nhan', gender: 'nam', tienTier: 5,
                  elements: ['kim'], haloWorn: 'hoang_kim'),
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
