// Soi sheet Bộ sưu tập sau khi đổi sang ListView.builder (22/09):
//   flutter test test/collection_sheet_render_test.dart
// → build/collection_sheet_preview.png — MỞ RA NHÌN trước khi commit.
// Mục đích: chứng minh đổi cách dựng list KHÔNG đổi bố cục (nhãn mục, lưới ô,
// ô đã/chưa thu thập) so với bản ListView(children:).
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
import 'package:novel_reader/screens/cultivation/sheets_tu_tien.dart';

const _sprites = {
  'congphap': 'book', 'danduoc': 'pill', 'linhthach': 'jade',
  'vukhi': 'sword', 'yphuc': 'shield_pill', 'giay': 'pouch',
  'phapbao': 'compass', 'phapchu': 'array',
};

/// 8 loại × 5 ô, phẩm 1..5 — đủ để thấy nhãn mục, viền theo phẩm và ô xám chưa có.
List<Rec> _catalog() {
  final out = <Rec>[];
  var id = 1;
  for (final ty in cultTypeNames.keys) {
    for (var g = 1; g <= 5; g++) {
      out.add({
        'id': id++, 'type': ty, 'grade': g,
        'pixel': _sprites[ty], 'name': '${cultTypeNames[ty]} phẩm $g',
      });
    }
  }
  return out;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('render CollectionSheet ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    final items = _catalog();
    // sở hữu các ô id lẻ → cạnh nhau có cả ô sáng và ô xám để đối chiếu
    final owned = {for (final it in items) if ((it['id'] as int).isOdd) it['id'] as int};
    final key = GlobalKey();
    await runZonedGuarded(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cultCatalogProvider.overrideWith((ref) async => items),
          cultCollectionProvider.overrideWith((ref) async => owned),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: RepaintBoundary(key: key, child: const CollectionSheet()),
          ),
        ),
      ));
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 500));
    }, (e, _) {
      if (!'$e'.contains('font')) throw e;
    });

    // Lười thật: chỉ loại đầu dựng ô, loại cuối nằm ngoài màn nên chưa có ô nào.
    expect(find.text('CÔNG PHÁP  3/5'), findsOneWidget); // CultSectionLabel viết hoa
    expect(find.text('PHÁP CHÚ  3/5'), findsNothing);

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/collection_sheet_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });
}
