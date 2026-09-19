// Soi 4 widget màn Tu Tiên (tách khỏi cultivation.dart 19/09) khi sửa UI:
//   flutter test test/cult_widgets_render_test.dart
// → build/cult_widgets_preview.png — MỞ RA NHÌN trước khi commit.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/cultivation.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/cultivation/hero_stage.dart';
import 'package:novel_reader/screens/cultivation/inventory.dart';
import 'package:novel_reader/screens/cultivation/realm_card.dart';

const Rec _st = {
  'race': 'nhan', 'gender': 'nam', 'realm': 3, 'stage': 4, 'exp': 1200, 'req': 5000,
  'rate': 12.5, 'elements': ['hoa', 'moc'], 'variant': null, 'linh_can': 3,
  'equipped': <String, dynamic>{}, 'stats': <String, dynamic>{}, 'tien_tier': 0,
  'ascended_at': null, 'halo_worn': null, 'halos': <String>[],
  'buff_until': null, 'buff_pct': 0, 'stone_until': null, 'stone_pct': 0,
};

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('render HeroStage/RealmCard/EquipRow/InventoryGrid ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    final key = GlobalKey();
    // font Google không tải được trong test (không mạng, không bundle) → chỉ nuốt lỗi font;
    // lỗi khác (tràn layout, ép kiểu) vẫn làm test đỏ.
    await runZonedGuarded(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cultStateProvider.overrideWith((ref) async => _st),
          cultInventoryProvider.overrideWith((ref) async => const <Rec>[]),
          isAdminProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SingleChildScrollView(
                child: Column(children: [
                  const SizedBox(height: 320, child: HeroStage(st: _st)),
                  RealmCard(
                    st: _st, exp: ValueNotifier(1200), busy: false, ascended: false,
                    onAdvance: () {}, onAscend: () {}, onAscendTier: () {},
                  ),
                  const EquipRow(st: _st),
                  const InventoryGrid(),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 500));
    }, (e, _) {
      if (!'$e'.contains('font')) throw e;
    });
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/cult_widgets_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });
}
