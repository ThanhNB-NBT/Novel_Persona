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
import 'package:novel_reader/screens/cultivation/pixel.dart';

void main() {
  test('nền Tu Tiên đổi đúng theo sáng/tối', () {
    expect(cultivationBackgroundAsset(Brightness.light),
        'assets/bg/cultivation_bg.webp');
    expect(cultivationBackgroundAsset(Brightness.dark),
        'assets/bg/cultivation_bg_night.webp');
  });

  // Mirror SQL↔Dart: cult_tien_max()=14 → 15 tên bậc + 15 đạo hiệu, tránh index-out-of-range.
  test('bảng bậc tiên khớp cult_tien_max (124)', () {
    expect(tienTierNames.length, 15);
    expect(tienDaoTitles.length, 15);
    expect(tienTierMax, 14);
  });

  testWidgets('render cảnh tu luyện ra PNG', (tester) async {
    await _renderGrid(tester, 'build/scene_preview.png', const [
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
              // cung Siêu Thoát (124): bậc 10 hào quang bắt đầu ngả trắng tím, bậc 14 lạnh hẳn
              CultivatorPreview(
                  realm: 9, race: 'linh', gender: 'nu', tienTier: 10,
                  elements: ['thuy']),
              CultivatorPreview(
                  realm: 9, race: 'nhan', gender: 'nam', tienTier: 14,
                  elements: ['hoa'], haloWorn: 'bach_ngan'),
    ]);
  });

  // 9 kiểu hiệu ứng công pháp (AuraPainter) — mỗi ô một code công pháp có kiểu riêng.
  // → build/aura_preview.png
  testWidgets('render 9 hiệu ứng công pháp ra PNG', (tester) async {
    await _renderGrid(tester, 'build/aura_preview.png', const [
      CultivatorPreview(realm: 3, cpCode: 'cp_huyen_thien'), // qi
      CultivatorPreview(realm: 3, cpCode: 'cp_huyen_bang'), // ice
      CultivatorPreview(realm: 3, cpCode: 'cp_ngu_phong'), // wind
      CultivatorPreview(realm: 3, cpCode: 'cp_dia_sat'), // earth
      CultivatorPreview(realm: 3, cpCode: 'cp_thien_cang'), // sword
      CultivatorPreview(realm: 3, cpCode: 'cp_cuu_chuyen'), // gold
      CultivatorPreview(realm: 3, cpCode: 'cp_dai_dien'), // star
      CultivatorPreview(realm: 3, cpCode: 'cp_liet_hoa'), // fire
      CultivatorPreview(realm: 3, cpCode: 'cp_thanh_moc'), // leaf
    ], cols: 3);
  });

  // Bản phối màu vật phẩm: mọi giá trị trong itemArt phải có file webp thật
  // (sinh bằng tool/recolor_items.py), không thì icon rơi về sprite pixel xấu.
  test('mọi bản phối itemArt có ảnh webp', () {
    for (final art in itemArt.values.toSet()) {
      expect(File('assets/cult_items/$art.webp').existsSync(), isTrue,
          reason: art);
    }
    expect(itemArtKey('khong_co', 'gourd_big'), 'gourd');
    expect(itemArtKey('yp_tho_bo', 'robe'), 'robe_tho');
  });
}

Future<void> _renderGrid(WidgetTester tester, String out, List<Widget> cells,
    {int cols = 2}) async {
  final rows = (cells.length + cols - 1) ~/ cols;
  await tester.binding.setSurfaceSize(Size(cols * 320, rows * 170));
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: key,
      child: Container(
        color: const Color(0xFF10141F), // nền tối "Dạ Lam" ước lệ
        child: GridView.count(
          crossAxisCount: cols,
          childAspectRatio: 320 / 170,
          children: cells,
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
    File(out)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(out).lengthSync(), greaterThan(10000));
}
